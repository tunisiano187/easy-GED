#!/bin/bash
# =============================================================================
# easy-GED — Téléchargement du modèle IA Mistral 7B via Ollama
# À exécuter une seule fois après le premier démarrage d'Ollama
# Taille du téléchargement : ~4.1 Go (connexion internet requise)
# =============================================================================

set -e

OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
MODEL="${OLLAMA_MODEL:-mistral:7b-instruct}"

echo "================================================"
echo "  easy-GED — Téléchargement modèle IA"
echo "  Modèle : $MODEL"
echo "  Taille approximative : ~4.1 Go"
echo "================================================"
echo ""
echo "⚠ Cette opération peut prendre 10-30 minutes selon"
echo "  la vitesse de votre connexion internet."
echo ""

# Attendre qu'Ollama soit disponible
echo "→ Vérification disponibilité Ollama..."
MAX_WAIT=60
WAITED=0
until curl -sf "$OLLAMA_HOST/api/tags" > /dev/null 2>&1; do
    if [ $WAITED -ge $MAX_WAIT ]; then
        echo "ERREUR : Ollama n'est pas accessible après ${MAX_WAIT}s"
        echo "Vérifiez que le conteneur ged-ollama est démarré : docker compose ps"
        exit 1
    fi
    echo "  Attente Ollama... (${WAITED}s)"
    sleep 5
    WAITED=$((WAITED + 5))
done
echo "✓ Ollama disponible"

# Vérifier si le modèle est déjà téléchargé
echo ""
echo "→ Vérification si le modèle est déjà présent..."
EXISTING=$(curl -s "$OLLAMA_HOST/api/tags" | python3 -c "
import sys, json
data = json.load(sys.stdin)
models = [m['name'] for m in data.get('models', [])]
print('oui' if any('mistral' in m for m in models) else 'non')
" 2>/dev/null || echo "inconnu")

if [ "$EXISTING" = "oui" ]; then
    echo "✓ Modèle Mistral déjà présent, aucun téléchargement nécessaire"
else
    echo "→ Téléchargement du modèle $MODEL..."
    echo "  (Progression affichée ci-dessous)"
    echo ""

    # Utiliser docker exec si on est en dehors du conteneur
    if command -v docker &> /dev/null; then
        docker exec ged-ollama ollama pull "$MODEL"
    else
        # Sinon appel API direct
        curl -X POST "$OLLAMA_HOST/api/pull" \
            -H "Content-Type: application/json" \
            -d "{\"name\": \"$MODEL\", \"stream\": true}" \
            --no-buffer \
            | while IFS= read -r line; do
                STATUS=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('status',''))" 2>/dev/null || echo "")
                if [ -n "$STATUS" ]; then
                    echo "  $STATUS"
                fi
            done
    fi

    echo ""
    echo "✓ Modèle $MODEL téléchargé avec succès !"
fi

# Test rapide du modèle
echo ""
echo "→ Test rapide du modèle (extraction JSON)..."
TEST_RESPONSE=$(curl -s -X POST "$OLLAMA_HOST/api/generate" \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$MODEL\",
        \"prompt\": \"Réponds uniquement avec ce JSON : {\\\"status\\\": \\\"ok\\\", \\\"modele\\\": \\\"mistral\\\"}\",
        \"stream\": false,
        \"options\": {\"temperature\": 0, \"num_predict\": 50}
    }" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('response','erreur')[:100])" 2>/dev/null || echo "erreur de connexion")

echo "  Réponse test : $TEST_RESPONSE"

echo ""
echo "================================================"
echo "✓ Modèle IA prêt pour easy-GED !"
echo ""
echo "Prochaine étape : Créer les champs Paperless"
echo "  ./paperless/init/create-custom-fields.sh"
echo "================================================"
