#!/bin/bash
# =============================================================================
# easy-GED — Push fichier vers Paperless via API REST
# Utilisé par le service pi-pusher (mode split Pi 5 + VM)
#
# Variables d'environnement requises :
#   PAPERLESS_URL        URL de Paperless (ex: http://192.168.1.42:8000)
#   PAPERLESS_API_TOKEN  Token API Paperless (Paramètres → Tokens API)
#
# Usage : ./push-to-paperless.sh /chemin/vers/fichier.pdf [titre]
# =============================================================================

set -euo pipefail

FILE="${1:-}"
TITRE="${2:-}"

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "[$(date '+%H:%M:%S')] ERREUR : fichier introuvable : $FILE"
  exit 1
fi

FILENAME=$(basename "$FILE")
PAPERLESS_URL="${PAPERLESS_URL:-http://localhost:8000}"
TOKEN="${PAPERLESS_API_TOKEN:-}"

if [ -z "$TOKEN" ]; then
  echo "[$(date '+%H:%M:%S')] ERREUR : PAPERLESS_API_TOKEN non défini"
  exit 1
fi

echo "[$(date '+%H:%M:%S')] Envoi vers Paperless : $FILENAME"

# Construire la commande curl
CURL_ARGS=(
  -s
  -o /tmp/paperless-response.json
  -w "%{http_code}"
  -X POST "$PAPERLESS_URL/api/documents/post_document/"
  -H "Authorization: Token $TOKEN"
  -F "document=@$FILE;filename=$FILENAME"
)

# Ajouter le titre si fourni
if [ -n "$TITRE" ]; then
  CURL_ARGS+=(-F "title=$TITRE")
fi

HTTP_CODE=$(curl "${CURL_ARGS[@]}" 2>/dev/null || echo "000")

case "$HTTP_CODE" in
  200|202)
    TASK_ID=$(cat /tmp/paperless-response.json 2>/dev/null | grep -o '"task_id":"[^"]*"' | cut -d'"' -f4 || echo "inconnu")
    echo "[$(date '+%H:%M:%S')] ✓ Document envoyé (HTTP $HTTP_CODE, task: $TASK_ID)"
    rm -f "$FILE"
    ;;
  000)
    echo "[$(date '+%H:%M:%S')] ✗ Erreur réseau — Paperless inaccessible ($PAPERLESS_URL)"
    exit 1
    ;;
  401)
    echo "[$(date '+%H:%M:%S')] ✗ Authentification échouée — vérifier PAPERLESS_API_TOKEN"
    exit 1
    ;;
  *)
    echo "[$(date '+%H:%M:%S')] ✗ Erreur HTTP $HTTP_CODE"
    cat /tmp/paperless-response.json 2>/dev/null || true
    exit 1
    ;;
esac

rm -f /tmp/paperless-response.json
