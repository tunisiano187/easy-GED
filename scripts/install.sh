#!/bin/bash
# =============================================================================
# easy-GED — Script d'installation one-shot
# Cible : Debian 12 / Ubuntu 24.04 LTS — AMD64 (VM Proxmox)
# Usage  : curl -sSL https://raw.githubusercontent.com/tunisiano187/easy-GED/main/scripts/install.sh | bash
#   ou   : chmod +x scripts/install.sh && ./scripts/install.sh
# =============================================================================

set -euo pipefail

# Couleurs
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERR]${NC}  $1"; exit 1; }

INSTALL_DIR="/opt/easy-ged"
REPO_URL="https://github.com/tunisiano187/easy-GED.git"

echo ""
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        easy-GED Installation           ║${NC}"
echo -e "${BLUE}║   GED Privée Auto-Hébergée avec IA     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# --- Vérifications préalables ---
info "Vérification de l'environnement..."

# Root ou sudo
if [ "$EUID" -ne 0 ]; then
    error "Ce script doit être exécuté en root ou avec sudo."
fi

# Système supporté
if ! grep -qE "(debian|ubuntu)" /etc/os-release 2>/dev/null; then
    warning "Système non-Debian/Ubuntu détecté. Le script peut ne pas fonctionner correctement."
fi

# Architecture AMD64
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    warning "Architecture $ARCH détectée (AMD64 recommandée). Ollama peut ne pas fonctionner."
fi

# RAM disponible
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
if [ "$TOTAL_RAM_MB" -lt 6000 ]; then
    warning "RAM disponible : ${TOTAL_RAM_MB}MB. Minimum recommandé : 8 Go pour Mistral 7B."
fi

# Espace disque
FREE_DISK_GB=$(df -BG / | awk 'NR==2{print $4}' | tr -d 'G')
if [ "$FREE_DISK_GB" -lt 15 ]; then
    error "Espace disque insuffisant : ${FREE_DISK_GB}Go libres. Minimum requis : 15 Go."
fi

success "Environnement validé (RAM: ${TOTAL_RAM_MB}MB, Disque libre: ${FREE_DISK_GB}Go)"

# --- Mise à jour système ---
echo ""
info "Mise à jour des paquets système..."
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq curl git python3 jq ca-certificates gnupg lsb-release unattended-upgrades
success "Paquets système installés"

# Activer les mises à jour automatiques de sécurité OS
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
success "Mises à jour automatiques de sécurité OS activées (unattended-upgrades)"

# --- Installation Docker ---
echo ""
info "Installation de Docker Engine..."

if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
    success "Docker déjà installé (version $DOCKER_VERSION)"
else
    # Méthode officielle Docker
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
    success "Docker installé et démarré"
fi

# Ajouter l'utilisateur non-root au groupe docker (si applicable)
SUDO_USER="${SUDO_USER:-}"
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    usermod -aG docker "$SUDO_USER"
    success "Utilisateur $SUDO_USER ajouté au groupe docker"
fi

# --- Cloner ou mettre à jour le dépôt ---
echo ""
info "Récupération du dépôt easy-GED..."

if [ -d "$INSTALL_DIR/.git" ]; then
    info "Dépôt existant détecté, mise à jour..."
    cd "$INSTALL_DIR"
    git pull origin main 2>/dev/null || git pull origin claude/plan-mise-en-place-cywqty 2>/dev/null || true
    success "Dépôt mis à jour"
else
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    success "Dépôt cloné dans $INSTALL_DIR"
fi

# --- Rendre les scripts exécutables ---
chmod +x scripts/*.sh
chmod +x paperless/init/*.sh
chmod +x paperless/scripts/*.sh

# --- Configuration .env ---
echo ""
info "Configuration de l'environnement..."

if [ -f "$INSTALL_DIR/.env" ]; then
    warning "Fichier .env existant détecté. Conservation sans modification."
    warning "Pour reconfigurer : nano $INSTALL_DIR/.env"
else
    cp "$INSTALL_DIR/.env.example" "$INSTALL_DIR/.env"

    # Générer les clés secrètes automatiquement
    PAPERLESS_SECRET=$(openssl rand -hex 32)
    N8N_KEY=$(openssl rand -hex 24)
    VM_IP=$(hostname -I | awk '{print $1}')

    sed -i "s|PAPERLESS_SECRET_KEY=changeme_openssl_rand_hex_32|PAPERLESS_SECRET_KEY=${PAPERLESS_SECRET}|" .env
    sed -i "s|N8N_ENCRYPTION_KEY=changeme_openssl_rand_hex_24|N8N_ENCRYPTION_KEY=${N8N_KEY}|" .env
    sed -i "s|PAPERLESS_URL=http://192.168.1.42:8000|PAPERLESS_URL=http://${VM_IP}:8000|" .env
    sed -i "s|N8N_WEBHOOK_BASE_URL=http://192.168.1.42:5678|N8N_WEBHOOK_BASE_URL=http://${VM_IP}:5678|" .env

    success "Fichier .env créé avec clés auto-générées (IP détectée : $VM_IP)"
    echo ""
    echo -e "${YELLOW}⚠ IMPORTANT : Édite le fichier .env avant de continuer :${NC}"
    echo "   nano $INSTALL_DIR/.env"
    echo ""
    echo "   Valeurs obligatoires à renseigner :"
    echo "   • PAPERLESS_ADMIN_PASSWORD"
    echo "   • POSTGRES_PASSWORD"
    echo "   • SMTP_HOST / SMTP_USER / SMTP_PASSWORD"
    echo "   • TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID"
    echo "   • SCANNER_SMB_USER / SCANNER_SMB_PASSWORD"
    echo ""
    read -rp "Appuyer sur ENTRÉE quand le .env est configuré..." _
fi

# --- Configuration n8n ---
echo ""
echo "=== Configuration n8n ==="
read -p "Avez-vous déjà un n8n existant que vous souhaitez utiliser ? [o/N] " use_external_n8n
if [[ "$use_external_n8n" =~ ^[oOyY]$ ]]; then
    read -p "URL de votre n8n (ex: http://192.168.1.10:5678) : " n8n_url
    sed -i "s|^N8N_EXTERNAL_URL=.*|N8N_EXTERNAL_URL=${n8n_url}|" .env
    echo -e "${YELLOW}⚠️  N'oubliez pas d'installer le package qrcode sur votre n8n :${NC}"
    echo "   npm install -g qrcode"
    echo "   + NODE_FUNCTION_ALLOW_EXTERNAL=qrcode dans vos env vars n8n"
    COMPOSE_PROFILES=""
else
    sed -i "s|^N8N_EXTERNAL_URL=.*|N8N_EXTERNAL_URL=|" .env
    COMPOSE_PROFILES="--profile internal-n8n"
fi

# --- Démarrer la stack Docker ---
echo ""
info "Téléchargement des images Docker..."
docker compose $COMPOSE_PROFILES pull 2>/dev/null | tail -5

echo ""
info "Démarrage des conteneurs..."
docker compose $COMPOSE_PROFILES up -d

# Attendre que les services soient prêts
echo ""
info "Attente de l'initialisation des services (jusqu'à 3 minutes)..."
MAX_WAIT=180
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    UNHEALTHY=$(docker compose ps 2>/dev/null | grep -c "unhealthy\|starting" || true)
    if [ "$UNHEALTHY" -eq 0 ]; then
        break
    fi
    sleep 10
    WAITED=$((WAITED + 10))
    echo -n "."
done
echo ""

docker compose ps

# --- Télécharger le modèle Mistral ---
echo ""
info "Téléchargement du modèle IA Mistral 7B (~4.1 Go)..."
info "Cette étape peut prendre 10-30 minutes selon votre connexion."
"$INSTALL_DIR/scripts/pull-model.sh"

# --- Créer les champs Paperless ---
echo ""
info "Initialisation des champs personnalisés Paperless..."
sleep 10  # Laisser Paperless finir son init
source <(grep -v '^#' .env | grep -v '^$')
"$INSTALL_DIR/paperless/init/create-custom-fields.sh" \
    "$PAPERLESS_URL" \
    "${PAPERLESS_ADMIN_USER:-admin}" \
    "$PAPERLESS_ADMIN_PASSWORD"

# --- Mises à jour automatiques du projet ---
echo ""
info "Configuration des mises à jour automatiques du projet..."
chmod +x "$INSTALL_DIR/scripts/update.sh"
cat > /etc/cron.d/easy-ged-update << EOF
# easy-GED — Mise à jour hebdomadaire du projet + images Docker (dimanche 3h00)
0 3 * * 0  root  INSTALL_DIR=/opt/easy-ged /opt/easy-ged/scripts/update.sh --project-only >> /var/log/easy-ged-update.log 2>&1
EOF
chmod 644 /etc/cron.d/easy-ged-update
success "Mise à jour automatique configurée (dimanche 3h00)"
info "Note : Les images Docker sont mises à jour par Watchtower (nuit à 3h00)"
info "Note : L'OS est mis à jour par unattended-upgrades (quotidien)"

# --- Sauvegardes ---
echo ""
info "Sauvegardes : gérées par Proxmox Backup Server (PBS)"
echo "  → Configurer le job PBS dans Proxmox UI : Datacenter → Backup → Add"
echo "  → Schedule recommandé : daily 04:00, rétention : keep-daily=7"

# --- Rapport final ---
VM_IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         easy-GED installé avec succès !        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Interfaces disponibles :${NC}"
echo "  📄 Paperless  : http://${VM_IP}:8000"
echo "  ⚙  n8n        : http://${VM_IP}:5678"
echo "  🐳 Portainer  : http://${VM_IP}:9000"
echo "  🤖 Ollama API : http://${VM_IP}:11434"
echo ""
echo -e "${BLUE}Avec Caddy (HTTPS local) :${NC}"
echo "  https://paperless.home.local"
echo "  https://n8n.home.local"
echo "  https://portainer.home.local"
echo ""
echo -e "${YELLOW}Étapes manuelles restantes :${NC}"
echo "  1. Importer le workflow n8n :"
echo "     → http://${VM_IP}:5678 → Workflows → Import from File"
echo "     → Fichier : ${INSTALL_DIR}/n8n/workflows/ged-main-workflow.json"
echo ""
echo "  2. Configurer ton scanner (voir README.md) :"
echo "     → Adresse SMB : ${VM_IP} / Dossier : consume"
echo "     → Identifiants : ceux définis dans SCANNER_SMB_USER/PASSWORD"
echo ""
echo "  3. Tester avec un document :"
echo "     → Copier un PDF dans : ${INSTALL_DIR}/consume/"
echo "     → Ou glisser un papier dans le scanner"
echo ""
echo -e "  Documentation complète : ${INSTALL_DIR}/README.md"
echo ""
