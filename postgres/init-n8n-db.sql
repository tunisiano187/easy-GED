-- Création de la base de données n8n dans le même PostgreSQL que Paperless
-- Ce script s'exécute automatiquement au premier démarrage du conteneur PostgreSQL

-- Créer la base n8n si elle n'existe pas déjà
SELECT 'CREATE DATABASE n8n OWNER paperless'
WHERE NOT EXISTS (
    SELECT FROM pg_database WHERE datname = 'n8n'
)\gexec

-- Accorder tous les droits à l'utilisateur paperless
GRANT ALL PRIVILEGES ON DATABASE n8n TO paperless;
