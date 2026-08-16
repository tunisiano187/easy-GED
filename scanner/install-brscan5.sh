#!/bin/bash
# =============================================================================
# easy-GED — Installation du driver Brother brscan5
# Compatible : Raspberry Pi 5 (ARM64), VM Debian/Ubuntu (AMD64)
# Scanners supportés : ADS-1200, ADS-1300, ADS-2200W, ADS-2700W, ...
#
# Usage : sudo ./install-brscan5.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERR]${NC}  $1"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Ce script doit être exécuté en root ou avec sudo."
fi

ARCH=$(dpkg --print-architecture)
info "Architecture détectée : $ARCH"

# --- Installer les dépendances SANE ---
info "Installation de sane-utils..."
apt-get update -qq
apt-get install -y -qq sane-utils libsane usbutils curl
success "sane-utils installé"

# --- URL du driver brscan5 selon l'architecture ---
# Source officielle Brother : https://support.brother.com/g/b/downloadlist.aspx?prod=ads1200_all&os=127
BRSCAN5_VERSION="1.2.8-1"

case "$ARCH" in
    arm64|aarch64)
        DEB_URL="https://download.brother.com/welcome/dlf105200/brscan5-${BRSCAN5_VERSION}.aarch64.deb"
        DEB_FILE="/tmp/brscan5.deb"
        ;;
    amd64|x86_64)
        DEB_URL="https://download.brother.com/welcome/dlf105200/brscan5-${BRSCAN5_VERSION}.amd64.deb"
        DEB_FILE="/tmp/brscan5.deb"
        ;;
    i386|i686)
        DEB_URL="https://download.brother.com/welcome/dlf105200/brscan5-${BRSCAN5_VERSION}.i386.deb"
        DEB_FILE="/tmp/brscan5.deb"
        ;;
    *)
        error "Architecture non supportée : $ARCH. Télécharger le driver manuellement sur https://support.brother.com"
        ;;
esac

# --- Téléchargement ---
info "Téléchargement du driver brscan5 v${BRSCAN5_VERSION} (${ARCH})..."
if ! curl -fsSL "${DEB_URL}" -o "${DEB_FILE}"; then
    error "Échec du téléchargement depuis : ${DEB_URL}
Vérifier la connexion internet ou télécharger manuellement sur :
https://support.brother.com/g/b/downloadlist.aspx?prod=ads1200_all&os=127"
fi
success "Driver téléchargé"

# --- Installation ---
info "Installation du driver..."
dpkg -i "${DEB_FILE}" || {
    warning "dpkg a signalé des dépendances manquantes — tentative de correction..."
    apt-get install -f -y -qq
}
rm -f "${DEB_FILE}"
success "Driver brscan5 installé"

# --- Enregistrement du scanner ---
info "Enregistrement du Brother ADS-1200 dans brscan5..."
brsaneconfig5 -a name=ADS-1200 model=ADS-1200 nodename=localhost 2>/dev/null || {
    warning "brsaneconfig5 non trouvé — le scanner sera détecté automatiquement au démarrage."
}

# --- Vérification ---
echo ""
info "Vérification — détection du scanner..."
sleep 1

if scanimage -L 2>/dev/null | grep -qi "brother"; then
    success "✓ Scanner Brother détecté !"
    scanimage -L
else
    warning "Scanner non détecté immédiatement."
    echo ""
    echo "Vérifications à faire :"
    echo "  1. Câble USB branché ? → lsusb | grep Brother"
    echo "  2. Scanner allumé ?"
    echo "  3. Relancer : scanimage -L"
    echo ""
    echo "Si lsusb détecte le scanner mais pas scanimage :"
    echo "  sudo udevadm control --reload-rules"
    echo "  sudo udevadm trigger"
fi

# --- Installation de scanbd (pour les scanners bouton, ex: DS-640) ---
echo ""
read -rp "Installer scanbd (détection du bouton pour Brother DS-640) ? [o/N] " INSTALL_SCANBD
INSTALL_SCANBD="${INSTALL_SCANBD:-N}"
if [[ "$INSTALL_SCANBD" =~ ^[oOyY] ]]; then
    info "Installation de scanbd..."
    apt-get install -y -qq scanbd
    success "scanbd installé"
    echo ""
    echo -e "${YELLOW}⚠ Configuration scanbd :${NC}"
    echo "  Éditer SCAN_TRIGGER=button dans /etc/systemd/system/ged-autoscan.service"
    echo "  puis : systemctl daemon-reload && systemctl restart ged-autoscan"
fi

echo ""
success "Installation terminée."
echo ""
echo "Prochaines étapes :"
echo "  1. Copier le service systemd :"
echo "     sudo cp scanner/autoscan.service /etc/systemd/system/ged-autoscan.service"
echo ""
echo "  2. Choisir le mode dans le service :"
echo "     SCAN_TRIGGER=adf    → Brother ADS-1200 (chargeur automatique)"
echo "     SCAN_TRIGGER=button → Brother DS-640   (bouton physique)"
echo ""
echo "  3. Activer et démarrer :"
echo "     sudo systemctl daemon-reload"
echo "     sudo systemctl enable --now ged-autoscan"
echo ""
echo "  Voir : README.md → section 'Scanner USB (Pi 5)'"
