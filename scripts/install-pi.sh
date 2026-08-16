#!/bin/bash
# =============================================================================
# easy-GED — Installation sur Raspberry Pi 5 (mode split)
# Cible  : Raspberry Pi OS Lite 64-bit (Bookworm)
# Rôle   : Réception scanner SMB + transfert vers Paperless sur VM
#
# Usage  : curl -sSL https://raw.githubusercontent.com/tunisiano187/easy-GED/main/scripts/install-pi.sh | sudo bash
#   ou   : chmod +x scripts/install-pi.sh && sudo ./scripts/install-pi.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERR]${NC}  $1"; exit 1; }

INSTALL_DIR="/opt/easy-ged-pi"
REPO_URL="https://github.com/tunisiano187/easy-GED.git"

echo ""
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    easy-GED — Installation Pi 5        ║${NC}"
echo -e "${BLUE}║    Mode split : Scanner → VM Proxmox   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# --- Vérifications ---
if [ "$EUID" -ne 0 ]; then
  error "Ce script doit être exécuté en root ou avec sudo."
fi

ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
  warning "Architecture $ARCH détectée (arm64/aarch64 attendu pour Pi 5)."
fi

RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
success "Environnement : $ARCH, ${RAM_MB}MB RAM"

# --- Mise à jour système ---
echo ""
info "Mise à jour du système Raspberry Pi OS..."
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq curl git jq ca-certificates gnupg

# Activer les mises à jour automatiques de sécurité
apt-get install -y -qq unattended-upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
success "Mises à jour automatiques de sécurité activées"

# --- Installation Docker (ARM64) ---
echo ""
info "Installation de Docker Engine (ARM64)..."

if command -v docker &> /dev/null; then
  success "Docker déjà installé ($(docker --version | awk '{print $3}' | tr -d ','))"
else
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  systemctl enable docker
  systemctl start docker
  success "Docker installé"
fi

SUDO_USER="${SUDO_USER:-}"
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
  usermod -aG docker "$SUDO_USER"
  success "Utilisateur $SUDO_USER ajouté au groupe docker"
fi

# --- Cloner le dépôt ---
echo ""
info "Récupération du projet easy-GED..."

if [ -d "$INSTALL_DIR/.git" ]; then
  cd "$INSTALL_DIR"
  git pull origin main 2>/dev/null || true
  success "Dépôt mis à jour"
else
  git clone "$REPO_URL" "$INSTALL_DIR"
  cd "$INSTALL_DIR"
  success "Dépôt cloné dans $INSTALL_DIR"
fi

chmod +x scripts/*.sh
chmod +x paperless/scripts/*.sh

# --- Configuration .env ---
echo ""
info "Configuration..."

if [ -f "$INSTALL_DIR/.env" ]; then
  warning "Fichier .env existant — conservation sans modification."
else
  cp "$INSTALL_DIR/.env.example" "$INSTALL_DIR/.env"

  PI_IP=$(hostname -I | awk '{print $1}')
  sed -i "s|PI5_HOST=.*|PI5_HOST=${PI_IP}|" .env 2>/dev/null || true

  success "Fichier .env créé"
  echo ""
  echo -e "${YELLOW}⚠ IMPORTANT : Renseigner dans .env avant de continuer :${NC}"
  echo "   nano $INSTALL_DIR/.env"
  echo ""
  echo "   Valeurs obligatoires :"
  echo "   • PAPERLESS_URL=http://IP_VM:8000      ← IP de ta VM Proxmox"
  echo "   • PAPERLESS_API_TOKEN=xxx               ← Créer dans Paperless → Tokens API"
  echo "   • SCANNER_SMB_USER=scanner"
  echo "   • SCANNER_SMB_PASSWORD=xxx"
  echo ""
  read -rp "Appuyer sur ENTRÉE quand le .env est configuré..." _
fi

# --- Démarrer la stack Pi ---
echo ""
info "Démarrage de la stack Pi (Samba + Pusher + Watchtower)..."
cd "$INSTALL_DIR"
docker compose -f docker-compose.pi.yml pull --quiet
docker compose -f docker-compose.pi.yml up -d

sleep 5
docker compose -f docker-compose.pi.yml ps

# --- Configurer les mises à jour automatiques ---
echo ""
info "Configuration du cron de mise à jour automatique..."
cat > /etc/cron.d/easy-ged-pi-update << 'EOF'
# easy-GED Pi — Mise à jour hebdomadaire (dimanche 3h30)
30 3 * * 0  root  INSTALL_DIR=/opt/easy-ged-pi /opt/easy-ged-pi/scripts/update.sh >> /var/log/easy-ged-update.log 2>&1
EOF
chmod 644 /etc/cron.d/easy-ged-pi-update
success "Mise à jour automatique configurée (dimanche 3h30)"

# --- Rapport ---
PI_IP=$(hostname -I | awk '{print $1}')
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      easy-GED Pi 5 installé avec succès ! ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Partage SMB scanner :${NC}"
echo "  Adresse : \\\\${PI_IP}\\consume"
echo "  Identifiant : valeur de SCANNER_SMB_USER"
echo ""
echo -e "${YELLOW}Prochaines étapes :${NC}"
echo "  1. Configurer le scanner pour pointer vers \\\\${PI_IP}\\consume"
echo "  2. S'assurer que PAPERLESS_API_TOKEN est correct dans .env"
echo "  3. Tester en déposant un fichier dans le partage SMB"
echo ""
