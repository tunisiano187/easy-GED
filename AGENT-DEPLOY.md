# AGENT-DEPLOY — Prompt de Déploiement easy-GED

> **Mode d'emploi** : Copier le bloc "PROMPT AGENT" ci-dessous et le donner à un agent IA
> (Claude Code, Codex, etc.) avec accès SSH à ta VM Proxmox.
> Adapter les variables en majuscules à ta configuration réelle.

---

## 📋 Variables à adapter avant de coller le prompt

```
VM_IP=192.168.1.XX           # IP de ta VM Debian/Ubuntu sur Proxmox
VM_USER=root                 # ou ton user sudo
REPO_URL=https://github.com/tunisiano187/easy-GED
```

---

## 🤖 PROMPT AGENT — Copier-coller ci-dessous

```
Tu es un agent DevOps expert. Ta mission est de déployer le système easy-GED
(GED privée auto-hébergée) sur ma VM Linux en suivant exactement ce plan.

## Contexte

Système : VM Debian/Ubuntu AMD64 sur Proxmox
IP de la VM : [REMPLACER PAR L'IP]
Utilisateur SSH : [REMPLACER PAR LE USER]
Dépôt : https://github.com/tunisiano187/easy-GED

## Étapes à exécuter dans l'ordre

### ÉTAPE 1 — Vérification système
- Vérifier que le système est bien Debian/Ubuntu AMD64
- Vérifier qu'il y a au moins 8 Go de RAM disponible
- Vérifier qu'il y a au moins 50 Go d'espace disque libre
- Mettre à jour les paquets : apt update && apt upgrade -y

### ÉTAPE 2 — Installation Docker
- Installer Docker Engine (méthode officielle Docker pour Debian/Ubuntu)
  URL : https://docs.docker.com/engine/install/debian/
- Installer Docker Compose plugin (inclus dans Docker Engine récent)
- Ajouter l'utilisateur courant au groupe docker : usermod -aG docker $USER
- Vérifier : docker --version && docker compose version

### ÉTAPE 3 — Cloner le dépôt
- Cloner dans /opt/easy-ged :
  git clone https://github.com/tunisiano187/easy-GED /opt/easy-ged
- cd /opt/easy-ged

### ÉTAPE 4 — Configurer l'environnement
- Copier .env.example en .env : cp .env.example .env
- Générer et remplacer les clés secrètes :
  - PAPERLESS_SECRET_KEY : openssl rand -hex 32
  - N8N_ENCRYPTION_KEY : openssl rand -hex 24
- Dans le .env, demander à l'utilisateur les valeurs pour :
  - PAPERLESS_ADMIN_PASSWORD (mot de passe interface Paperless)
  - POSTGRES_PASSWORD (mot de passe base de données)
  - SMTP_HOST, SMTP_USER, SMTP_PASSWORD (email pour notifications)
  - TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID (notifications Telegram)
  - NAS_SMB_HOST, NAS_SMB_SHARE, NAS_SMB_USER, NAS_SMB_PASSWORD (backup NAS)
  - RESTIC_PASSWORD (chiffrement sauvegardes - À NE PAS PERDRE)
  - SCANNER_SMB_USER, SCANNER_SMB_PASSWORD (identifiants scanner)
  - PAPERLESS_URL (http://IP_VM:8000 - IP de la VM)
  - N8N_WEBHOOK_BASE_URL (http://IP_VM:5678)

### ÉTAPE 5 — Rendre les scripts exécutables
chmod +x scripts/*.sh
chmod +x paperless/init/*.sh
chmod +x paperless/scripts/*.sh

### ÉTAPE 6 — Démarrer la stack Docker
docker compose pull
docker compose up -d

Attendre que tous les services soient healthy (max 5 minutes) :
docker compose ps

Si un service n'est pas healthy après 5 minutes, afficher ses logs :
docker compose logs [nom-service]

### ÉTAPE 7 — Télécharger le modèle IA Mistral
./scripts/pull-model.sh

Note : ~4.1 Go, peut prendre 10-30 minutes selon la connexion.
Attendre la fin complète avant de continuer.

### ÉTAPE 8 — Créer les champs personnalisés Paperless
Attendre 30 secondes que Paperless soit complètement initialisé, puis :
./paperless/init/create-custom-fields.sh

Vérifier que les 7 champs sont créés :
emetteur, numero_facture, montant_total, date_echeance, iban, communication, statut_paiement

### ÉTAPE 9 — Importer le workflow n8n
- Ouvrir n8n sur http://IP_VM:5678
- Aller dans Workflows → Import from File
- Importer le fichier : n8n/workflows/ged-main-workflow.json
- Activer le workflow (toggle ON)
- Copier l'URL du webhook Paperless affiché dans le nœud "Webhook Trigger"

### ÉTAPE 10 — Configurer le webhook Paperless → n8n
Dans le fichier .env, vérifier que PAPERLESS_URL est correct, puis :
docker compose restart paperless-ngx

Le script notify-n8n.sh appellera automatiquement n8n après chaque document ingéré.

### ÉTAPE 11 — Configurer les sauvegardes automatiques
Installer restic : apt install restic -y

Ajouter le cron de sauvegarde (4h00 chaque nuit) :
echo "0 4 * * * root /opt/easy-ged/scripts/backup.sh >> /var/log/easy-ged-backup.log 2>&1" > /etc/cron.d/easy-ged-backup
chmod 644 /etc/cron.d/easy-ged-backup

Installer cifs-utils pour le montage NAS :
apt install cifs-utils -y

### ÉTAPE 12 — Tests de validation
Exécuter ces tests et rapporter le résultat de chacun :

TEST 1 : Tous les conteneurs sont healthy
  docker compose ps | grep -E "(healthy|running)"
  → Attendu : 8 lignes (tous les services)

TEST 2 : Paperless accessible
  curl -s -o /dev/null -w "%{http_code}" http://localhost:8000
  → Attendu : 200

TEST 3 : n8n accessible
  curl -s -o /dev/null -w "%{http_code}" http://localhost:5678
  → Attendu : 200 ou 401

TEST 4 : Ollama avec Mistral chargé
  curl -s http://localhost:11434/api/tags | python3 -c "import sys,json; models=[m['name'] for m in json.load(sys.stdin).get('models',[])]; print('OK' if any('mistral' in m for m in models) else 'ERREUR: Mistral non trouvé')"
  → Attendu : OK

TEST 5 : Test extraction IA (français)
  curl -s -X POST http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d '{"model":"mistral:7b-instruct","prompt":"Réponds uniquement avec {\"status\":\"ok\"}","stream":false}' \
    | python3 -c "import sys,json; r=json.load(sys.stdin); print('OK' if 'ok' in r.get('response','') else 'ERREUR')"
  → Attendu : OK

TEST 6 : Partage SMB scanner accessible
  smbclient -L localhost -U [SCANNER_SMB_USER]%[SCANNER_SMB_PASSWORD] -N 2>/dev/null | grep consume
  → Attendu : ligne avec "consume"

### ÉTAPE 13 — Rapport final
Afficher un résumé avec :
- ✓/✗ pour chaque test
- URLs d'accès :
  - Paperless : http://[IP_VM]:8000 (user: admin)
  - n8n : http://[IP_VM]:5678
  - Portainer : http://[IP_VM]:9000
  - Ollama : http://[IP_VM]:11434
- Prochaines étapes manuelles restantes :
  1. Configurer le scanner (voir README.md section "Configuration Scanner")
  2. Importer le workflow n8n manuellement via l'interface web
  3. Tester avec un premier document

## En cas d'erreur

- Si un conteneur ne démarre pas : docker compose logs [service] pour diagnostiquer
- Si Paperless ne répond pas après 3 minutes : docker compose restart paperless-ngx
- Si Ollama est lent : c'est normal sur CPU, la première génération prend 1-2 minutes
- Si le webhook n8n ne reçoit pas : vérifier que N8N_WEBHOOK_BASE_URL dans .env est l'IP de la VM (pas localhost)

## Important

- Ne jamais committer le fichier .env dans git
- Le mot de passe RESTIC_PASSWORD est CRITIQUE : le noter dans un gestionnaire de mots de passe
- En cas de redémarrage VM : docker compose up -d suffit (restart: unless-stopped est configuré)
```

---

## 🔧 Utilisation avec Claude Code (recommandé)

Si tu utilises **Claude Code** avec accès SSH à la VM :

```bash
# Dans le terminal de la VM (ou via SSH)
cd /opt/easy-ged
claude  # Lance Claude Code dans le contexte du projet
```

Claude Code lira automatiquement `CLAUDE.md` et aura tout le contexte nécessaire.
Tu pourras ensuite dire : *"Déploie easy-GED sur cette machine"* et il suivra ce guide.

## 🔧 Utilisation avec un autre agent IA

1. Copier le contenu du bloc "PROMPT AGENT" ci-dessus
2. Remplacer `[REMPLACER PAR L'IP]` et `[REMPLACER PAR LE USER]`  
3. Donner le prompt à l'agent avec accès SSH à ta VM
4. L'agent demandera les mots de passe/tokens manquants et exécutera chaque étape

## 📝 Informations à préparer avant de lancer l'agent

Pour que le déploiement soit entièrement non-interactif, prépare ces informations :

- [ ] IP de la VM Proxmox GED
- [ ] Mots de passe à définir : Paperless admin, PostgreSQL, n8n
- [ ] Credentials SMTP (email pour notifications)
- [ ] Token bot Telegram + Chat ID
- [ ] IP + identifiants NAS Synology (dossier de backup)
- [ ] Identifiants SMB scanner (tu les choisiras toi-même)
- [ ] Mot de passe Restic (chiffrement backup — à noter précieusement)
