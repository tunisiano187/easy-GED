#!/bin/bash
# =============================================================================
# Script de notification post-consommation Paperless → n8n
# Ce script est appelé automatiquement par Paperless après chaque document ingéré.
# Variables disponibles injectées par Paperless :
#   DOCUMENT_ID, DOCUMENT_FILE_NAME, DOCUMENT_CORRESPONDENT, DOCUMENT_TAGS,
#   DOCUMENT_ORIGINAL_FILENAME, DOCUMENT_ARCHIVE_PATH, DOCUMENT_SOURCE_PATH
# =============================================================================

# URL n8n : externe si N8N_EXTERNAL_URL est défini, interne sinon
N8N_BASE="${N8N_EXTERNAL_URL:-http://n8n:5678}"
N8N_WEBHOOK_URL="${N8N_WEBHOOK_URL:-${N8N_BASE}/webhook/paperless-document}"

# Construire le payload JSON avec les infos du document
PAYLOAD=$(cat <<EOF
{
  "document_id": ${DOCUMENT_ID},
  "document_file_name": "${DOCUMENT_FILE_NAME}",
  "document_correspondent": "${DOCUMENT_CORRESPONDENT}",
  "document_tags": "${DOCUMENT_TAGS}",
  "document_original_filename": "${DOCUMENT_ORIGINAL_FILENAME}",
  "document_archive_path": "${DOCUMENT_ARCHIVE_PATH:-}",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)

# Envoyer la notification à n8n (avec retry)
MAX_RETRIES=5
RETRY_DELAY=5
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_RETRIES ]; do
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        --max-time 30 \
        "$N8N_WEBHOOK_URL")

    if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
        echo "[easy-GED] Notification n8n envoyée pour document ID ${DOCUMENT_ID} (HTTP $HTTP_STATUS)"
        exit 0
    fi

    ATTEMPT=$((ATTEMPT + 1))
    echo "[easy-GED] Tentative $ATTEMPT/$MAX_RETRIES échouée (HTTP $HTTP_STATUS), retry dans ${RETRY_DELAY}s..."
    sleep $RETRY_DELAY
done

echo "[easy-GED] ERREUR : Impossible de notifier n8n après $MAX_RETRIES tentatives pour document ID ${DOCUMENT_ID}"
exit 1
