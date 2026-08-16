#!/bin/bash
# =============================================================================
# easy-GED — Création des champs personnalisés Paperless-ngx
# À exécuter une seule fois après le premier démarrage de Paperless
# Usage : ./create-custom-fields.sh [PAPERLESS_URL] [ADMIN_USER] [ADMIN_PASSWORD]
# =============================================================================

set -e

PAPERLESS_URL="${1:-${PAPERLESS_URL:-http://localhost:8000}}"
ADMIN_USER="${2:-${PAPERLESS_ADMIN_USER:-admin}}"
ADMIN_PASSWORD="${3:-${PAPERLESS_ADMIN_PASSWORD}}"

if [ -z "$ADMIN_PASSWORD" ]; then
    echo "ERREUR : Mot de passe administrateur requis."
    echo "Usage : $0 [URL] [USER] [PASSWORD]"
    echo "   ou : PAPERLESS_ADMIN_PASSWORD=xxx $0"
    exit 1
fi

echo "================================================"
echo "  easy-GED — Initialisation champs Paperless"
echo "  URL : $PAPERLESS_URL"
echo "  User : $ADMIN_USER"
echo "================================================"

# Obtenir un token d'authentification
echo ""
echo "→ Obtention du token d'authentification..."
TOKEN_RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"${ADMIN_USER}\", \"password\": \"${ADMIN_PASSWORD}\"}" \
    "${PAPERLESS_URL}/api/token/")

TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['token'])" 2>/dev/null)

if [ -z "$TOKEN" ]; then
    echo "ERREUR : Impossible d'obtenir le token. Vérifiez l'URL et les identifiants."
    echo "Réponse : $TOKEN_RESPONSE"
    exit 1
fi

echo "✓ Token obtenu"

# Fonction pour créer un champ personnalisé
create_field() {
    local NAME="$1"
    local DATA_TYPE="$2"
    local EXTRA_DATA="${3:-}"

    echo ""
    echo "→ Création du champ : $NAME ($DATA_TYPE)..."

    PAYLOAD="{\"name\": \"${NAME}\", \"data_type\": \"${DATA_TYPE}\"${EXTRA_DATA}}"

    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Authorization: Token $TOKEN" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        "${PAPERLESS_URL}/api/custom_fields/")

    if [ "$RESPONSE" = "201" ]; then
        echo "  ✓ Champ '$NAME' créé avec succès"
    elif [ "$RESPONSE" = "400" ]; then
        echo "  ⚠ Champ '$NAME' existe déjà (ignoré)"
    else
        echo "  ✗ Erreur lors de la création de '$NAME' (HTTP $RESPONSE)"
    fi
}

# Créer les champs personnalisés easy-GED
create_field "emetteur" "string"
create_field "numero_facture" "string"
create_field "montant_total" "monetary"
create_field "date_echeance" "date"
create_field "iban" "string"
create_field "communication" "string"
create_field "statut_paiement" "select" ', "extra_data": {"select_options": ["Non Payé", "Payé", "En Litige", "Rappel Reçu"]}'

echo ""
echo "================================================"
echo "✓ Initialisation des champs personnalisés terminée !"
echo ""
echo "Prochaine étape : Importer le workflow n8n"
echo "  → Accès n8n : ${PAPERLESS_URL/8000/5678}"
echo "  → Fichier : n8n/workflows/ged-main-workflow.json"
echo "================================================"
