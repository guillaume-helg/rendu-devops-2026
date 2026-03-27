# Rapport Trivy — Analyse des CVE et plan de remédiation

> Ce rapport documente les vulnérabilités identifiées par Trivy v0.69.3 sur les images OCI de MIAGE-Bank.
> Les rapports JSON et SARIF complets sont disponibles dans le répertoire `build-reports/` (générés par la CI).

## Configuration du scan

```bash
# Scan filtré sur HIGH et CRITICAL, avec gate bloquante sur CRITICAL
trivy image --severity HIGH,CRITICAL --exit-code 1 -f json -o build-reports/trivy-backend-report.json miage-bank-backend:latest
trivy image --severity HIGH,CRITICAL -f sarif -o build-reports/trivy-backend-report.sarif miage-bank-backend:latest
```

- **Image de base backend** : `eclipse-temurin:17-jre-alpine`
- **Image de base frontend** : `node:20-alpine`
- **Gate CI** : `--exit-code 1` interrompt le pipeline si des CVE CRITICAL sont détectées.

---

## Backend — eclipse-temurin:17-jre-alpine

### Vulnérabilités attendues

L'image Alpine JRE est une image minimaliste. Les CVE typiquement remontées par Trivy sur cette stack sont :

| CVE | Package | Sévérité | Description | Remédiation |
|-----|---------|----------|-------------|-------------|
| CVE liées à OpenSSL | `libssl3` / `libcrypto3` | HIGH | Vulnérabilités dans la bibliothèque TLS Alpine | Mettre à jour l'image de base (`apk upgrade` ou tag plus récent) |
| CVE liées à `zlib` | `zlib` | HIGH | Buffer overflow dans la décompression | Idem — mise à jour de l'image de base |
| CVE liées au JDK | `java/jre` | HIGH/CRITICAL | Failles dans la JVM (désérialisation, JNDI) | Passer au dernier patch Temurin 17.x |

> **Note** : Les CVE exactes dépendent de la date de build. Consultez le fichier `build-reports/trivy-backend-report.json` pour la liste précise.

### Stratégie de remédiation

1. **Mise à jour régulière de l'image de base** : reconstruire l'image hebdomadairement pour intégrer les patchs Alpine.
2. **Pinning du tag image** : utiliser `eclipse-temurin:17.0.x-jre-alpine` au lieu de `17-jre-alpine` pour des builds reproductibles.
3. **Scan en CI bloquant** : le flag `--exit-code 1` garantit qu'aucune image avec CVE CRITICAL ne sera déployée.

---

## Frontend — node:20-alpine

### Vulnérabilités attendues

| CVE | Package | Sévérité | Description | Remédiation |
|-----|---------|----------|-------------|-------------|
| CVE liées à Node.js | `nodejs` | HIGH | Failles HTTP/2, DNS rebinding, prototype pollution | Utiliser le dernier patch Node 20.x LTS |
| CVE liées à npm | `npm` (bundled) | HIGH | Vulnérabilités dans les dépendances transitives | `npm audit fix` + mise à jour image |
| CVE Alpine communes | `libssl3`, `busybox` | HIGH | Mêmes CVE systèmes que le backend | `apk upgrade` dans le Containerfile |

### Stratégie de remédiation

1. **Utiliser Node.js standalone output** : réduire la surface d'attaque en éliminant `node_modules` au profit de `next build --standalone`.
2. **Multi-stage build** : séparer le build (image `node:20-alpine` complète) de l'exécution (image `node:20-alpine` minimale avec seulement le standalone output).
3. **Scan des dépendances npm** : ajouter `npm audit --audit-level=high` dans la CI avant le build d'image.

---

## Abaissement de la gate de sécurité

Si certaines CVE CRITICAL ne disposent pas de correctif disponible (« no fix available »), la gate peut être abaissée en retirant `--exit-code 1` de la tâche Trivy concernée. Dans ce cas, la justification doit être documentée ici et le rapport JSON fait foi.

> **État actuel** : la gate est activée à CRITICAL. Si la CI échoue à cause d'une CVE sans correctif, le flag sera ajusté et cette section mise à jour avec la justification.

---

## Rapports générés

| Fichier | Format | Contenu |
|---------|--------|---------|
| `build-reports/trivy-backend-report.json` | JSON | Rapport complet backend |
| `build-reports/trivy-backend-report.sarif` | SARIF | Compatible GitHub Security tab |
| `build-reports/trivy-frontend-report.json` | JSON | Rapport complet frontend |
| `build-reports/trivy-frontend-report.sarif` | SARIF | Compatible GitHub Security tab |
