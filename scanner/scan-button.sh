#!/bin/bash
# =============================================================================
# easy-GED — Script de numérisation déclenché par bouton (Brother DS-640)
#
# Ce script est appelé automatiquement par scanbd quand le bouton
# physique du scanner est pressé.
#
# Il est configuré dans scanner/scanbd.conf (clé "script").
# Ne pas appeler manuellement — passer par "systemctl start ged-autoscan"
# avec SCAN_TRIGGER=button.
#
# Variables d'environnement (exportées par autoscan.sh ou scanbd.conf) :
#   CONSUME_DIR      — Dossier destination           (défaut : /opt/easy-ged-pi/consume)
#   SCAN_DEVICE      — Identifiant SANE              (défaut : auto-detect)
#   SCAN_RESOLUTION  — Résolution DPI                (défaut : 300)
#   SCAN_MODE        — Color | Gray | Black & White  (défaut : Color)
# =============================================================================

set -euo pipefail

CONSUME_DIR="${CONSUME_DIR:-/opt/easy-ged-pi/consume}"
SCAN_DEVICE="${SCAN_DEVICE:-}"
SCAN_RESOLUTION="${SCAN_RESOLUTION:-300}"
SCAN_MODE="${SCAN_MODE:-Color}"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTFILE="${CONSUME_DIR}/scan_${TIMESTAMP}.pdf"
LOGFILE="/var/log/ged-autoscan.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [scan-button] $1" | tee -a "$LOGFILE"; }

log "Bouton pressé — démarrage de la numérisation..."

# Créer le dossier si nécessaire
mkdir -p "$CONSUME_DIR"

# Auto-détecter le scanner si non configuré
if [ -z "$SCAN_DEVICE" ]; then
    SCAN_DEVICE=$(scanimage -L 2>/dev/null | grep -oP "(?<=device ')[^']+" | head -1 || true)
    if [ -z "$SCAN_DEVICE" ]; then
        log "ERREUR : Aucun scanner détecté. Vérifier le câble USB."
        exit 1
    fi
fi

log "Scanner : $SCAN_DEVICE"
log "Destination : $OUTFILE"

# Numérisation
# Pour le DS-640 (scanner feuille à feuille) : pas de source ADF, scan direct
if scanimage \
    --device-name="${SCAN_DEVICE}" \
    --mode="${SCAN_MODE}" \
    --resolution="${SCAN_RESOLUTION}" \
    --format=pdf \
    -o "${OUTFILE}" \
    2>>"$LOGFILE"; then

    FILESIZE=$(stat -c%s "${OUTFILE}" 2>/dev/null || echo 0)

    if [ "$FILESIZE" -gt 1024 ]; then
        log "✓ Numérisé avec succès → $(basename "${OUTFILE}") (${FILESIZE} octets)"
        log "  Le fichier sera envoyé à Paperless par pi-pusher..."
    else
        log "AVERTISSEMENT : Fichier trop petit (${FILESIZE} octets) — supprimé"
        rm -f "${OUTFILE}"
        exit 1
    fi
else
    log "ERREUR : La numérisation a échoué. Vérifier que le document est bien inséré."
    rm -f "${OUTFILE}"
    exit 1
fi
