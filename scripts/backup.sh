#!/bin/bash
# =============================================================================
# easy-GED — Sauvegarde chiffrée vers NAS Synology via Restic
# Cron recommandé : 0 4 * * * /opt/easy-ged/scripts/backup.sh >> /var/log/easy-ged-backup.log 2>&1
# =============================================================================

set -euo pipefail

# --- Configuration (depuis .env si disponible) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source <(grep -v '^#' "$ENV_FILE" | grep -v '^$' | sed 's/^/export /')
fi

NAS_SMB_HOST="${NAS_SMB_HOST:?Variable NAS_SMB_HOST non définie}"
NAS_SMB_SHARE="${NAS_SMB_SHARE:?Variable NAS_SMB_SHARE non définie}"
NAS_SMB_USER="${NAS_SMB_USER:?Variable NAS_SMB_USER non définie}"
NAS_SMB_PASSWORD="${NAS_SMB_PASSWORD:?Variable NAS_SMB_PASSWORD non définie}"
NAS_SMB_DOMAIN="${NAS_SMB_DOMAIN:-WORKGROUP}"
RESTIC_PASSWORD="${RESTIC_PASSWORD:?Variable RESTIC_PASSWORD non définie}"

# Répertoires
NAS_MOUNT="/mnt/nas-ged-backup"
RESTIC_REPO="${NAS_MOUNT}/restic-repo"
DOCKER_COMPOSE_DIR="${SCRIPT_DIR}/.."

# Rétention (30 jours de snapshots quotidiens)
KEEP_DAILY=30
KEEP_WEEKLY=8
KEEP_MONTHLY=6

LOG_PREFIX="[easy-GED backup $(date '+%Y-%m-%d %H:%M:%S')]"

echo "$LOG_PREFIX ============================================"
echo "$LOG_PREFIX Démarrage sauvegarde easy-GED"
echo "$LOG_PREFIX ============================================"

# --- 1. Monter le NAS ---
echo "$LOG_PREFIX Montage NAS ${NAS_SMB_HOST}/${NAS_SMB_SHARE}..."

if ! mountpoint -q "$NAS_MOUNT"; then
    mkdir -p "$NAS_MOUNT"
    mount -t cifs "//${NAS_SMB_HOST}/${NAS_SMB_SHARE}" "$NAS_MOUNT" \
        -o "username=${NAS_SMB_USER},password=${NAS_SMB_PASSWORD},domain=${NAS_SMB_DOMAIN},iocharset=utf8,file_mode=0600,dir_mode=0700" \
        || { echo "$LOG_PREFIX ERREUR : Impossible de monter le NAS"; exit 1; }
    echo "$LOG_PREFIX ✓ NAS monté"
else
    echo "$LOG_PREFIX ✓ NAS déjà monté"
fi

# --- 2. Initialiser le dépôt Restic si nécessaire ---
export RESTIC_REPOSITORY="$RESTIC_REPO"
export RESTIC_PASSWORD

mkdir -p "$RESTIC_REPO"

if ! restic snapshots --quiet > /dev/null 2>&1; then
    echo "$LOG_PREFIX Initialisation du dépôt Restic..."
    restic init
    echo "$LOG_PREFIX ✓ Dépôt Restic initialisé"
fi

# --- 3. Sauvegarder les volumes Docker via docker compose ---
echo "$LOG_PREFIX Sauvegarde des volumes Docker..."

# Créer un snapshot temporaire des données Paperless (export)
EXPORT_DIR="/tmp/ged-backup-export-$$"
mkdir -p "$EXPORT_DIR"

# Exporter les données Paperless (documents + base)
echo "$LOG_PREFIX → Export documents Paperless..."
docker exec ged-paperless document_exporter /usr/src/paperless/export 2>/dev/null || true

# Copier l'export vers le répertoire temporaire
docker cp ged-paperless:/usr/src/paperless/export/. "$EXPORT_DIR/paperless-export/" 2>/dev/null || true

# Dump PostgreSQL
echo "$LOG_PREFIX → Dump PostgreSQL..."
mkdir -p "$EXPORT_DIR/postgres"
docker exec ged-postgres pg_dumpall -U paperless > "$EXPORT_DIR/postgres/dump-$(date +%Y%m%d).sql" 2>/dev/null \
    || { echo "$LOG_PREFIX ⚠ Dump PostgreSQL échoué, continuation..."; }

# Backup n8n workflows
echo "$LOG_PREFIX → Backup n8n workflows..."
mkdir -p "$EXPORT_DIR/n8n"
docker exec ged-n8n n8n export:workflow --all --output=/tmp/n8n-export.json 2>/dev/null \
    && docker cp ged-n8n:/tmp/n8n-export.json "$EXPORT_DIR/n8n/" 2>/dev/null \
    || { echo "$LOG_PREFIX ⚠ Export n8n échoué, continuation..."; }

# Copier aussi la config du projet
cp -r "$DOCKER_COMPOSE_DIR/.env" "$EXPORT_DIR/" 2>/dev/null || true
cp -r "$DOCKER_COMPOSE_DIR/docker-compose.yml" "$EXPORT_DIR/" 2>/dev/null || true

# --- 4. Lancer Restic ---
echo "$LOG_PREFIX Sauvegarde Restic en cours..."
restic backup \
    "$EXPORT_DIR" \
    --tag "easy-ged" \
    --tag "$(date +%Y-%m-%d)" \
    --verbose=0 \
    || { echo "$LOG_PREFIX ERREUR : Sauvegarde Restic échouée"; rm -rf "$EXPORT_DIR"; exit 1; }

echo "$LOG_PREFIX ✓ Sauvegarde Restic terminée"

# --- 5. Nettoyage des anciens snapshots ---
echo "$LOG_PREFIX Nettoyage anciens snapshots..."
restic forget \
    --keep-daily "$KEEP_DAILY" \
    --keep-weekly "$KEEP_WEEKLY" \
    --keep-monthly "$KEEP_MONTHLY" \
    --prune \
    --quiet \
    || { echo "$LOG_PREFIX ⚠ Nettoyage échoué, continuation..."; }

# --- 6. Nettoyage local ---
rm -rf "$EXPORT_DIR"

# --- 7. Vérification intégrité (hebdomadaire, le dimanche) ---
DAY_OF_WEEK=$(date +%u)  # 7 = dimanche
if [ "$DAY_OF_WEEK" = "7" ]; then
    echo "$LOG_PREFIX Vérification intégrité du dépôt (hebdomadaire)..."
    restic check --quiet || echo "$LOG_PREFIX ⚠ Problème d'intégrité détecté !"
fi

# --- 8. Démonter le NAS ---
umount "$NAS_MOUNT" 2>/dev/null || true
echo "$LOG_PREFIX ✓ NAS démonté"

echo "$LOG_PREFIX ============================================"
echo "$LOG_PREFIX ✓ Sauvegarde terminée avec succès"
echo "$LOG_PREFIX ============================================"
