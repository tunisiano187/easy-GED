# easy-GED — Contexte Projet pour Agent IA

## Vue d'ensemble

**easy-GED** est une Gestion Électronique de Documents (GED) privée, auto-hébergée, 100% locale.
Elle automatise la numérisation, l'analyse IA et le classement des courriers et factures.

- **Dépôt** : https://github.com/tunisiano187/easy-GED
- **Branche de travail** : claude/plan-mise-en-place-cywqty
- **Langue principale** : Français (documents, UI, prompts IA)
- **Statut** : En cours de mise en place

## Matériel Cible

| Composant | Détail |
|---|---|
| Serveur | Mini PC AMD Ryzen 7330U, 16 Go RAM, 1 To NVMe (à acheter) |
| Virtualisation | Proxmox VE — VM Debian/Ubuntu AMD64 dédiée GED (8 vCPUs, 12 Go RAM) |
| NAS | Synology basique (DS220j/DS223) — stockage réseau si besoin |
| Scanner | ScanSnap iX1300 ou Brother ADS-1800W (à acheter) |
| Sauvegardes | Proxmox Backup Server (PBS) — snapshots VM quotidiens |
| UPS | APC (optionnel) — monitoring via NUT sur device avec USB physique |

## Architecture

```
Scanner ──SMB──► Samba ──► /consume ──► Paperless-ngx (OCR Tesseract FR)
Email IMAP (opt) ───────────────────────►         │
                                                   │ webhook POST
                                                   ▼
                                             n8n Workflow
                                         ┌────────┼────────┐
                                         ▼        ▼        ▼
                                      Ollama  Paperless PostgreSQL
                                    Mistral 7B  API       historique
                                         │
                             ┌───────────┴───────────┐
                             ▼                       ▼
                         facture               rappel reçu
                      Tag "À Payer"        vérifie si payée
                      alerte échéance     → alerte litige si oui
                             │
                    Email + Telegram + QR Code EPC

Caddy ──HTTPS──► paperless.home.local / n8n.home.local / portainer.home.local
Proxmox PBS ◄── Snapshots VM quotidiens (sauvegardes niveau VM)
```

## Stack Docker Compose

### docker-compose.yml (VM GED principale)

| Conteneur | Image | Port | Rôle |
|---|---|---|---|
| `ged-postgres` | postgres:15-alpine | — | Base données (Paperless + n8n) |
| `ged-redis` | redis:7-alpine | — | Cache Paperless |
| `ged-paperless` | paperless-ngx:latest | 8000 | GED + OCR |
| `ged-n8n` | n8nio/n8n:latest | 5678 | Orchestration workflows |
| `ged-ollama` | ollama/ollama:latest | 11434 | IA locale Mistral 7B |
| `ged-samba` | dperson/samba:latest | 445 | Réception fichiers scanner |
| `ged-caddy` | caddy:2-alpine | 80/443 | Reverse proxy HTTPS local |
| `ged-portainer` | portainer/portainer-ce | 9000 | Gestion Docker (UI) |
| `ged-watchtower` | containrrr/watchtower | — | MàJ auto images Docker |

### docker-compose.nut.yml (device avec USB physique — séparé)

| Conteneur | Image | Port | Rôle |
|---|---|---|---|
| `nut-upsd` | instantlinux/nut-upsd | 3493 | Serveur NUT (USB APC) |
| `nut-monitor` | teknologist/webnut | 6543 | Interface web monitoring |

> ⚠️ NUT doit tourner sur un device avec accès USB physique à l'UPS (pas dans la VM GED).

## Structure des Fichiers

```
easy-GED/
├── CLAUDE.md                          ← Ce fichier (contexte agent IA)
├── AGENT-DEPLOY.md                    ← Prompt de déploiement pour agent IA
├── docker-compose.yml                 ← Stack principale (VM GED)
├── docker-compose.nut.yml             ← Stack NUT/UPS (device séparé)
├── .env.example                       ← Template de configuration
├── .env                               ← (gitignore) Configuration réelle
├── .gitignore
├── README.md                          ← Guide humain + liste de courses
├── caddy/
│   └── Caddyfile                      ← Config reverse proxy HTTPS local
├── nut/
│   ├── ups.conf.example               ← Config UPS APC (template)
│   └── upsd.users.example             ← Utilisateurs NUT (template)
├── paperless/
│   ├── scripts/
│   │   └── notify-n8n.sh             ← Script post-consume → webhook n8n
│   └── init/
│       └── create-custom-fields.sh   ← Crée les 7 champs personnalisés
├── n8n/
│   └── workflows/
│       ├── ged-main-workflow.json    ← Workflow principal importable
│       └── ged-budget-mensuel.json   ← Bilan mensuel (cron 1er du mois)
├── ollama/
│   └── prompts/
│       └── invoice-extraction.txt   ← Prompt Mistral (extraction JSON FR)
├── postgres/
│   └── init-n8n-db.sql              ← Création base n8n au démarrage
└── scripts/
    ├── install.sh                    ← Installation complète one-shot
    └── pull-model.sh                 ← Télécharge Mistral 7B
```

## Champs Personnalisés Paperless

| Champ | Type | Valeurs possibles |
|---|---|---|
| `emetteur` | String | Nom de l'entreprise (EDF, Orange…) |
| `numero_facture` | String | Référence document |
| `montant_total` | Monetary | Montant en EUR |
| `date_echeance` | Date | YYYY-MM-DD |
| `iban` | String | FR76 3000… |
| `communication` | String | Référence paiement |
| `statut_paiement` | Select | Non Payé / Payé / En Litige / Rappel Reçu |

## Logique Métier n8n

### Cas `facture`
1. Set champs personnalisés (montant, échéance, IBAN, émetteur)
2. Tag "À Payer" dans Paperless
3. Si `date_echeance` dans ≤7 jours → notification urgente
4. Si IBAN présent → générer données QR Code EPC pour paiement mobile

### Cas `rappel`
1. Recherche Paperless : même émetteur + montant ±5%
2. Si trouvé ET `statut_paiement = Payé` → alerte litige (email + Telegram)
3. Sinon → tag "Rappel Urgent" + notification standard

### Cas `courrier_administratif` / `attestation`
1. Classement automatique par correspondant
2. Tag selon type, pas de notification

### Bilan mensuel (workflow ged-budget-mensuel.json)
- Cron : 1er du mois à 8h00
- Récupère toutes les factures du mois précédent via l'API Paperless
- Agrège par émetteur : total, payées, non payées
- Envoie rapport texte par Telegram + Email

## Variables d'Environnement Clés

Voir `.env.example` pour toutes les variables. Les indispensables :
- `PAPERLESS_SECRET_KEY`, `PAPERLESS_ADMIN_PASSWORD`
- `POSTGRES_PASSWORD`, `N8N_ENCRYPTION_KEY`
- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`
- `SMTP_HOST`, `SMTP_USER`, `SMTP_PASSWORD`
- `SCANNER_SMB_USER`, `SCANNER_SMB_PASSWORD`

Variables optionnelles :
- Section `[CADDY]` : domaines `.home.local` (si override nécessaire)
- Section `[NUT]` : `NUT_UPSD_PASSWORD`, `NUT_UPS_NAME`, `NUT_SERVER_HOST`

## Commandes Utiles

```bash
# Démarrer la stack principale
docker compose up -d

# Voir les logs
docker compose logs -f

# Statut des conteneurs
docker compose ps

# Télécharger le modèle IA
./scripts/pull-model.sh

# Créer les champs Paperless
./paperless/init/create-custom-fields.sh

# Stack NUT (sur le device avec UPS)
docker compose -f docker-compose.nut.yml up -d

# Accès aux interfaces (HTTP direct)
# Paperless  : http://IP_VM:8000
# n8n        : http://IP_VM:5678
# Portainer  : http://IP_VM:9000
# Ollama API : http://IP_VM:11434

# Accès HTTPS local (après ajout dans /etc/hosts)
# Paperless  : https://paperless.home.local
# n8n        : https://n8n.home.local
# Portainer  : https://portainer.home.local
```

## Tests de Validation

1. `docker compose ps` → tous les services `healthy`
2. Ouvrir Paperless sur `:8000` → se connecter avec le compte admin
3. Vérifier les 7 champs personnalisés dans Paramètres → Champs personnalisés
4. `curl http://IP_VM:11434/api/tags` → doit lister `mistral:7b-instruct`
5. Copier un PDF dans le dossier consume → il doit apparaître dans Paperless avec les champs remplis
6. Vérifier notification Telegram reçue
7. Test litige : scanner un rappel pour une facture déjà marquée "Payée"

## Sauvegardes

Les sauvegardes sont assurées par **Proxmox Backup Server (PBS)** au niveau VM.
Aucun script de sauvegarde local dans le projet.

Configuration PBS recommandée :
- Schedule : `daily` à 04:00
- Rétention : `keep-daily=7, keep-weekly=4, keep-monthly=3`

## Contraintes & Scope

- HTTPS local via Caddy (`local_certs`, domaines `.home.local`)
- Accès distant : utiliser **Tailscale** (VPN mesh gratuit)
- NUT doit tourner sur un device avec **USB physique** vers l'UPS
- Configuration scanner : manuelle sur l'interface web du scanner (SMB → IP_VM port 445)
- Modèle Ollama : téléchargement initial ~4.1 Go requis
