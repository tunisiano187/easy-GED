# =============================================================================
# easy-GED — Image n8n personnalisée avec génération QR Code locale
#
# Ajoute le package npm `qrcode` pour générer les QR Codes EPC (SEPA)
# directement dans les nœuds Code n8n, sans appel à un service externe.
#
# Usage : docker compose up -d  (build automatique via docker-compose.yml)
# =============================================================================

FROM n8nio/n8n:latest

USER root

# Installation du package qrcode (génération QR codes PNG/SVG/base64)
RUN npm install -g qrcode && npm cache clean --force

USER node
