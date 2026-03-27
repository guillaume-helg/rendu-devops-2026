#!/usr/bin/env bash
set -euo pipefail

# Approche 2 : Packaging d'un artefact préparé par la CI via Buildah natif
# Reproduit le même résultat que Containerfile.backend, sans Containerfile.

echo "Création du conteneur d'exécution (runner)..."
RUNNER=$(buildah from docker.io/library/eclipse-temurin:17-jre-alpine)
buildah run "$RUNNER" -- mkdir -p /app

echo "Création de l'utilisateur non-root..."
buildah run "$RUNNER" -- addgroup -S appgroup
buildah run "$RUNNER" -- adduser -S appuser -G appgroup

echo "Copie de l'artefact pré-compilé depuis la CI hôte..."
buildah copy --chown appuser:appgroup "$RUNNER" ./banque-micro-service/target/*.jar /app/app.jar

buildah config --workingdir /app --port 8080 --user appuser --entrypoint '["java", "-jar", "app.jar"]' "$RUNNER"
buildah commit "$RUNNER" miage-bank-backend:native

echo "Nettoyage..."
buildah rm "$RUNNER"

echo "Image native Buildah terminée : miage-bank-backend:native"
