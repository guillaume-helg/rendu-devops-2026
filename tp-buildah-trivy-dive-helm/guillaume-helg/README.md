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

---

## Partie B — Packaging Helm & Déploiement Kubernetes de MIAGE-Bank

Livrables pour la Partie B :
- **Chart Helm** `miage-bank` complet incluant :
  - Support de `values.yaml` (dev) et `values-prod.yaml` (prod).
  - Déploiement sécurisé avec `livenessProbe`, `readinessProbe` et des limites/ressources.
  - Service `ClusterIP` et `Ingress` avec controlleur `traefik`.
  - `NetworkPolicy` en "default-deny" n'autorisant que le flux depuis Traefik Ingress.
  - Sécurité RBAC (`ServiceAccount`, `Role`, `RoleBinding`) selon le principe du moindre privilège.
  - **Gestion des Secrets** nativement couplée à Vault via `ExternalSecret` et `SecretStore`.
- **GitOps** : L'Application ArgoCD déclarative se trouve dans le répertoire `argocd/argocd-miage-bank.yaml`.

### Déploiement & Démonstration ArgoCD

Pour tester l'infrastructure :

#### 1. Vault
Si Vault est installé dans votre cluster, assurez-vous d'injecter votre token Vault dans Kubernetes :
```bash
kubectl create secret generic vault-token --from-literal=token=votre-token -n miage-bank
```

#### 2. Lancement du projet avec ArgoCD
Déployez le point d'entrée ArgoCD :
```bash
kubectl apply -f argocd/argocd-miage-bank.yaml
```
ArgoCD va automatiquement "pull" le dépôt GitHub, instancier le Namespace `miage-bank` et injecter tous les composants Helm.

#### 3. Démonstration de la dérive (Drift) ArgoCD
Si vous changez manuellement une valeur sur le cluster de production (ex: `kubectl scale deployment miage-bank --replicas=5 -n miage-bank`), ArgoCD détectera immédiatement que l'état live diverge de l'état désiré (défini à `replicaCount: 1` dans *values.yaml*).
L'option `selfHeal: true` activée forcera alors un retour automatique et immédiat au réplicas = 1 (l'état "Truth" contenu dans Git), résorbant ainsi la dérive.

