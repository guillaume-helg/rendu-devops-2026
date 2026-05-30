# Partie B — Packaging Helm & Déploiement Kubernetes de MIAGE-Bank

## 1. Chart Helm pour MIAGE-Bank

### Structure du chart

```
miage-bank/
├── Chart.yaml
├── values.yaml
├── values-prod.yaml
└── templates/
    ├── _helpers.tpl
    ├── configmap.yaml
    ├── deployment.yaml
    ├── externalsecret.yaml
    ├── ingress.yaml
    ├── namespace.yaml
    ├── networkpolicy.yaml
    ├── pdb.yaml
    ├── rbac.yaml
    ├── service.yaml
    └── serviceaccount.yaml
```

### Chart.yaml

```yaml
apiVersion: v2
name: miage-bank
description: A Helm chart for Kubernetes deployment of MIAGE-Bank
type: application
version: 0.1.0
appVersion: "1.0.0"
```

### values.yaml (Environnement dev)

| Paramètre | Valeur | Description |
|---|---|---|
| `replicaCount` | `1` | Nombre de réplicas (dev) |
| `image.repository` | `ghcr.io/guillaume-helg/miage-bank-backend` | Image GHCR publiée par la CI |
| `image.pullPolicy` | `IfNotPresent` | Évite de re-pull à chaque restart |
| `image.tag` | `latest` | Surchargé par la CI (Git SHA / semver) |
| `serviceAccount.create` | `true` | Crée un ServiceAccount dédié |
| `serviceAccount.name` | `miage-bank-sa` | Nom du ServiceAccount |
| `service.type` | `ClusterIP` | Exposition interne uniquement |
| `service.port` | `8080` | Port Spring Boot |
| `ingress.enabled` | `true` | Active l'Ingress |
| `ingress.className` | `traefik` | Controlleur Traefik |
| `ingress.hosts[0].host` | `miage-bank.local` | Hostname dev |
| `resources.limits` | `cpu: 500m, memory: 512Mi` | Limites de ressources |
| `resources.requests` | `cpu: 100m, memory: 256Mi` | Requests de ressources |
| `autoscaling.enabled` | `false` | HPA désactivé en dev |
| `config.springProfile` | `default` | Profil Spring Boot |
| `vault.secretPath` | `secret/data/miage-bank` | Chemin Vault KV v2 |

### values-prod.yaml (Surcharges production)

| Paramètre | Valeur | Description |
|---|---|---|
| `replicaCount` | `3` | Haute disponibilité |
| `ingress.hosts[0].host` | `miage-bank.production.local` | Hostname production |
| `resources.limits` | `cpu: 1000m, memory: 1024Mi` | Plus de headroom |
| `resources.requests` | `cpu: 250m, memory: 512Mi` | Plus de headroom |
| `autoscaling.enabled` | `true` | HPA activé (3→10 pods, seuil CPU 80%) |
| `config.springProfile` | `prod` | Profil Spring Boot prod |
| `vault.secretPath` | `secret/data/miage-bank-prod` | Chemin Vault séparé pour la prod |

### Deployment

Points clés du déploiement :

- **SecurityContext** : `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, drop all capabilities.
- **Probes** :
  - `startupProbe` : `GET /actuator/health/liveness` (30 tentatives, 2s d'intervalle)
  - `livenessProbe` : `GET /actuator/health/liveness` (10s d'intervalle)
  - `readinessProbe` : `GET /actuator/health/readiness` (5s d'intervalle)
- **Resources** : `limits` et `requests` définis et paramétrables via `values.yaml`.
- **Volume `/tmp`** : `emptyDir` monté pour permettre au filesystem read-only de fonctionner avec Spring Boot.

### Service

- Type : `ClusterIP` (exposition externe via Ingress uniquement)
- Port : `8080`

### Ingress

- IngressClass : `traefik`
- Hostname paramétrable via `values.yaml`
- TLS optionnel (non activé par défaut)

### NetworkPolicy

Le chart implémente une stratégie **default-deny** complète :

| Politique | Type | Description |
|---|---|---|
| `default-deny-ingress` | Ingress | Bloque tout trafic entrant sur le namespace |
| `allow-traefik-ingress` | Ingress | Autorise uniquement le trafic depuis le namespace `traefik` sur le port 8080 |
| `default-deny-egress` | Egress | Bloque tout trafic sortant du namespace |
| `allow-dns-egress` | Egress | Autorise la résolution DNS (port 53 UDP/TCP) |
| `allow-vault-egress` | Egress | Autorise la communication avec Vault (port 8200, namespace `default`) |

### RBAC

- **ServiceAccount** dédié : `miage-bank-sa`
- **Role** minimaliste (least privilege) : lecture seule sur `configmaps` et `secrets` (`get`, `watch`, `list`)
- **RoleBinding** : lie le ServiceAccount au Role dans le namespace

### Gestion des Secrets — Vault + External Secrets Operator

Les secrets sont gérés via **Vault + External Secrets Operator** (approche recommandée) :

- **SecretStore** `vault-backend` : pointe vers Vault (`http://vault.default.svc.cluster.local:8200`), authentification par token Kubernetes.
- **ExternalSecret** : extrait les secrets depuis le chemin `vault.secretPath` (configurable via `values.yaml`) et les injecte dans un Secret Kubernetes nommé `<release>-vault-secret`.
- Le token Vault est stocké dans un Secret Kubernetes séparé (`vault-token`) créé manuellement.

---

## 2. Déploiement dans Kubernetes

### Prérequis

1. **Vault** : injecter le token Vault dans Kubernetes :
   ```bash
   kubectl create secret generic vault-token --from-literal=token=votre-token -n miage-bank
   ```

2. **Validation du chart** :
   ```bash
   helm lint ./miage-bank
   helm template ./miage-bank
   helm install --dry-run miage-bank ./miage-bank
   ```

3. **Installation** :
   ```bash
   helm install miage-bank ./miage-bank -n miage-bank --create-namespace
   ```

   Pour la production :
   ```bash
   helm install miage-bank ./miage-bank -f values.yaml -f values-prod.yaml -n miage-bank
   ```

### Validation post-déploiement

- L'application est accessible via l'Ingress (`miage-bank.local` en dev)
- Les NetworkPolicies sont actives et bloquent tout trafic non autorisé
- Les secrets ne sont pas exposés en clair (gérés par Vault + ESO)

---

## 3. GitOps avec ArgoCD

### Application ArgoCD

Le fichier déclaratif `argocd/argocd-miage-bank.yaml` définit l'application :

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: miage-bank
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/guillaume-helg/rendus-miage-2026.git'
    path: tp-buildah-trivy-dive-helm/guillaume-helg/miage-bank
    targetRevision: main
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: miage-bank
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Déploiement via ArgoCD

```bash
kubectl apply -f argocd/argocd-miage-bank.yaml
```

ArgoCD va automatiquement « pull » le dépôt GitHub, instancier le Namespace `miage-bank` et injecter tous les composants Helm.

### Démonstration de la dérive (Drift) ArgoCD et réconciliation

ArgoCD compare constamment l'état désiré (défini dans Git) et l'état réel (sur le cluster).

- **Dérive (Drift)** : Si une modification manuelle (hors Git) est faite sur le cluster, l'état devient `OutOfSync`.
- **Réconciliation automatique** : Grâce à `selfHeal: true` et `prune: true`, ArgoCD écrase immédiatement la modification manuelle pour restaurer l'état désiré.

---

## 4. Guide de test de bout en bout (Local PC)

Pour valider l'ensemble du déploiement de la Partie B sur votre machine locale, suivez cette démarche étape par étape (en utilisant **Minikube** ou **Kind**).

### Étape 4.1 — Préparation de l'environnement local
1. Lancez votre cluster local avec l'Ingress Traefik/Nginx activé :
   ```bash
   minikube start --addons=ingress
   # Si minikube utilise ingress-nginx par défaut, modifiez la valeur ingress.className dans values.yaml à "nginx" ou déployez Traefik.
   ```
2. Créez le Namespace de l'application :
   ```bash
   kubectl create namespace miage-bank
   ```

### Étape 4.2 — Configuration de Vault et External Secrets Operator (ESO)
1. Installez **External Secrets Operator** via Helm :
   ```bash
   helm repo add external-secrets https://charts.external-secrets.io
   helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace
   ```
2. Déployez **HashiCorp Vault** en mode dev (pour les tests) :
   ```bash
   helm repo add hashicorp https://helm.releases.hashicorp.com
   helm install vault hashicorp/vault -n default --set "server.dev.enabled=true"
   ```
3. Récupérez le token d'administration (root token) de Vault dev :
   ```bash
   # Le token par défaut en mode dev est "root" ou affiché dans les logs du pod vault-0
   kubectl logs vault-0 -n default | grep "Root Token"
   ```
4. Configurez un secret dans Vault :
   ```bash
   # Entrez dans le pod Vault pour écrire le secret
   kubectl exec -it vault-0 -n default -- vault kv put secret/miage-bank spring.datasource.password="db-ultra-secure-pass"
   ```
5. Enregistrez le token dans Kubernetes pour qu'ESO puisse s'authentifier auprès de Vault :
   ```bash
   kubectl create secret generic vault-token --from-literal=token="root" -n miage-bank
   ```

### Étape 4.3 — Déploiement et validation du Chart Helm
1. Validez la syntaxe et simulez le rendu des templates :
   ```bash
   cd tp-buildah-trivy-dive-helm/guillaume-helg/
   helm lint ./miage-bank
   helm template ./miage-bank
   ```
2. Installez le chart localement :
   ```bash
   helm install miage-bank ./miage-bank -n miage-bank
   ```
3. Vérifiez que l'ExternalSecret a bien généré le secret Kubernetes :
   ```bash
   kubectl get externalsecret -n miage-bank
   # Devrait afficher le statut 'SecretSynced'
   
   kubectl get secret miage-bank-vault-secret -n miage-bank -o jsonpath='{.data.spring\.datasource\.password}' | base64 -d
   # Devrait afficher : db-ultra-secure-pass
   ```

### Étape 4.4 — Validation des NetworkPolicies
Pour vérifier que la politique de **default-deny** bloque bien tout le trafic sauf celui provenant de Traefik :
1. Tentez d'accéder au backend depuis un pod temporaire dans un autre namespace (ex: `default`) :
   ```bash
   kubectl run test-pod-blocked --rm -i --tty --image=curlimages/curl -n default -- curl -I -m 5 http://miage-bank.miage-bank.svc.cluster.local:8080
   # Résultat attendu : Connection timed out (bloqué par default-deny egress/ingress)
   ```
2. Le trafic depuis l'Ingress Traefik (ou les pods autorisés avec le label du controller) est le seul autorisé à joindre le backend.

### Étape 4.5 — Validation du GitOps ArgoCD et démonstration de la dérive (Drift)
1. Installez **ArgoCD** sur votre cluster local :
   ```bash
   kubectl create namespace argocd
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   ```
2. Déployez l'application ArgoCD déclarative :
   ```bash
   kubectl apply -f argocd/argocd-miage-bank.yaml
   ```
3. Ouvrez l'interface ArgoCD ou utilisez `kubectl` pour voir l'état :
   ```bash
   kubectl get application -n argocd miage-bank
   # Devrait afficher : Synced / Healthy
   ```
4. **Démonstration de la dérive** :
   Modifiez manuellement l'état du cluster (ex. passez à 5 réplicas au lieu de 1) :
   ```bash
   kubectl scale deployment miage-bank --replicas=5 -n miage-bank
   ```
5. **Observation de la réconciliation** :
   - Surveillez les pods immédiatement après :
     ```bash
     kubectl get pods -n miage-bank
     ```
   - ArgoCD détecte instantanément le Drift, marque l'application `OutOfSync` puis, grâce à `selfHeal: true`, termine automatiquement les 4 pods excédentaires pour restaurer l'état de référence défini dans Git (1 réplica).

---

## Arborescence complète des livrables

```
rendus-miage-2026/
├── .github/workflows/ci.yml                            ← Pipeline CI/CD GitHub Actions
├── README_ANSWER_PART_A.md                             ← Réponses Partie A (Buildah, Trivy, Dive, Pipeline)
├── README_ANSWER_PART_B.md                             ← Réponses Partie B (Helm, K8s, ArgoCD)
├── README_TODO.md                                      ← Idées d'améliorations futures (Dagger, Cosign, etc.)
├── README_SUBJECT.md                                   ← Sujet du TP
└── tp-buildah-trivy-dive-helm/
    └── guillaume-helg/
        ├── .containerignore                             ← Fichiers exclus du contexte de build
        ├── Containerfile.backend                        ← Containerfile backend (Approche 1)
        ├── Containerfile.frontend                       ← Containerfile frontend (Approche 1)
        ├── buildah-native-backend.sh                    ← Build natif Buildah backend (Approche 2)
        ├── buildah-native-frontend.sh                   ← Build natif Buildah frontend (Approche 2)
        ├── mise.toml                                    ← Gestion des outils et tâches locales
        ├── argocd/
        │   └── argocd-miage-bank.yaml                   ← Application ArgoCD déclarative
        └── miage-bank/                                  ← Chart Helm
            ├── Chart.yaml
            ├── values.yaml                              ← Valeurs dev
            ├── values-prod.yaml                         ← Surcharges production
            └── templates/
                ├── _helpers.tpl
                ├── configmap.yaml
                ├── deployment.yaml
                ├── externalsecret.yaml
                ├── ingress.yaml
                ├── namespace.yaml
                ├── networkpolicy.yaml
                ├── pdb.yaml
                ├── rbac.yaml
                ├── service.yaml
                └── serviceaccount.yaml
```
