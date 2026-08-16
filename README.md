# easy-GED — GED Privée Auto-Hébergée avec IA 🏠

> Scannez un courrier, il est analysé, classé et vous alertez automatiquement. 100% local, zéro cloud.

**Stack :** Paperless-ngx · n8n · Ollama (Mistral 7B) · PostgreSQL · Caddy · Cloudflare Tunnel · Docker  
**Hébergement :** VM Debian/Ubuntu sur Proxmox · Sauvegardes Proxmox PBS  
**Modes :** All-in-one (VM seule) ou Split (Pi 5 scanner + VM GED)

---

## 🛒 Liste de Courses

### Matériel obligatoire (à acheter)

> ⚠️ **Les prix Amazon varient quotidiennement** — vérifier le prix au moment de l'achat.

| Composant | Modèle recommandé | Recherche Amazon.fr |
|---|---|---|
| 🖥️ **Serveur Mini PC** | Mini PC Ryzen 7430U/7530U, 16 Go RAM, **1 To NVMe** (viser 1 To intégré) | [Chercher →](https://www.amazon.fr/s?k=mini+pc+ryzen+7430U+16go+1to) |
| 💾 **SSD 1 To** (si serveur livré en 512 Go) | Kingston NV2 ou NV3, M.2 NVMe 1 To | [Chercher →](https://www.amazon.fr/s?k=ssd+nvme+m2+1to+kingston) |
| 🍓 **Raspberry Pi 5** (mode Split) | Raspberry Pi 5 — **8 Go RAM** recommandé (Pi 5 Model B 8GB) | [Voir →](https://www.amazon.fr/s?k=raspberry+pi+5+8go) |
| 🔌 **Alimentation Pi 5** (mode Split) | Alimentation officielle 27 W USB-C (Raspberry Pi 27W Power Supply) — **obligatoire** pour le Pi 5 | [Voir →](https://www.amazon.fr/s?k=raspberry+pi+5+alimentation+27w+usb-c) |
| 💳 **microSD Pi 5** (mode Split) | microSD 32 Go classe A2 minimum (ex: SanDisk Extreme 32 Go) | [Chercher →](https://www.amazon.fr/s?k=microsd+32go+classe+a2+sandisk) |
| 📄 **Scanner (option WiFi/SMB)** | Fujitsu ScanSnap iX1300 — compact, pousse directement via SMB sans PC | [Voir →](https://www.amazon.fr/ScanSnap-iX1300-Document-Automatique-Standards/dp/B09HS7WRNX) |
| 📄 **Scanner (option USB + Pi 5)** | Brother ADS-1200 — USB, ultra-compact, avaleur, compatible Linux/SANE | [Voir →](https://www.amazon.fr/Brother-ADS-1200-Documents-Portable-Plastifi%C3%A9es/dp/B07H3CTHF3) |

> **💡 Conseil serveur :** Chercher un Mini PC avec le SSD **déjà en 1 To** — c'est souvent plus économique qu'acheter serveur + SSD séparément. Mots-clés : `mini pc ryzen 7430U 1to 16go`.

> **💡 Raspberry Pi 5 (mode Split) :** Prendre le modèle **8 Go RAM** — le 4 Go peut être juste avec plusieurs conteneurs Docker actifs (pi-samba + pi-pusher + nut-upsd). L'alimentation officielle **27 W USB-C** est obligatoire : les alimentations génériques ne fournissent pas assez de courant et causent des instabilités. Ne pas oublier la microSD (32 Go min, classe A2).

> **💡 Scanner :**
> - **ScanSnap iX1300** : scanner WiFi/USB compact (format U-turn). Se connecte en SMB directement à la VM — aucun PC intermédiaire. Idéal si tu n'as pas de Pi 5.
> - **Brother ADS-1200** : USB uniquement, ultra-compact, duplex 25 ppm, ADF 20 feuilles. Branché au **Raspberry Pi 5** → numérisation automatique dès qu'un document est inséré (service SANE + scanbd inclus dans `docker-compose.pi.yml`). Compatible Linux nativement (driver `brscan5`).

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
7. ✅ Configure les mises à jour automatiques (OS + projet)
8. ✅ Affiche les URLs d'accès HTTP et HTTPS

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

### Scanner USB — Raspberry Pi 5 (Brother ADS-1200 ou DS-640)

Le service `ged-autoscan` gère deux types de scanners USB, chacun avec son mode de déclenchement.

| Scanner | Mode | Déclenchement |
|---|---|---|
| **ADS-1200** (~270€) | `SCAN_TRIGGER=adf` | Insertion d'un doc dans l'ADF → scan immédiat |
| **DS-640** (~70€) | `SCAN_TRIGGER=button` | Appui sur le bouton physique → scan de la feuille |

#### Étape 1 — Installer le driver et le service

```bash
cd /opt/easy-ged-pi

# Installe brscan5 + (optionnel) scanbd pour mode bouton
sudo ./scanner/install-brscan5.sh

# Copier le service systemd
sudo cp scanner/autoscan.service /etc/systemd/system/ged-autoscan.service
```

> **💡 Si tu as utilisé `install-pi.sh`** : le script te propose déjà ces étapes.

#### Étape 2 — Choisir le mode (ADS-1200 ou DS-640)

Éditer `/etc/systemd/system/ged-autoscan.service` :

```ini
# Pour le Brother ADS-1200 (ADF multi-pages) :
Environment=SCAN_TRIGGER=adf

# Pour le Brother DS-640 (feuille à feuille, bouton) :
Environment=SCAN_TRIGGER=button
```

#### Étape 3 — Activer et démarrer

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now ged-autoscan

# Vérifier
systemctl status ged-autoscan
journalctl -u ged-autoscan -f
```

#### Étape 4 — Vérifier que le scanner est détecté

```bash
scanimage -L
# → doit afficher :
# device 'brother5:bus6;dev1' is a Brother ADS-1200 ...
# ou
# device 'brother5:bus6;dev2' is a Brother DS-640 ...
```

#### Étape 5 — Tester

**Mode ADF (ADS-1200) :** insérer un document dans l'ADF → scan automatique en ~3s

**Mode bouton (DS-640) :**
1. Insérer la feuille dans le slot
2. Appuyer sur le bouton "Scan" du scanner
3. Le scan se lance automatiquement

Dans les deux cas : le PDF apparaît dans `/opt/easy-ged-pi/consume/scan_YYYYMMDD_HHMMSS.pdf`, puis `pi-pusher` l'envoie à Paperless.

#### Paramétrage avancé (optionnel)

```ini
# Dans /etc/systemd/system/ged-autoscan.service :
Environment=SCAN_RESOLUTION=300    # DPI : 150, 300, 600
Environment=SCAN_MODE=Color        # Color, Gray, Black & White
Environment=SCAN_SOURCE=ADF        # ADF, ADF Duplex (mode adf uniquement)
Environment=POLL_INTERVAL=3        # Intervalle scrutation en secondes (mode adf)
```

```bash
sudo systemctl daemon-reload && sudo systemctl restart ged-autoscan
```

#### Troubleshooting scanner

```bash
# Scanner non détecté
lsusb | grep -i brother        # Doit afficher le scanner
scanimage -L                   # Doit lister le scanner SANE
sudo udevadm control --reload-rules && sudo udevadm trigger

# Logs en temps réel
journalctl -u ged-autoscan -f

# Tester un scan manuel (DS-640)
scanimage --device-name="$(scanimage -L | grep -oP "(?<=')[^']+")" \
  --mode=Color --resolution=300 --format=pdf -o /tmp/test.pdf \
  && echo "✓ Scan OK" || echo "✗ Échec"
```

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

### Mises à jour automatiques

Le système se met à jour à trois niveaux :

| Niveau | Mécanisme | Fréquence |
|---|---|---|
| 🐳 Images Docker | Watchtower (inclus dans stack) | Toutes les nuits 3h00 |
| 📦 Projet (git) | Cron → `scripts/update.sh` | Dimanche 3h00 |
| 🔒 OS sécurité | `unattended-upgrades` | Quotidien |

Mise à jour manuelle :
```bash
# Tout mettre à jour maintenant
sudo /opt/easy-ged/scripts/update.sh

# Projet uniquement
sudo /opt/easy-ged/scripts/update.sh --project-only

# OS uniquement
sudo /opt/easy-ged/scripts/update.sh --os-only
```

---

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
- Accès externe via Cloudflare Tunnel (profil Docker optionnel)
- Bilan mensuel automatique (cron n8n, 1er du mois à 8h)
- Mode split Pi 5 + VM (architecture modulaire)
- Mises à jour automatiques (OS + projet + Docker via Watchtower)

### v2 (prévue)
- [ ] QR Code EPC généré localement (sans appel externe)
- [ ] Amélioration OCR avec Surya/Docling (meilleure précision documents complexes)
- [ ] Dashboard budget Grafana (visualisation des dépenses)
- [ ] Notification push mobile (Gotify ou Ntfy auto-hébergé)
- [ ] Multi-utilisateurs Paperless (famille / PME)

---

## ☁️ Accès Externe via Cloudflare Tunnel (optionnel)

> Accès HTTPS sécurisé depuis l'extérieur, sans ouvrir de ports sur votre box.

**Prérequis :** Compte Cloudflare gratuit + un domaine géré par Cloudflare.

### Configurer le tunnel

1. Se connecter sur [one.dash.cloudflare.com](https://one.dash.cloudflare.com/)
2. Aller dans **Networks → Tunnels → Create a tunnel**
3. Choisir **Cloudflared** → Donner un nom (ex: `easy-ged-home`)
4. Copier le **token** affiché
5. Dans le fichier `.env`, décommenter et renseigner :
   ```
   CLOUDFLARE_TUNNEL_TOKEN=eyJhIjoiXXXX...
   ```
6. Dans le tunnel, configurer les **Public Hostnames** :
   - `paperless.ton-domaine.com` → Service: `http://paperless-ngx:8000`
   - `n8n.ton-domaine.com` → Service: `http://n8n:5678`
   - `portainer.ton-domaine.com` → Service: `http://portainer:9000`
   - ⚠️ **Ne pas exposer Ollama** (11434) — usage interne uniquement

### Démarrer avec Cloudflare

```bash
# Démarrer la stack avec le tunnel Cloudflare
docker compose --profile cloudflare up -d

# Vérifier que cloudflared est connecté
docker compose logs ged-cloudflared
```

---

## 🍓 Raspberry Pi 5 — Mode Split (optionnel)

> Le Pi 5 gère la réception des scans, la VM Proxmox gère l'analyse IA et le stockage.

### Pourquoi le mode split ?

| Avantage | Détail |
|---|---|
| Scanner dédié | Le Pi est toujours allumé pour recevoir les scans |
| UPS possible | Le Pi peut monitorer l'UPS APC en USB |
| VM moins sollicitée | La VM ne gère que l'IA et la GED |

### Activer le mode split

Dans `.env` :
```bash
DEPLOY_MODE=split
PI5_HOST=192.168.1.XX
```

### Installer la stack Pi

```bash
# Sur le Raspberry Pi 5 (Raspberry Pi OS Lite 64-bit)
curl -sSL https://raw.githubusercontent.com/tunisiano187/easy-GED/main/scripts/install-pi.sh | sudo bash
```

Le script installe sur le Pi :
- **Samba** — réception fichiers scanner (`\\IP_PI\consume`)
- **Pi Pusher** — transfert automatique vers Paperless via API REST
- **Watchtower Pi** — mises à jour Docker du Pi
- **Mises à jour automatiques** — cron hebdomadaire (dimanche 3h30)

### Créer le token API Paperless

Pour que le Pi envoie les fichiers à Paperless :
1. Dans Paperless : **Paramètres → Tokens API → Ajouter**
2. Donner un nom (ex: `pi5-pusher`)
3. Copier le token dans `.env` du Pi : `PAPERLESS_API_TOKEN=xxx`

---

## 🔌 Monitoring UPS APC (NUT)

> **Optionnel** — Requis uniquement si tu as un onduleur APC branché physiquement sur le Pi 5.

Le Pi 5 est le **serveur NUT** : l'UPS y est branché en USB, et il expose le monitoring sur le réseau (port 3493). Les autres machines (VM Proxmox, NAS Synology) se connectent en tant que **clients NUT**.

> ⚠️ NUT ne peut **pas** tourner dans la VM Proxmox sans USB passthrough — c'est pour ça qu'il tourne sur le Pi.

### Démarrer le serveur NUT sur le Pi

```bash
cd /opt/easy-ged-pi

# 1. Renseigner les variables NUT dans .env
nano .env
# Ajouter :
#   NUT_UPSD_USER=upsmon
#   NUT_UPSD_PASSWORD=<MOT_DE_PASSE>   ← définir ici
#   NUT_UPS_NAME=apc
#   NUT_UPS_DRIVER=usbhid-ups   # pour la plupart des APC USB

# 2. Vérifier que l'UPS est détecté
lsusb | grep -i apc

# 3. Lancer la stack Pi avec le profil NUT
docker compose -f docker-compose.pi.yml --profile nut up -d

# 4. Vérifier l'état de l'UPS
docker exec pi-nut-upsd upsc apc@localhost
```

**Accès :**
- Interface web NUT : `http://IP_PI:6543`
- Serveur NUT (pour les clients) : `IP_PI:3493`

### Configurer les clients NUT

**Sur chaque nœud Proxmox :**
```bash
apt install -y nut-client

# /etc/nut/upsmon.conf
MONITOR apc@IP_PI 1 upsmon MOT_DE_PASSE slave

# /etc/nut/nut.conf
MODE=netclient

systemctl restart nut-client
```

**Sur le NAS Synology :**
Panneau de configuration → Matériel et alimentation → UPS → UPS réseau → Adresse : `IP_PI`

---

## 📜 Licence

Ce projet est open-source, usage personnel. Voir [LICENSE](LICENSE).
