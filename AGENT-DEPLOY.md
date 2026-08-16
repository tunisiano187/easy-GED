# AGENT-DEPLOY — Prompt de Déploiement easy-GED

> **Mode d'emploi** : Copier le bloc "PROMPT AGENT" ci-dessous et le donner à un agent IA
> (Claude Code, Codex, etc.) avec accès SSH à ta VM Proxmox.
> Adapter les variables en majuscules à ta configuration réelle.

---

## 📋 Variables à adapter avant de coller le prompt

```
VM_IP=192.168.1.XX           # IP de ta VM Debian/Ubuntu sur Proxmox
VM_USER=root                 # ou ton user sudo
DEPLOY_MODE=all-in-one       # ou "split" si tu as un Raspberry Pi 5
PI5_IP=192.168.1.XX          # IP du Pi 5 (uniquement si DEPLOY_MODE=split)
CLOUDFLARE=false             # true si tu veux activer Cloudflare Tunnel
REPO_URL=https://github.com/tunisiano187/easy-GED
```

---

## 🤖 PROMPT AGENT — Copier-coller ci-dessous

```
Tu es un agent DevOps expert. Ta mission est de déployer le système easy-GED
(GED privée auto-hébergée) sur ma VM Linux en suivant exactement ce plan.

## Directives d'exécution

- Utilise des sous-agents pour toutes les tâches pouvant s'exécuter en parallèle
  (ex: déploiement VM + Pi simultané, tests de validation en parallèle)
- Chaque sous-agent doit avoir un objectif précis et rapporter son statut
- Si un sous-agent échoue, stopper et rapporter avant de continuer
- Pour les commandes longues (docker pull, modèle Mistral), lancer en arrière-plan
  et vérifier la fin avant de passer à l'étape suivante

## Contexte

Système : VM Debian/Ubuntu AMD64 sur Proxmox
IP de la VM : [REMPLACER PAR L'IP]
Utilisateur SSH : [REMPLACER PAR LE USER]
Mode déploiement : [all-in-one OU split]
Cloudflare Tunnel : [oui/non]
Dépôt : https://github.com/tunisiano187/easy-GED

## Étapes à exécuter dans l'ordre

## Étapes à exécuter dans l'ordre

### ÉTAPE 0 — Lecture du contexte (obligatoire)
Lire le fichier CLAUDE.md dans le dépôt pour avoir le contexte complet du projet.
Adapter le plan d'exécution en fonction du DEPLOY_MODE choisi :
- all-in-one : exécuter ÉTAPES 1-13 sur la VM uniquement
- split : lancer ÉTAPES 1-13 sur VM et ÉTAPE 14 (Pi 5) en parallèle via sous-agents

#### Détection automatique — Systèmes de monitoring et Home Assistant

Avant toute chose, scanner le réseau local pour détecter des systèmes existants :

```bash
# Détecter Home Assistant (port 8123)
curl -s --connect-timeout 2 http://[IP_LAN]:8123/api/ -o /dev/null -w "%{http_code}"

# Détecter Uptime Kuma (port 3001)
curl -s --connect-timeout 2 http://[IP_LAN]:3001/ -o /dev/null -w "%{http_code}"

# Détecter Prometheus (port 9090) ou Grafana (port 3000)
curl -s --connect-timeout 2 http://[IP_LAN]:9090/-/healthy -o /dev/null -w "%{http_code}"
curl -s --connect-timeout 2 http://[IP_LAN]:3000/api/health -o /dev/null -w "%{http_code}"
```

Si Home Assistant **ou** une solution de monitoring est détectée (ou si l'utilisateur en
confirme l'existence), **proposer systématiquement** d'ajouter l'intégration NUT en ÉTAPE 15
et l'inclure dans le plan d'exécution. Ne pas l'exécuter sans confirmation de l'utilisateur.

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
  - SCANNER_SMB_USER, SCANNER_SMB_PASSWORD (identifiants scanner)
  - PAPERLESS_URL (http://IP_VM:8000 - IP de la VM)
  - N8N_WEBHOOK_BASE_URL (http://IP_VM:5678)
  - DEPLOY_MODE (all-in-one ou split)
  - Si DEPLOY_MODE=split : PI5_HOST, PI5_SSH_USER
  - Si Cloudflare voulu : CLOUDFLARE_TUNNEL_TOKEN

### ÉTAPE 5 — Rendre les scripts exécutables
chmod +x scripts/*.sh
chmod +x paperless/init/*.sh
chmod +x paperless/scripts/*.sh

### ÉTAPE 6 — Démarrer la stack Docker
docker compose pull
docker compose up -d

# Si Cloudflare Tunnel activé :
# docker compose --profile cloudflare up -d

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

### ÉTAPE 9 — Importer les workflows n8n
- Ouvrir n8n sur http://IP_VM:5678
- Aller dans Workflows → Import from File
- Importer le fichier : n8n/workflows/ged-main-workflow.json → Activer (toggle ON)
- Importer le fichier : n8n/workflows/ged-budget-mensuel.json → Activer (toggle ON)
- Copier l'URL du webhook affiché dans le nœud "Webhook Trigger" du workflow principal

### ÉTAPE 10 — Configurer le webhook Paperless → n8n
Dans le fichier .env, vérifier que PAPERLESS_URL est correct, puis :
docker compose restart paperless-ngx

Le script notify-n8n.sh appellera automatiquement n8n après chaque document ingéré.

### ÉTAPE 11 — Sauvegardes (Proxmox PBS)
Les sauvegardes sont gérées par **Proxmox Backup Server (PBS)** au niveau VM.
Aucune configuration requise sur la VM elle-même.

Informer l'utilisateur qu'il doit configurer un job PBS depuis l'interface Proxmox :
- Datacenter → Backup → Add
- Choisir le nœud, la VM easy-GED (ID 100 ou autre)
- Schedule recommandé : daily à 04:00
- Rétention : keep-daily=7, keep-weekly=4

Vérifier que le PBS est accessible depuis le cluster Proxmox avant de clore le déploiement.

### ÉTAPE 12 — Tests de validation
Exécuter ces tests et rapporter le résultat de chacun :

TEST 1 : Tous les conteneurs sont healthy
  docker compose ps | grep -E "(healthy|running)"
  → Attendu : 9 lignes (tous les services dont Caddy)

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

### ÉTAPE 14 — Déploiement Pi 5 (uniquement si DEPLOY_MODE=split)
⚡ Lancer en parallèle avec les ÉTAPES 7-12 via un sous-agent dédié.

Sous-agent Pi 5 (SSH vers PI5_HOST) :
- Vérifier que le Pi 5 est accessible : ssh PI5_SSH_USER@PI5_HOST
- Lancer le script d'installation :
  curl -sSL https://raw.githubusercontent.com/tunisiano187/easy-GED/main/scripts/install-pi.sh | sudo bash
- Configurer le .env sur le Pi :
  - PAPERLESS_URL=http://IP_VM:8000
  - PAPERLESS_API_TOKEN=[token créé dans Paperless à l'ÉTAPE 8]
  - SCANNER_SMB_USER / SCANNER_SMB_PASSWORD
- Vérifier le statut : docker compose -f docker-compose.pi.yml ps
- Tester : déposer un fichier test dans \\PI5_IP\consume → vérifier dans Paperless

### ÉTAPE 15 — Intégration NUT avec systèmes existants (si détectés à l'ÉTAPE 0)

> Cette étape est **conditionnelle** : n'exécuter que si un onduleur APC est configuré
> (profil `nut` actif) **ET** qu'un système de monitoring ou Home Assistant a été détecté.
> Toujours confirmer avec l'utilisateur avant d'apporter des modifications à un système existant.

#### Option A — Home Assistant

Si Home Assistant est détecté ou confirmé par l'utilisateur, proposer l'ajout de
l'intégration NUT pour afficher l'état de l'onduleur dans HA (niveau de charge, état,
autonomie restante, tension) et déclencher des automatisations en cas de coupure secteur.

**Méthode recommandée (via l'API HA REST) :**

```bash
# Vérifier la version HA et l'accessibilité de l'API
HA_URL="http://[HA_IP]:8123"
HA_TOKEN="[LONG_LIVED_ACCESS_TOKEN]"   # Profil HA → Sécurité → Tokens longue durée

curl -s -H "Authorization: Bearer $HA_TOKEN" "$HA_URL/api/" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print('HA', d.get('version','?'))"
```

Instructions à donner à l'utilisateur pour ajouter l'intégration manuellement :
```
Home Assistant → Paramètres → Appareils et services → + Ajouter une intégration
→ Rechercher "NUT" → Network UPS Tools
→ Hôte : [IP_PI]   Port : 3493
→ Utilisateur : upsmon   Mot de passe : [NUT_UPSD_PASSWORD]
→ Valider → sélectionner l'UPS détecté
```

Si l'utilisateur le demande, générer également une automatisation HA basique :
- Déclencheur : état UPS passe à "OL DISCHRG" (sur batterie)
- Action : notification mobile "⚡ Coupure secteur — passage sur batterie"

#### Option B — Prometheus / Grafana

Si Prometheus ou Grafana est détecté, ajouter `nut-exporter` en tant que nouveau
service Docker sur le Pi 5 (ou sur la VM si mode all-in-one) :

```yaml
# Ajouter dans docker-compose.pi.yml sous le profil "nut"
nut-exporter:
  profiles: ["nut"]
  image: hon96/nut-exporter:latest
  container_name: pi-nut-exporter
  restart: unless-stopped
  environment:
    NUT_EXPORTER_SERVER: nut-upsd
    NUT_EXPORTER_PORT: 3493
    NUT_EXPORTER_USERNAME: ${NUT_UPSD_USER:-upsmon}
    NUT_EXPORTER_PASSWORD: ${NUT_UPSD_PASSWORD}
  ports:
    - "9199:9199"   # métriques Prometheus sur /metrics
  depends_on:
    - nut-upsd
  networks:
    - pi-network
```

Puis ajouter le scrape job dans la config Prometheus existante :
```yaml
# prometheus.yml — ajouter dans scrape_configs :
- job_name: 'nut'
  static_configs:
    - targets: ['[IP_PI]:9199']
      labels:
        instance: 'ups-apc'
```

Si Grafana est présent, proposer d'importer le dashboard NUT communautaire
(ID Grafana : **13822** — "NUT UPS Monitoring").

#### Option C — Uptime Kuma

Si Uptime Kuma est détecté, proposer d'ajouter deux moniteurs :
- **Port TCP 3493** sur IP_PI → vérifie que le démon NUT répond
- **HTTP 6543** sur IP_PI → vérifie l'interface web WebNUT (si profil nut actif)

```bash
# Exemple via l'API Uptime Kuma (si API activée)
# Moniteur TCP pour le démon NUT
curl -s -X POST http://[UK_IP]:3001/api/monitors \
  -H "Content-Type: application/json" \
  -d '{"type":"port","name":"NUT UPS (Pi 5)","hostname":"[IP_PI]","port":3493,"interval":60}'
```

### ÉTAPE 13 — Rapport final
Afficher un résumé avec :
- ✓/✗ pour chaque test
- URLs d'accès :
  - Paperless : http://[IP_VM]:8000 (user: admin)
  - n8n : http://[IP_VM]:5678
  - Portainer : http://[IP_VM]:9000
  - Ollama : http://[IP_VM]:11434
  - (HTTPS) paperless.home.local / n8n.home.local / portainer.home.local (via Caddy)
- Prochaines étapes manuelles restantes :
  1. Configurer le scanner (voir README.md section "Configuration Scanner")
  2. Importer le workflow n8n manuellement via l'interface web
  3. Tester avec un premier document

## Utilisation des sous-agents

L'agent principal doit déléguer les tâches suivantes à des sous-agents :

| Tâche | Sous-agent | Parallèle avec |
|---|---|---|
| Déploiement Pi 5 (si split) | `sous-agent-pi` | ÉTAPES 7-12 VM |
| Tests de validation | `sous-agent-tests` | après ÉTAPE 12 |
| Configuration Cloudflare (si activé) | `sous-agent-cf` | après stack up |
| Intégration NUT HA/monitoring (si détecté) | `sous-agent-nut-integration` | après ÉTAPE 14 |

Instructions pour les sous-agents :
- Chaque sous-agent reçoit son contexte complet (IP, credentials, objectif)
- Il rapporte : succès ✓ / échec ✗ / avertissement ⚠ pour chaque test
- En cas d'échec, il inclut les logs complets pour diagnostic
- L'agent principal attend la completion de tous les sous-agents avant le rapport final

## En cas d'erreur

- Si un conteneur ne démarre pas : docker compose logs [service] pour diagnostiquer
- Si Paperless ne répond pas après 3 minutes : docker compose restart paperless-ngx
- Si Ollama est lent : c'est normal sur CPU, la première génération prend 1-2 minutes
- Si le webhook n8n ne reçoit pas : vérifier que N8N_WEBHOOK_BASE_URL dans .env est l'IP de la VM (pas localhost)

## Important

- Ne jamais committer le fichier .env dans git
- En cas de redémarrage VM : docker compose up -d suffit (restart: unless-stopped est configuré)
- Les sauvegardes sont entièrement gérées par Proxmox PBS — aucun script local nécessaire
```

---

## 🔧 Utilisation avec Claude Code (recommandé)

Claude Code supporte nativement les sous-agents — en mode split, il déploiera
la VM et le Pi 5 en parallèle automatiquement.

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
- [ ] Identifiants SMB scanner (tu les choisiras toi-même)
- [ ] PBS configuré sur le cluster Proxmox (sauvegardes VM)
