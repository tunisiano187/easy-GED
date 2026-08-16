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
| Virtualisation | Proxmox VE — VM Debian/Ubuntu AMD64 dédiée GED |
| NAS | Synology basique (DS220j/DS223) — stockage + sauvegardes |
| Scanner | ScanSnap iX1300 ou Brother ADS-1800W (à acheter) |

## Architecture

```
Scanner ──SMB──► Samba ──► /consume ──► Paperless-ngx (OCR Tesseract FR)
Email IMAP ────────────────────────────►          │
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
                      alerte échéance    → alerte litige si oui
                             │
                    Email + Telegram + QR Code EPC

NAS Synology ◄── Restic (backups chiffrés quotidiens)
```

## Stack Docker Compose

| Conteneur | Image | Port | Rôle |
|---|---|---|---|
| `ged-postgres` | postgres:15-alpine | — | Base données (Paperless + n8n) |
| `ged-redis` | redis:7-alpine | — | Cache Paperless |
| `ged-paperless` | paperless-ngx:latest | 8000 | GED + OCR |
| `ged-n8n` | n8nio/n8n:latest | 5678 | Orchestration workflows |
| `ged-ollama` | ollama/ollama:latest | 11434 | IA locale Mistral 7B |
| `ged-samba` | dperson/samba:latest | 445 | Réception fichiers scanner |
| `ged-portainer` | portainer/portainer-ce | 9000 | Gestion Docker (UI) |
| `ged-watchtower` | containrrr/watchtower | — | MàJ auto images Docker |

## Structure des Fichiers

```
easy-GED/
├── CLAUDE.md                          ← Ce fichier (contexte agent IA)
├── AGENT-DEPLOY.md                    ← Prompt de déploiement pour agent IA
├── docker-compose.yml                 ← Stack complète
├── .env.example                       ← Template de configuration
├── .env                               ← (gitignore) Configuration réelle
├── .gitignore
├── README.md                          ← Guide humain + liste de courses
├── paperless/
│   ├── scripts/
│   │   └── notify-n8n.sh             ← Script post-consume → webhook n8n
│   └── init/
│       └── create-custom-fields.sh   ← Crée les 7 champs personnalisés
├── n8n/
│   └── workflows/
│       └── ged-main-workflow.json    ← Workflow complet importable
├── ollama/
│   └── prompts/
│       └── invoice-extraction.txt   ← Prompt Mistral (extraction JSON FR)
├── postgres/
│   └── init-n8n-db.sql              ← Création base n8n au démarrage
└── scripts/
    ├── install.sh                    ← Installation complète one-shot
    ├── pull-model.sh                 ← Télécharge Mistral 7B
    └── backup.sh                    ← Sauvegarde Restic vers NAS
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
4. Si IBAN présent → générer QR Code EPC pour paiement mobile

### Cas `rappel`
1. Recherche Paperless : même émetteur + montant ±5%
2. Si trouvé ET `statut_paiement = Payé` → alerte litige (email + Telegram + PDF joint)
3. Sinon → tag "Rappel Urgent" + notification standard

### Cas `courrier_administratif` / `attestation`
1. Classement automatique par correspondant
2. Tag selon type, pas de notification

## Variables d'Environnement Clés

Voir `.env.example` pour toutes les variables. Les indispensables :
- `PAPERLESS_SECRET_KEY`, `PAPERLESS_ADMIN_PASSWORD`
- `POSTGRES_PASSWORD`, `N8N_ENCRYPTION_KEY`
- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`
- `SMTP_HOST`, `SMTP_USER`, `SMTP_PASSWORD`
- `NAS_SMB_HOST`, `NAS_SMB_SHARE`, `NAS_SMB_USER`, `NAS_SMB_PASSWORD`
- `RESTIC_PASSWORD`
- `SCANNER_SMB_USER`, `SCANNER_SMB_PASSWORD`

## Commandes Utiles

```bash
# Démarrer la stack
docker compose up -d

# Voir les logs
docker compose logs -f

# Statut des conteneurs
docker compose ps

# Télécharger le modèle IA
./scripts/pull-model.sh

# Créer les champs Paperless
./paperless/init/create-custom-fields.sh

# Sauvegarde manuelle
sudo ./scripts/backup.sh

# Accès aux interfaces
# Paperless  : http://IP_VM:8000
# n8n        : http://IP_VM:5678
# Portainer  : http://IP_VM:9000
# Ollama API : http://IP_VM:11434
```

## Tests de Validation

1. `docker compose ps` → tous les services `healthy`
2. Ouvrir Paperless sur `:8000` → se connecter avec le compte admin
3. Vérifier les 7 champs personnalisés dans Paramètres → Champs personnalisés
4. `curl http://IP_VM:11434/api/tags` → doit lister `mistral:7b-instruct`
5. Copier un PDF dans le dossier consume → il doit apparaître dans Paperless avec les champs remplis
6. Vérifier notification Telegram reçue
7. Test litige : scanner un rappel pour une facture déjà marquée "Payée"

## Contraintes & Scope v1

- Accès **local uniquement** (pas de HTTPS/reverse proxy — ajouter Caddy en v2)
- Accès distant : utiliser **Tailscale** (VPN mesh gratuit)
- Configuration scanner : manuelle sur l'interface web du scanner (SMB destination → IP_VM port 445)
- Modèle Ollama : téléchargement initial ~4.1 Go requis
