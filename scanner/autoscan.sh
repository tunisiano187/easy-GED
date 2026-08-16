#!/bin/bash
# =============================================================================
# easy-GED — Daemon de numérisation automatique (scanner USB)
#
# Deux modes selon le scanner utilisé :
#
#   SCAN_TRIGGER=adf    (défaut) — Brother ADS-1200 et tout scanner avec ADF
#     → Scrute en boucle l'ADF ; scan automatique dès qu'un document est inséré
#
#   SCAN_TRIGGER=button           — Brother DS-640 et scanners sans ADF
#     → Lance scanbd qui surveille le bouton physique du scanner ;
#       chaque appui déclenche un scan via scan-button.sh
#
# Prérequis communs :
#   - sane-utils installé (apt-get install -y sane-utils)
#   - Driver brscan5 installé (voir install-brscan5.sh)
#
# Prérequis mode button :
#   - scanbd installé (apt-get install -y scanbd)
#
# Usage :
#   ./autoscan.sh                        # Mode ADF (défaut)
#   SCAN_TRIGGER=button ./autoscan.sh    # Mode bouton (DS-640)
#   systemctl start ged-autoscan         # Via systemd (recommandé)
#
# Variables d'environnement :
#   SCAN_TRIGGER     — adf | button                    (défaut : adf)
#   CONSUME_DIR      — Dossier destination des scans   (défaut : /opt/easy-ged-pi/consume)
#   SCAN_DEVICE      — Identifiant SANE (auto si vide) (défaut : auto-detect)
#   SCAN_RESOLUTION  — Résolution DPI                  (défaut : 300)
#   SCAN_MODE        — Color | Gray | Black & White    (défaut : Color)
#   SCAN_SOURCE      — ADF | ADF Duplex | Flatbed      (défaut : ADF — mode adf uniquement)
#   POLL_INTERVAL    — Intervalle scrutation (secondes)(défaut : 3 — mode adf uniquement)
#   SCANBD_CONF      — Chemin config scanbd            (défaut : $(dirname $0)/scanbd.conf)
# =============================================================================

set -euo pipefail

# --- Configuration ---
SCAN_TRIGGER="${SCAN_TRIGGER:-adf}"
CONSUME_DIR="${CONSUME_DIR:-/opt/easy-ged-pi/consume}"
SCAN_DEVICE="${SCAN_DEVICE:-}"
SCAN_RESOLUTION="${SCAN_RESOLUTION:-300}"
SCAN_MODE="${SCAN_MODE:-Color}"
SCAN_SOURCE="${SCAN_SOURCE:-ADF}"
POLL_INTERVAL="${POLL_INTERVAL:-3}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANBD_CONF="${SCANBD_CONF:-${SCRIPT_DIR}/scanbd.conf}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${BLUE}[GED Autoscan]${NC} $1"; }
log_ok()  { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${GREEN}[GED Autoscan]${NC} $1"; }
log_warn(){ echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${YELLOW}[GED Autoscan]${NC} $1"; }
log_err() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${RED}[GED Autoscan]${NC} $1"; }

# --- Vérification commune ---
if ! command -v scanimage &>/dev/null; then
    log_err "scanimage introuvable — installer sane-utils :"
    log_err "  apt-get install -y sane-utils"
    exit 1
fi

if [ ! -d "$CONSUME_DIR" ]; then
    log "Création du dossier consume : $CONSUME_DIR"
    mkdir -p "$CONSUME_DIR"
fi

# --- Détection automatique du scanner ---
detect_scanner() {
    scanimage -L 2>/dev/null | grep -oP "(?<=device ')[^']+" | head -1 || true
}

wait_for_scanner() {
    local attempts=0
    while [ $attempts -lt 10 ]; do
        local dev
        dev=$(detect_scanner)
        if [ -n "$dev" ]; then
            echo "$dev"
            return 0
        fi
        log_warn "Aucun scanner détecté (tentative $((attempts+1))/10) — vérifier le câble USB..."
        sleep 10
        attempts=$((attempts + 1))
    done
    return 1
}

# =============================================================================
# MODE ADF — Brother ADS-1200 (et tout scanner avec chargeur automatique)
# Scrute l'ADF en boucle ; scan déclenché dès qu'un document est inséré
# =============================================================================
run_adf_mode() {
    log "Mode : ADF (scanner à chargeur automatique)"
    log "  Dossier destination : $CONSUME_DIR"
    log "  Résolution : ${SCAN_RESOLUTION} DPI | Mode : $SCAN_MODE | Source : $SCAN_SOURCE"
    log "  Intervalle scrutation : ${POLL_INTERVAL}s"

    if [ -z "$SCAN_DEVICE" ]; then
        log "Auto-détection du scanner..."
        SCAN_DEVICE=$(wait_for_scanner) || {
            log_err "Aucun scanner trouvé après 100s. Vérifier le câble USB."
            exit 1
        }
    fi

    log_ok "Scanner : $SCAN_DEVICE"
    log "Prêt — insérer un document pour déclencher automatiquement la numérisation"
    echo ""

    local consecutive_errors=0
    local max_errors=5

    while true; do
        local outfile="${CONSUME_DIR}/scan_$(date +%Y%m%d_%H%M%S).pdf"

        if scanimage \
            --device-name="${SCAN_DEVICE}" \
            --source="${SCAN_SOURCE}" \
            --mode="${SCAN_MODE}" \
            --resolution="${SCAN_RESOLUTION}" \
            --format=pdf \
            -o "${outfile}" \
            2>/tmp/scanimage_err.txt; then

            local filesize
            filesize=$(stat -c%s "${outfile}" 2>/dev/null || echo 0)
            if [ "$filesize" -gt 1024 ]; then
                log_ok "✓ Document numérisé → $(basename "${outfile}") (${filesize} octets)"
                consecutive_errors=0
            else
                log_warn "Fichier suspect (${filesize} octets) — supprimé"
                rm -f "${outfile}"
            fi
        else
            rm -f "${outfile}"
            local err_msg
            err_msg=$(cat /tmp/scanimage_err.txt 2>/dev/null | head -1)

            if echo "$err_msg" | grep -qiE "(no.*doc|feeder.*empty|ADF.*empty|STATUS_NO_DOCS)"; then
                consecutive_errors=0  # ADF vide = comportement normal
            elif echo "$err_msg" | grep -qiE "(io error|device.*busy|invalid|transport)"; then
                consecutive_errors=$((consecutive_errors + 1))
                log_warn "Erreur scanner (${consecutive_errors}/${max_errors}) : $err_msg"
                if [ $consecutive_errors -ge $max_errors ]; then
                    log_err "Trop d'erreurs — re-détection du scanner..."
                    SCAN_DEVICE=""
                    SCAN_DEVICE=$(wait_for_scanner) || { sleep 30; continue; }
                    log_ok "Scanner re-détecté : $SCAN_DEVICE"
                    consecutive_errors=0
                fi
            fi
        fi

        sleep "${POLL_INTERVAL}"
    done
}

# =============================================================================
# MODE BUTTON — Brother DS-640 (et scanners sans ADF)
# Lance scanbd qui surveille le bouton physique ;
# chaque appui déclenche scan-button.sh → PDF dans CONSUME_DIR
# =============================================================================
run_button_mode() {
    log "Mode : Bouton (scanner feuille à feuille, Brother DS-640)"
    log "  Dossier destination : $CONSUME_DIR"
    log "  Résolution : ${SCAN_RESOLUTION} DPI | Mode : $SCAN_MODE"
    log "  Config scanbd : $SCANBD_CONF"

    # Vérifier que scanbd est installé
    if ! command -v scanbd &>/dev/null; then
        log_err "scanbd non installé. Lancer :"
        log_err "  apt-get install -y scanbd"
        exit 1
    fi

    # Vérifier que la config scanbd existe
    if [ ! -f "$SCANBD_CONF" ]; then
        log_err "Fichier de config scanbd introuvable : $SCANBD_CONF"
        log_err "Copier scanner/scanbd.conf dans $SCANBD_CONF"
        exit 1
    fi

    # Vérifier que scan-button.sh est accessible
    local scan_script="${SCRIPT_DIR}/scan-button.sh"
    if [ ! -f "$scan_script" ]; then
        log_err "Script de scan introuvable : $scan_script"
        exit 1
    fi
    chmod +x "$scan_script"

    # Exporter les variables pour scan-button.sh
    export CONSUME_DIR SCAN_DEVICE SCAN_RESOLUTION SCAN_MODE

    log_ok "Démarrage de scanbd — appuyer sur le bouton du scanner pour numériser"
    echo ""

    # -f : foreground (pas de daemon, pour systemd)
    exec scanbd -f -c "${SCANBD_CONF}"
}

# =============================================================================
# Point d'entrée
# =============================================================================
case "$SCAN_TRIGGER" in
    adf)
        run_adf_mode
        ;;
    button)
        run_button_mode
        ;;
    *)
        log_err "SCAN_TRIGGER invalide : '$SCAN_TRIGGER'"
        log_err "Valeurs acceptées : adf (ADS-1200) | button (DS-640)"
        exit 1
        ;;
esac
