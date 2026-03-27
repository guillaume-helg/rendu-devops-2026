#!/usr/bin/env bash
set -e

# Exemple d'approche 2 : Packaging d'assets via Buildah natif (Artefact généré par la CI hôte)

echo "Création du conteneur d'exécution..."
RUNNER=$(buildah from docker.io/library/node:20-alpine)
buildah config --workingdir /app $RUNNER

echo "Copie des assets front-end pré-compilés..."
buildah copy $RUNNER ./banque-front/package*.json /app/
buildah copy $RUNNER ./banque-front/.next /app/.next
buildah copy $RUNNER ./banque-front/public /app/public
# Assumption: node_modules has been filled by "npm ci" on the CI runner
buildah copy $RUNNER ./banque-front/node_modules /app/node_modules

buildah config --port 3000 --cmd '["npm", "start"]' $RUNNER
buildah commit $RUNNER miage-bank-frontend:native

echo "Nettoyage..."
buildah rm $RUNNER

echo "Image native Buildah terminée : miage-bank-frontend:native"
