#!/usr/bin/env bash
set -euo pipefail

# Approche 2 : Packaging d'assets via Buildah natif (Artefact généré par la CI hôte)
# Reproduit le même résultat que Containerfile.frontend, sans Containerfile.

echo "Création du conteneur d'exécution..."
RUNNER=$(buildah from docker.io/library/node:20-alpine)
buildah config --workingdir /app "$RUNNER"

echo "Copie des assets front-end pré-compilés..."
buildah copy --chown node:node "$RUNNER" ./banque-front/package*.json /app/
buildah copy --chown node:node "$RUNNER" ./banque-front/.next /app/.next
buildah copy --chown node:node "$RUNNER" ./banque-front/public /app/public
# node_modules a été rempli par "npm ci" sur le runner CI
buildah copy --chown node:node "$RUNNER" ./banque-front/node_modules /app/node_modules

echo "Configuration de l'utilisateur non-root..."
buildah config --user node --port 3000 --cmd '["npm", "start"]' "$RUNNER"
buildah commit "$RUNNER" miage-bank-frontend:native

echo "Nettoyage..."
buildah rm "$RUNNER"

echo "Image native Buildah terminée : miage-bank-frontend:native"
