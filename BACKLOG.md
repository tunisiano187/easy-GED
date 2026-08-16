# easy-GED — Backlog & Roadmap

> Ce fichier est lu par l'agent IA lors de son scan hebdomadaire pour déterminer
> quoi implémenter ensuite. Mettre à jour au fil de l'avancement.

---

## ✅ V1 — Implémentée

| Fonctionnalité | Fichier(s) |
|---|---|
| Stack Docker complète (Paperless, n8n, Ollama, PostgreSQL, Redis, Caddy, Portainer) | `docker-compose.yml` |
| Option n8n externe (`N8N_EXTERNAL_URL`) — utiliser un n8n existant | `docker-compose.yml`, `.env.example`, `scripts/install.sh`, `notify-n8n.sh` |
| Configuration `.env.example` | `.env.example` |
| Stack Raspberry Pi 5 (mode split) | `docker-compose.pi.yml` |
| Stack NUT/UPS indépendante | `docker-compose.nut.yml` |
| Reverse proxy HTTPS local (Caddy, `*.home.local`) | `caddy/Caddyfile` |
| Workflow n8n principal (webhook → Mistral → Paperless → alertes) | `n8n/workflows/ged-main-workflow.json` |
| Workflow bilan mensuel (cron n8n, 1er du mois) | `n8n/workflows/ged-budget-mensuel.json` |
| Prompt Mistral extraction JSON (français) | `ollama/prompts/invoice-extraction.txt` |
| Champs personnalisés Paperless (7 champs) | `paperless/init/create-custom-fields.sh` |
| Script notify-n8n.sh (post-consume → webhook) | `paperless/scripts/notify-n8n.sh` |
| Script push-to-paperless.sh (Pi → API Paperless) | `paperless/scripts/push-to-paperless.sh` |
| DB init PostgreSQL (base n8n) | `postgres/init-n8n-db.sql` |
| Script install VM one-shot | `scripts/install.sh` |
| Script install Pi 5 one-shot | `scripts/install-pi.sh` |
| Script pull Mistral 7B | `scripts/pull-model.sh` |
| Script mise à jour | `scripts/update.sh` |
| Scanner USB Brother ADS-1200 (mode ADF, service systemd) | `scanner/autoscan.sh`, `scanner/autoscan.service` |
| Scanner USB Brother DS-640 (mode bouton, scanbd) | `scanner/scan-button.sh`, `scanner/scanbd.conf` |
| Driver brscan5 (ARM64/AMD64) | `scanner/install-brscan5.sh` |
| Config NUT templates | `nut/ups.conf.example`, `nut/upsd.users.example` |
| Prompt déploiement agent IA | `AGENT-DEPLOY.md` |
| README complet (liste de courses, guide pas-à-pas, troubleshooting) | `README.md` |

---

## 🚧 V2 — À implémenter

Priorité décroissante. L'agent traite ces items dans l'ordre lors de ses scans hebdomadaires,
**si aucune PR ouverte ni issue bloquante n'attend son attention**.

### P1 — Haute priorité

- [x] **QR Code EPC local** — Générer le QR Code de paiement (format EPC/SEPA) sans appel
      externe, directement dans le workflow n8n via un nœud Code (bibliothèque `qrcode` npm).
      Le QR est inséré en base64 dans l'email de notification.
      → PR #5 mergée — `n8n/Dockerfile`, `docker-compose.yml`, `n8n/workflows/ged-main-workflow.json`

- [ ] **Gotify / Ntfy — Notifications push mobiles** — Alternative auto-hébergée aux
      notifications Telegram pour les alertes (coupure UPS, document urgent, rappel).
      Ajouter le service Docker + configurer dans n8n + documenter dans README.
      Choisir Ntfy (plus simple, client web + mobile).
      → Fichiers : `docker-compose.yml` (nouveau service `ged-ntfy`), `.env.example`,
        `n8n/workflows/ged-main-workflow.json` (nœud Ntfy)

### P2 — Priorité moyenne

- [ ] **Dashboard budget Grafana** — Visualisation mensuelle des dépenses par catégorie
      depuis les données Paperless. Ajouter Grafana + datasource PostgreSQL + dashboard
      prêt à l'emploi (JSON importable).
      → Fichiers : `docker-compose.yml` (services `ged-grafana`, `ged-prometheus`),
        `grafana/dashboards/budget.json`

- [ ] **Amélioration OCR Surya/Docling** — Remplacer ou compléter Tesseract par Surya
      (meilleure précision sur documents manuscrits et tableaux). Ajouter comme service
      Docker optionnel (profil `ocr-enhanced`), scripter la post-processing.
      → Fichiers : `docker-compose.yml` (profil `ocr-enhanced`),
        `paperless/scripts/enhanced-ocr.sh`

- [ ] **Script de diagnostic** — `scripts/check.sh` qui vérifie l'état de la stack en
      30 secondes : services healthy, espace disque, IA accessible, dernière sauvegarde PBS.
      Affiche un résumé coloré avec ✓/✗.

### P3 — Basse priorité

- [ ] **Multi-utilisateurs Paperless** — Guide de configuration pour plusieurs comptes
      (famille ou PME) : groupes Paperless, permissions par correspondant, n8n adapté.
      → Fichier : `docs/multi-users.md`

- [ ] **Intégration email IMAP** — Ingestion automatique des emails (factures PDF en PJ,
      confirmations de paiement). Documenter la configuration Paperless IMAP + workflow n8n.
      → Fichier : `docs/imap-setup.md`, mise à jour `.env.example`

- [ ] **Tailscale** — Guide accès distant sécurisé via Tailscale (alternative Cloudflare
      Tunnel pour ceux sans domaine). Script d'installation + documentation.
      → Fichier : `docs/tailscale.md`

---

## 🐛 Issues Connues

> Mis à jour automatiquement par le scan hebdomadaire de l'agent.
> Les issues actives ont un lien GitHub correspondant.

| # | Description | Gravité | GitHub Issue | Statut |
|---|---|---|---|---|
| — | Aucune issue connue | — | — | — |

---

## 📋 Règles pour l'Agent Hebdomadaire

1. **Vérifier d'abord** : lire les issues GitHub ouvertes + statut CI des PRs ouvertes
2. **Créer une issue** pour tout problème détecté qui ne peut pas être résolu immédiatement
3. **Priorité** : corriger issues existantes > merger PRs prêtes > avancer sur V2
4. **Avancement V2** : prendre le premier item non coché de la liste V2 ci-dessus
5. **Une PR par item V2** : ne jamais mélanger plusieurs features dans une PR
6. **Mettre à jour ce fichier** à chaque run : cocher les items terminés, ajouter les issues
7. **Ne pas travailler sur plus d'un item V2 par run** (garder les PRs petites et reviewables)
