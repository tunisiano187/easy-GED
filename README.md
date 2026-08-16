# easy-GED — GED Privée Auto-Hébergée avec IA 🏠

> Scannez un courrier, il est analysé, classé et vous alertez automatiquement. 100% local, zéro cloud.

**Stack :** Paperless-ngx · n8n · Ollama (Mistral 7B) · PostgreSQL · Caddy · Docker  
**Hébergement :** VM Debian/Ubuntu sur Proxmox · Sauvegardes Proxmox PBS

---

## 🛒 Liste de Courses

### Matériel obligatoire (à acheter)

| Composant | Modèle recommandé | Lien | Prix estimé |
|---|---|---|---|
| 🖥️ **Serveur** | NiPoGi E3B (Ryzen 5 7430U, 16 Go, 512 Go) | [Amazon.fr →](https://www.amazon.fr/NiPoGi-Windows-Ordinateur-Bureau-Graphique/dp/B09X2PMLD9) | ~200 € |
| 💾 **SSD 1 To** (si le serveur livré sans) | Kingston NV2 M.2 NVMe 1 To | [Amazon.fr →](https://www.amazon.fr/Kingston-NVMe-PCIe-1000G-SNV2S/dp/B0BBWH1R8H) | ~55 € |
| 📄 **Scanner (option 1)** | Fujitsu ScanSnap iX1300 (compact, push SMB auto) | [Amazon.fr →](https://www.amazon.fr/ScanSnap-iX1300-Document-Automatique-Standards/dp/B09HS7WRNX) | ~250 € |
| 📄 **Scanner (option 2)** | Brother ADS-1800W (écran tactile, WiFi) | [Amazon.fr →](https://www.amazon.fr/Brother-ADS-1800W-Scanner-Compact-Portable/dp/B0CYTKGLRP) | ~200 € |

> **💡 Conseil achat serveur :** Si tu trouves un modèle avec Ryzen 7430U/7530U + 16 Go + 1 To intégré dans ta fourchette de prix, prends-le directement. Sinon, la combinaison NiPoGi E3B + SSD Kingston est la plus économique.

> **💡 Scanner :** Le ScanSnap iX1300 est le meilleur pour l'intégration murale (format U-turn, compact). Le Brother ADS-1800W a un écran tactile qui simplifie la configuration des raccourcis.

### Matériel déjà en ta possession

- ✅ Cluster Proxmox (le Mini PC serveur y sera intégré comme nouveau nœud)
- ✅ NAS Synology basique (DS220j/DS223) — stockage réseau si besoin

---

## 🏗️ Architecture

```
Scanner Physique
  └──► SMB (port 445) ──► Samba ──► /consume ──► Paperless-ngx
                                                        │ OCR Tesseract FR
Email IMAP (optionnel) ─────────────────────────────────►│ webhook
                                                        ▼
                                                  n8n Workflow
                                              ┌────────┼────────┐
                                              ▼        ▼        ▼
                                           Ollama  Paperless PostgreSQL
                                         Mistral 7B  MAJ       historique
                                              │
                                  ┌───────────┴───────────┐
                                  ▼                       ▼
                           facture reçue           rappel reçu
                           Tag "À Payer"        vérif. si payée
                           alerte échéance     → alerte litige si oui
                                  │
                        Email + Telegram + QR Code EPC

Proxmox PBS ◄── Snapshots VM quotidiens (Proxmox Backup Server)
```

---

## 🚀 Installation Rapide (Méthode Automatique)

### Prérequis
- VM Debian 12 ou Ubuntu 24.04 LTS sur Proxmox (**AMD64**)
- **VM recommandée :** 8 vCPUs, 12 Go RAM, 2 disques (32 Go OS + 150 Go données)
- Accès root ou sudo
- Connexion internet (téléchargement images Docker + modèle Mistral ~4.1 Go)

### Une seule commande

```bash
curl -sSL https://raw.githubusercontent.com/tunisiano187/easy-GED/main/scripts/install.sh | sudo bash
```

Le script fera tout automatiquement :
1. ✅ Installe Docker Engine
2. ✅ Clone le dépôt dans `/opt/easy-ged`
3. ✅ Génère les clés secrètes
4. ✅ Démarre tous les conteneurs (dont Caddy HTTPS)
5. ✅ Télécharge Mistral 7B (~4.1 Go)
6. ✅ Crée les champs personnalisés Paperless
7. ✅ Affiche les URLs d'accès HTTP et HTTPS

---

## ⚙️ Création de la VM sur Proxmox

### 1. Créer la VM

Dans l'interface Proxmox de ton nouveau serveur (ou depuis l'UI web du cluster) :

```
Clic droit sur le nœud → Create VM

Général :
  VM ID : 100 (ou suivant disponible)
  Name  : easy-ged

OS :
  ISO : Debian 12 (télécharger sur https://www.debian.org/CD/netinst/)
  Type : Linux / 6.x - 2.6 Kernel

Système :
  Machine  : Default (i440fx)
  BIOS     : SeaBIOS
  Qemu Agent : ✓ (activer)

Disques :
  Disque 1 (OS) : 32 Go — format RAW ou QCOW2
  Disque 2 (Données) : 150 Go minimum — sur le stockage NVMe du nouveau serveur

CPU :
  Sockets : 1
  Cores   : 8 (utilise les 4C/8T du Ryzen 7330U)
  Type    : host (performances maximales)

Mémoire :
  RAM : 12288 Mo (12 Go) — laisse ~4 Go pour Proxmox

Réseau :
  Bridge : vmbr0 (LAN principal, accès NAS + scanner)
  Model  : VirtIO (paravirtualisé, meilleure performance)
```

### 2. Installer Debian

Choisir l'installation minimale (sans interface graphique), puis :

```bash
# Après installation Debian — se connecter en SSH ou via console Proxmox
apt update && apt upgrade -y
apt install -y qemu-guest-agent
systemctl enable --now qemu-guest-agent

# Optionnel : activer SSH
apt install -y openssh-server
```

---

## 🔧 Configuration Manuelle

### Configurer le fichier .env

```bash
cd /opt/easy-ged
nano .env
```

Valeurs à renseigner obligatoirement :

```bash
PAPERLESS_ADMIN_PASSWORD=ton_mot_de_passe_paperless
POSTGRES_PASSWORD=mot_de_passe_base_de_donnees
SMTP_HOST=smtp.ton-fournisseur.com  # ex: smtp.gmail.com, smtp.ovh.net…
SMTP_PORT=587
SMTP_USER=ton@email.com
SMTP_PASSWORD=mot_de_passe_application  # pour Gmail : "mot de passe d'application"
NOTIFICATION_EMAIL=ton@email.com
TELEGRAM_BOT_TOKEN=123456:ABC...    # depuis @BotFather
TELEGRAM_CHAT_ID=123456789          # ton Chat ID Telegram
SCANNER_SMB_USER=scanner            # identifiant SMB que tu choisis
SCANNER_SMB_PASSWORD=mdp_scanner    # mot de passe SMB que tu choisis
```

### Créer un bot Telegram (si pas encore fait)

1. Ouvrir Telegram → chercher `@BotFather`
2. Taper `/newbot` → donner un nom (ex: `easy-GED Home`)
3. Copier le token dans `TELEGRAM_BOT_TOKEN`
4. Aller sur `https://api.telegram.org/bot<TON_TOKEN>/getUpdates`
5. Envoyer un message à ton bot depuis Telegram
6. Rafraîchir la page → copier le `chat.id` dans `TELEGRAM_CHAT_ID`

### Créer un mot de passe d'application Gmail (si SMTP Gmail)

1. Compte Google → Sécurité → Validation en 2 étapes (activer si pas fait)
2. Sécurité → Mots de passe d'application
3. Créer un mot de passe pour "easy-GED"
4. Copier dans `SMTP_PASSWORD`

---

## 📄 Configurer le Scanner

### ScanSnap iX1300

1. Installer **ScanSnap Home** sur un PC temporairement (pour la config initiale)
2. Scanner → Profil → Nouvelle destination : **Dossier réseau (SMB)**
3. Renseigner :
   - Adresse : `\\IP_VM\consume`  (ex: `\\192.168.1.50\consume`)
   - Utilisateur : valeur de `SCANNER_SMB_USER` (ex: `scanner`)
   - Mot de passe : valeur de `SCANNER_SMB_PASSWORD`
4. Tester → un fichier doit apparaître dans Paperless automatiquement

### Brother ADS-1800W

1. Accéder à l'interface web du scanner : `http://IP_SCANNER`
2. Numériser → Vers réseau (SMB)
3. Renseigner les mêmes infos que ci-dessus
4. Sauvegarder → Tester depuis l'écran tactile du scanner

---

## 📥 Importer le Workflow n8n

1. Ouvrir n8n : `http://IP_VM:5678`
2. Se connecter (credentials définis dans `.env`)
3. Menu → **Workflows** → **Import from File**
4. Sélectionner : `n8n/workflows/ged-main-workflow.json`
5. Configurer les credentials :
   - **Paperless API Token** → créer dans Paperless (Paramètres → Tokens API → Ajouter)
   - **Telegram Bot** → entrer le token du bot
   - **SMTP** → entrer les informations email
6. Activer le workflow (toggle ON en haut à droite)
7. Copier l'URL du webhook affiché dans le nœud "Webhook Paperless"

---

## ✅ Tests de Validation

```bash
# 1. Vérifier que tous les conteneurs sont en bonne santé
docker compose ps

# 2. Tester l'accès aux services
curl -sf http://localhost:8000 && echo "✓ Paperless OK"
curl -sf http://localhost:5678 && echo "✓ n8n OK"
curl -sf http://localhost:9000 && echo "✓ Portainer OK"
curl -sf http://localhost:11434/api/tags && echo "✓ Ollama OK"

# 3. Tester l'extraction IA
curl -s -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{"model":"mistral:7b-instruct","prompt":"Extrais en JSON: Facture EDF de 125.50€ du 15/01/2025","stream":false}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['response'][:200])"

# 4. Tester la chaîne complète : copier un PDF dans le dossier consume
cp /chemin/vers/une_facture.pdf /opt/easy-ged/consume/
# → Attendre 30 secondes → Vérifier dans Paperless que les champs sont remplis
# → Vérifier la notification Telegram reçue
```

---

## 🔐 Accès aux Interfaces

| Interface | URL | Identifiants |
|---|---|---|
| **Paperless** (GED) | `http://IP_VM:8000` | admin / PAPERLESS_ADMIN_PASSWORD |
| **n8n** (workflows) | `http://IP_VM:5678` | N8N_BASIC_AUTH_USER / PASSWORD |
| **Portainer** (Docker) | `http://IP_VM:9000` | Créer au premier accès |
| **Ollama** (API IA) | `http://IP_VM:11434` | Pas d'auth |

---

## 🔄 Opérations Courantes

```bash
# Démarrer/arrêter la stack
docker compose up -d
docker compose down

# Voir les logs en temps réel
docker compose logs -f paperless-ngx
docker compose logs -f n8n
docker compose logs -f ged-ollama

# Mettre à jour Paperless (Watchtower le fait automatiquement chaque nuit)
docker compose pull paperless-ngx
docker compose up -d paperless-ngx

# Marquer une facture comme payée
# → Directement dans l'interface Paperless (champ "statut_paiement")
```

### Sauvegardes (Proxmox PBS)

Les sauvegardes sont gérées par **Proxmox Backup Server** — elles couvrent la VM entière :

1. Dans l'interface Proxmox : **Datacenter → Backup → Add**
2. Sélectionner le nœud et la VM `easy-ged`
3. Schedule recommandé : **Daily à 04:00**
4. Rétention conseillée : `keep-daily=7, keep-weekly=4, keep-monthly=3`
5. Vérifier que le datastore PBS a assez d'espace (VM ~50-80 Go compressée)

---

## 🚨 Troubleshooting

| Problème | Solution |
|---|---|
| Paperless ne démarre pas | `docker compose logs paperless-ngx` → souvent un problème de PAPERLESS_SECRET_KEY |
| Ollama lent | Normal sur CPU — première génération : 1-3 min. Les suivantes sont plus rapides. |
| Webhook n8n pas reçu | Vérifier que `N8N_WEBHOOK_BASE_URL` contient l'IP de la VM (pas `localhost`) |
| Scanner ne pousse pas | Vérifier le pare-feu VM : `ufw allow 445` et `ufw allow 139` |
| Caddy : erreur de cert | Ajouter les hostnames `.home.local` dans `/etc/hosts` du PC client |
| Pas de notification Telegram | Tester le bot : `curl https://api.telegram.org/bot<TOKEN>/getMe` |
| Sauvegarde PBS échoue | Vérifier la connectivité Proxmox → PBS et l'espace disque du datastore |

---

## 🗺️ Feuille de Route

### v1 (actuelle) ✅
- Scanner → Paperless via SMB
- OCR + analyse Mistral 7B
- Champs personnalisés (montant, IBAN, échéance, statut)
- Notifications email + Telegram
- Détection rappels abusifs / litiges
- Sauvegardes via Proxmox PBS (niveau VM)
- HTTPS local avec Caddy (`*.home.local`, certificats auto-signés)
- Bilan mensuel automatique (cron n8n, 1er du mois à 8h)

### v2 (prévue)
- [ ] Accès externe sécurisé via Tailscale
- [ ] Amélioration OCR avec Surya/Docling (meilleure précision sur documents complexes)
- [ ] QR Code EPC généré localement (sans appel externe)
- [ ] Dashboard budget Grafana (visualisation des dépenses)
- [ ] Notification push mobile (Gotify ou Ntfy auto-hébergé)

---

## 🔌 Monitoring UPS APC (NUT)

> **Optionnel** — Requis uniquement si vous avez un onduleur APC et souhaitez monitorer son état.

Le monitoring UPS via NUT nécessite un **accès USB physique** à l'onduleur.
Il ne peut **pas** tourner dans la VM Proxmox sans USB passthrough.

**Déployer NUT sur un device avec USB physique** (Raspberry Pi 5, Mini PC host, etc.) :

```bash
# Sur le device avec l'UPS branché en USB
git clone https://github.com/tunisiano187/easy-GED /opt/easy-ged
cd /opt/easy-ged

# Identifier l'UPS : lsusb | grep -i apc
# Copier et adapter la config NUT
cp nut/ups.conf.example nut/ups.conf
cp nut/upsd.users.example nut/upsd.users
nano nut/upsd.users   # ← Changer CHANGER_CE_MOT_DE_PASSE

# Renseigner le mot de passe dans .env
echo "NUT_UPSD_PASSWORD=mon_mot_de_passe" >> .env

# Lancer le stack NUT
docker compose -f docker-compose.nut.yml up -d
```

**Accès :**
- Interface web NUT : `http://IP_DEVICE:6543`
- Serveur NUT (pour clients Proxmox/VMs) : `IP_DEVICE:3493`

**Configurer Proxmox pour utiliser le NUT distant :**
```bash
# Sur chaque nœud Proxmox
apt install nut-client -y
# Configurer /etc/nut/upsmon.conf :
# MONITOR apc@IP_DEVICE 1 upsmon MOT_DE_PASSE slave
```

---

## 📜 Licence

Ce projet est open-source, usage personnel. Voir [LICENSE](LICENSE).
