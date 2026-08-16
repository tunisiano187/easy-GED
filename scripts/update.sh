#!/bin/bash
# =============================================================================
# easy-GED — Mise à jour automatique
# Met à jour : dépôt Git, images Docker, paquets OS
#
# Usage : sudo ./scripts/update.sh [--os-only] [--docker-only] [--project-only]
# Cron  : 0 3 * * 0  root  /opt/easy-ged/scripts/update.sh >> /var/log/easy-ged-update.log 2>&1
# =============================================================================

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/easy-ged}"
LOGFILE="/var/log/easy-ged-update.log"
FLAG_OS=true
FLAG_DOCKER=true
FLAG_PROJECT=true

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${BLUE}[INFO]${NC} $1"; }
success() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${GREEN}[OK]${NC}   $1"; }
warning() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${RED}[ERR]${NC}  $1"; }

# Parsing des arguments
for arg in "$@"; do
  case $arg in
    --os-only)      FLAG_DOCKER=false; FLAG_PROJECT=false ;;
    --docker-only)  FLAG_OS=false;     FLAG_PROJECT=false ;;
    --project-only) FLAG_OS=false;     FLAG_DOCKER=false ;;
  esac
done

echo ""
echo "============================================================"
info "easy-GED — Mise à jour $(date '+%d/%m/%Y %H:%M')"
echo "============================================================"

# --- Mise à jour du projet (git pull) ---
if [ "$FLAG_PROJECT" = true ]; then
  echo ""
  info "📦 Mise à jour du dépôt easy-GED..."

  if [ ! -d "$INSTALL_DIR/.git" ]; then
    warning "Dépôt git non trouvé dans $INSTALL_DIR — ignoré."
  else
    cd "$INSTALL_DIR"
    CURRENT_COMMIT=$(git rev-parse HEAD)

    # Récupère les dernières modifications
    git fetch origin main 2>/dev/null || git fetch origin claude/plan-mise-en-place-cywqty 2>/dev/null || true
    git pull origin main 2>/dev/null || git pull origin HEAD 2>/dev/null || true

    NEW_COMMIT=$(git rev-parse HEAD)

    if [ "$CURRENT_COMMIT" != "$NEW_COMMIT" ]; then
      success "Projet mis à jour ($(echo "$CURRENT_COMMIT" | head -c 7) → $(echo "$NEW_COMMIT" | head -c 7))"
    else
      success "Projet déjà à jour ($(echo "$CURRENT_COMMIT" | head -c 7))"
    fi
  fi
fi

# --- Mise à jour des images Docker ---
if [ "$FLAG_DOCKER" = true ]; then
  echo ""
  info "🐳 Mise à jour des images Docker..."

  if ! command -v docker &> /dev/null; then
    warning "Docker non disponible — ignoré."
  else
    cd "$INSTALL_DIR"

    # Watchtower s'en charge normalement, mais on force un pull ici
    docker compose pull --quiet 2>/dev/null || true

    # Redémarrer uniquement les conteneurs dont l'image a changé
    docker compose up -d --remove-orphans --quiet-pull 2>/dev/null || true

    # Nettoyer les images obsolètes
    docker image prune -f --filter "until=72h" > /dev/null 2>&1 || true

    success "Images Docker mises à jour et conteneurs redémarrés"

    # Vérification santé
    UNHEALTHY=$(docker compose ps 2>/dev/null | grep -c "unhealthy" || true)
    if [ "$UNHEALTHY" -gt 0 ]; then
      warning "$UNHEALTHY conteneur(s) en état unhealthy — vérifier avec : docker compose ps"
    fi
  fi
fi

# --- Mise à jour OS (sécurité uniquement) ---
if [ "$FLAG_OS" = true ]; then
  echo ""
  info "🔒 Mise à jour des paquets système (sécurité)..."

  if command -v apt-get &> /dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" 2>/dev/null || true

    # Vérifier si un redémarrage est nécessaire
    if [ -f /var/run/reboot-required ]; then
      warning "Un redémarrage est requis (noyau/libc mis à jour)"
      warning "Planifier : sudo systemctl reboot ou via Proxmox"
    fi

    success "Paquets système mis à jour"
  else
    warning "apt-get non disponible — système non Debian/Ubuntu ?"
  fi
fi

echo ""
echo "============================================================"
success "Mise à jour terminée — $(date '+%d/%m/%Y %H:%M')"
echo "============================================================"
echo ""
