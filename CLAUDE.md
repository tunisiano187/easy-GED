# easy-GED — Contexte Projet pour Agent IA

## Vue d'ensemble

**easy-GED** est une Gestion Électronique de Documents (GED) privée, auto-hébergée, 100% locale.
Elle automatise la numérisation, l'analyse IA et le classement des courriers et factures.

- **Dépôt** : https://github.com/tunisiano187/easy-GED
- **Branche de travail** : main (les features partent sur `feat/<sujet>` et reviennent sur main via PR)
- **Langue principale** : Français (documents, UI, prompts IA)
- **Statut** : En cours de mise en place

## Matériel Cible

| Composant | Détail |
|---|---|
| Serveur | Mini PC AMD Ryzen 7330U, 16 Go RAM, 1 To NVMe (à acheter) |
| Virtualisation | Proxmox VE — VM Debian/Ubuntu AMD64 dédiée GED (8 vCPUs, 12 Go RAM) |
| Raspberry Pi 5 | 8 Go RAM — réception scanner + monitoring UPS (mode split optionnel) |
| NAS | Synology basique (DS220j/DS223) — stockage réseau si besoin |
| Scanner | ScanSnap iX1300 ou Brother ADS-1800W (à acheter) |
| Sauvegardes | Proxmox Backup Server (PBS) — snapshots VM quotidiens |
| UPS | APC (optionnel) — monitoring via NUT (Pi 5 ou Proxmox host) |

## Modes de Déploiement

### Mode `all-in-one` (défaut)
Tout tourne sur la VM Proxmox — plus simple, recommandé pour débuter.

### Mode `split`
- **Raspberry Pi 5** : Samba (réception scanner) + Pi Pusher (envoi API Paperless) + NUT (optionnel)
- **VM Proxmox** : Paperless-ngx + n8n + Ollama + PostgreSQL + Redis + Caddy

Le choix se fait via `DEPLOY_MODE` dans `.env`.

## Architecture

```
[Mode all-in-one]
Scanner ──SMB──► Samba ──► /consume ──► Paperless-ngx (OCR Tesseract FR)

[Mode split]
Scanner ──SMB──► Pi 5 Samba ──► pi-pusher ──► Paperless API POST

Email IMAP (opt) ─────────────────────────────────────►│
                                                        │ webhook POST
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

Caddy ──HTTPS local──► *.home.local (auto-signed certs)
Cloudflare Tunnel (opt) ──HTTPS externe──► paperless|n8n|portainer.domaine.com
Proxmox PBS ◄── Snapshots VM quotidiens
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
| `ged-samba` | dperson/samba:latest | 445 | Réception scanner (mode all-in-one) |
| `ged-caddy` | caddy:2-alpine | 80/443 | Reverse proxy HTTPS local |
| `ged-cloudflared` | cloudflare/cloudflared | — | Tunnel externe (profil cloudflare) |
| `ged-portainer` | portainer/portainer-ce | 9000 | Gestion Docker (UI) |
| `ged-watchtower` | containrrr/watchtower | — | MàJ auto images Docker (3h00) |

### docker-compose.pi.yml (Raspberry Pi 5 — mode split)

| Conteneur | Image | Port | Rôle |
|---|---|---|---|
| `pi-samba` | dperson/samba | 445 | Réception scanner SMB |
| `pi-pusher` | alpine:3.19 | — | inotify → POST Paperless API |
| `pi-watchtower` | containrrr/watchtower | — | MàJ auto images Docker Pi |
| `nut-upsd` (opt) | instantlinux/nut-upsd | 3493 | Serveur NUT (USB APC) |
| `nut-monitor` (opt) | teknologist/webnut | 6543 | Interface web NUT |

### docker-compose.nut.yml (device avec USB physique — séparé)
Identique à la partie NUT du docker-compose.pi.yml, pour un usage sur Proxmox host ou autre device.

## Structure des Fichiers

```
easy-GED/
├── CLAUDE.md                          ← Ce fichier (contexte agent IA)
├── AGENT-DEPLOY.md                    ← Prompt de déploiement pour agent IA
├── docker-compose.yml                 ← Stack principale (VM GED)
├── docker-compose.pi.yml              ← Stack Pi 5 (mode split)
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
│   │   ├── notify-n8n.sh             ← Script post-consume → webhook n8n
│   │   └── push-to-paperless.sh      ← Pi → Paperless API (mode split)
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
    ├── install.sh                    ← Installation VM one-shot
    ├── install-pi.sh                 ← Installation Pi 5 one-shot
    ├── pull-model.sh                 ← Télécharge Mistral 7B
    └── update.sh                     ← Mise à jour projet + OS + Docker
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
- `DEPLOY_MODE` : `all-in-one` (défaut) ou `split`

Variables optionnelles :
- `PAPERLESS_API_TOKEN` : pour le Pi Pusher (mode split)
- `CLOUDFLARE_TUNNEL_TOKEN` : accès externe HTTPS
- Section `[NUT]` : `NUT_UPSD_PASSWORD`, `NUT_UPS_NAME`, `NUT_SERVER_HOST`

## Commandes Utiles

```bash
# Démarrer la stack principale
docker compose up -d

# Démarrer avec Cloudflare Tunnel
docker compose --profile cloudflare up -d

# Démarrer la stack Pi 5 (sur le Pi)
docker compose -f docker-compose.pi.yml up -d

# Voir les logs
docker compose logs -f

# Statut des conteneurs
docker compose ps

# Télécharger le modèle IA
./scripts/pull-model.sh

# Créer les champs Paperless
./paperless/init/create-custom-fields.sh

# Mise à jour complète
sudo ./scripts/update.sh

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
8. (Mode split) Déposer un fichier dans `\\IP_PI\consume` → vérifier dans Paperless

## Mises à jour automatiques

| Niveau | Mécanisme | Fréquence |
|---|---|---|
| Images Docker (VM) | Watchtower | Nuit à 3h00 |
| Images Docker (Pi) | pi-watchtower | Nuit à 3h30 |
| Projet Git | Cron → `scripts/update.sh` | Dimanche 3h00 |
| OS sécurité | `unattended-upgrades` | Quotidien |

## Sauvegardes

Les sauvegardes sont assurées par **Proxmox Backup Server (PBS)** au niveau VM.
Aucun script de sauvegarde local dans le projet.

Configuration PBS recommandée :
- Schedule : `daily` à 04:00
- Rétention : `keep-daily=7, keep-weekly=4, keep-monthly=3`

## Règles Git & PRs — OBLIGATOIRES

> Ces règles s'appliquent à tous les agents IA travaillant sur ce projet.
> Les violer est une erreur — corriger avant de continuer.

- **1 PR = 1 raison unique** : ne jamais mélanger des sujets différents dans une même PR.
  Exemples de raisons distinctes : une feature, un bugfix, une mise à jour de doc,
  un nouveau fichier de config, une mise à jour de dépendance.
- **Doc et BACKLOG inclus dans la PR de la feature** : toute mise à jour de `BACKLOG.md`,
  `README.md` ou autre doc directement liée à une feature fait partie du même commit/PR.
  Ne jamais ouvrir une PR séparée juste pour cocher une case dans BACKLOG.md.
- **Maximum 2 PRs ouvertes simultanément** : attendre qu'une PR soit mergée ou fermée
  avant d'en ouvrir une troisième.
- **Jamais de push direct sur `main`** : toujours passer par une branche + PR.
- **Branche nommée selon le sujet** : `feat/<sujet>`, `fix/<sujet>`, `docs/<sujet>`.
- **Ne pas réutiliser une PR mergée** : créer une nouvelle PR pour chaque nouveau sujet.

## Contraintes & Scope

- HTTPS local via Caddy (`local_certs`, domaines `.home.local`)
- Accès externe : **Cloudflare Tunnel** (profil Docker `cloudflare`) ou Tailscale
- NUT doit tourner sur un device avec **USB physique** vers l'UPS
- Configuration scanner : manuelle sur l'interface web du scanner (SMB → IP_VM ou IP_PI port 445)
- Modèle Ollama : téléchargement initial ~4.1 Go requis
- Ne jamais exposer Ollama (11434) via Cloudflare Tunnel
