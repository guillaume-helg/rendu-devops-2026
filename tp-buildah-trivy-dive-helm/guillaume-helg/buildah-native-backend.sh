#!/usr/bin/env bash
set -e

# Exemple d'approche 2 : Packaging d'un artefact préparé par la CI via Buildah natif

echo "Création du conteneur d'exécution (runner)..."
RUNNER=$(buildah from docker.io/library/eclipse-temurin:17-jre-alpine)
buildah run $RUNNER -- mkdir -p /app

echo "Copie de l'artefact pré-compilé depuis la CI hôte..."
buildah copy $RUNNER ./banque-micro-service/target/*.jar /app/app.jar

buildah config --workingdir /app --port 8080 --entrypoint '["java", "-jar", "app.jar"]' $RUNNER
buildah commit $RUNNER miage-bank-backend:native

echo "Nettoyage..."
buildah rm $RUNNER

echo "Image native Buildah terminée : miage-bank-backend:native"
