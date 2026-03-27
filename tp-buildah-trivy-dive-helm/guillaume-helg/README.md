# Guillaume Helg

## Partie A — Chaîne de build OCI avec Buildah, Trivy et Dive

Livrables pour la Partie A :
- Analyse comparative Docker vs Buildah détaillée dans `analyse-docker-buildah.md`.
- `Containerfile` et scripts `buildah-native.sh` pour Backend et Frontend.
- Scan Trivy v0.69.3 et Audit Dive orchestrés par `mise.toml`.
- Pipeline CI Github Actions `.github/workflows/ci.yml`.

### Justification relative à l'export SARIF
L'action globale `upload-sarif` de GitHub (`github/codeql-action`) échoue habituellement avec l'erreur `Resource not accessible by integration` lors de l'envoi du rapport de sécurité Trivy. Cela se produit systématiquement lorsque le dépôt GitHub est configuré en mode **Privé** sur un compte Free, car la fonctionnalité *GitHub Advanced Security* (qui alimente l'onglet Security) est réservée aux dépôts publics ou aux entreprises.

Pour respecter l'exigence d'export du format SARIF sans bloquer la pipeline de CI, le workflow a été adapté avec la directive `continue-on-error: true` sur l'étape de l'action CodeQL. Le fichier de rapport `trivy-backend-report.sarif` est téléchargé publiquement à sa place depuis la section **Artifacts** des exécutions (Run) de GitHub Actions.
