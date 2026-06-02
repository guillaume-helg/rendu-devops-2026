# Partie B — Packaging Helm & Déploiement Kubernetes de MIAGE-Bank

## 1. Chart Helm pour MIAGE-Bank

### Structure des charts (Architecture modulaire)

```
tp-buildah-trivy-dive-helm/
├── miage-bank/                                   ← Chart principal (Backend & Infrastructure)
│   ├── Chart.yaml                                ← Déclare les dépendances vers frontend et database
│   ├── values.yaml
│   ├── values-prod.yaml
│   └── templates/
│       ├── _helpers.tpl
│       ├── deployment.yaml                       ← Déploiement du backend
│       ├── service.yaml                          ← Service du backend
│       ├── ingress.yaml                          ← Ingress partagé
│       ├── networkpolicy.yaml                    ← Politiques de sécurité inter-services
│       ├── externalsecret.yaml                   ← Secrets via Vault + ESO
│       ├── namespace.yaml
│       ├── pdb.yaml
│       ├── rbac.yaml
│       └── serviceaccount.yaml
│
├── frontend/                                     ← Chart standalone pour le Frontend Next.js
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── _helpers.tpl
│       ├── deployment.yaml
│       ├── service.yaml
│       └── configmap.yaml
│
└── database/                                     ← Chart standalone pour MySQL
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        ├── _helpers.tpl
        ├── statefulset.yaml                      ← StatefulSet pour MySQL (au lieu de Deployment)
        ├── persistentvolumeclaim.yaml            ← Stockage persistant
        └── service.yaml
```

### Note d'architecture : Monolithe vs. Microservices dans banque-micro-service

> [!NOTE]
> Bien que le dépôt d'origine se nomme `banque-micro-service` et contienne des sous-dossiers pour différents microservices (`account-service`, `customer-service`, `gateway-service`, `discovery-service`, `config-service`, `composite-service`, `monitoring-service`), le fichier `pom.xml` racine compile l'ensemble de la logique métier sous la forme d'un **monolithe Spring Boot unique** (générant `TPAE-0.0.1-SNAPSHOT.jar` qui écoute sur le port `8080` et communique avec la base MySQL).
>
> Dans le cadre du sujet de ce TP, le packaging OCI et le déploiement Kubernetes ciblent ce **monolithe backend**. 
> Si nous devions déployer la véritable architecture microservices complète définie par les sous-dossiers :
> 1. Il faudrait créer **7 Containerfiles distincts** et compiler 7 images OCI indépendantes.
> 2. Il faudrait packager **7 charts ou subcharts Helm indépendants** pour orchestrer chaque service (avec des configurations de probes, de ressources et de variables d'environnement adaptées à chacun).
> 3. Il faudrait déployer et configurer des composants d'infrastructure complexes supplémentaires (comme le serveur de découverte Eureka, le serveur de configuration centralisé et l'API Gateway).
>
> Pour rester parfaitement fidèle au sujet du TP et assurer une simplicité opérationnelle, l'approche modulaire mise en œuvre sépare proprement :
> - Le **backend (TPAE)** sous forme de composant principal.
> - Le **frontend (Next.js)** sous forme de sous-chart autonome.
> - La **base de données (MySQL)** sous forme de sous-chart autonome (StatefulSet).

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
    repoURL: 'https://github.com/guillaume-helg/rendu-devops-2026.git'
    path: tp-buildah-trivy-dive-helm/miage-bank
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

Pour valider l'ensemble du déploiement de la Partie B sur votre machine locale, suivez cette démarche étape par étape (en utilisant **Minikube**).

> **Pré-requis** : Docker installé et démarré (`sudo systemctl start docker`), Helm et kubectl installés.

### Étape 4.0 — Remise à zéro (optionnel, si le cluster est déjà dans un état instable)
```bash
minikube delete
docker system prune -f
rm -rf ~/.kube/cache ~/.cache/helm
```

### Étape 4.1 — Démarrage du cluster Minikube
```bash
minikube start --memory=4096 --cpus=2
```

Vérifiez que le cluster est opérationnel :
```bash
kubectl get nodes
# Résultat attendu : minikube   Ready   control-plane   ...
```

### Étape 4.2 — Installation des opérateurs tiers (ESO & Vault)

1. Installez **External Secrets Operator** via Helm (avec les CRDs) :
   ```bash
   helm repo add external-secrets https://charts.external-secrets.io
   helm repo update
   helm install external-secrets external-secrets/external-secrets \
     -n external-secrets --create-namespace --set installCRDs=true
   ```

2. Déployez **HashiCorp Vault** en mode dev (pour les tests) :
   ```bash
   helm repo add hashicorp https://helm.releases.hashicorp.com
   helm install vault hashicorp/vault -n default --set "server.dev.enabled=true"
   ```

3. Attendez que le pod Vault soit prêt :
   ```bash
   kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=vault -n default --timeout=120s
   ```

### Étape 4.3 — Provisionnement des secrets

1. Écrivez le secret applicatif dans Vault :
   ```bash
   kubectl exec -it vault-0 -n default -- vault kv put secret/miage-bank \
     spring.datasource.password="db-ultra-secure-pass"
   ```

2. Créez le namespace `miage-bank` et le secret contenant le token Vault pour ESO :
   ```bash
   kubectl create namespace miage-bank
   kubectl create secret generic vault-token --from-literal=token="root" -n miage-bank
   ```

3. Annotez le namespace pour qu'il soit adopté par Helm lors de l'installation du chart (le chart contient un template `namespace.yaml`) :
   ```bash
   kubectl label namespace miage-bank app.kubernetes.io/managed-by=Helm
   kubectl annotate namespace miage-bank \
     meta.helm.sh/release-name=miage-bank \
     meta.helm.sh/release-namespace=miage-bank
   ```

### Étape 4.4 — Déploiement et validation du Chart Helm

Vous pouvez utiliser soit les commandes **Helm natives**, soit les raccourcis configurés dans **`mise.toml`** (recommandé car il installe et gère automatiquement la bonne version de Helm).

#### Option A — Via `mise` (Recommandé)

1. Mettre à jour les dépendances et valider les charts :
   ```bash
   cd tp-buildah-trivy-dive-helm/
   mise run helm:lint
   ```
2. Simuler le rendu des templates :
   ```bash
   mise run helm:template
   ```
3. Déployer l'application (Dev ou Prod) :
   ```bash
   # Pour l'environnement de Dev
   mise run helm:deploy

   # Pour l'environnement de Prod
   mise run helm:deploy:prod
   ```

#### Option B — Via commandes Helm natives

1. Mettre à jour les dépendances locales :
   ```bash
   cd tp-buildah-trivy-dive-helm/
   helm dependency update ./miage-bank
   ```
2. Valider la syntaxe et simulez le rendu :
   ```bash
   helm lint ./miage-bank
   helm lint ./frontend
   helm lint ./database
   helm template ./miage-bank
   ```
3. Installez le chart :
   ```bash
   helm install miage-bank ./miage-bank -n miage-bank
   ```

3. Vérifiez que l'ExternalSecret a bien généré le secret Kubernetes :
   ```bash
   kubectl get externalsecret -n miage-bank
   # Devrait afficher le statut 'SecretSynced'

   kubectl get secret miage-bank-vault-secret -n miage-bank \
     -o jsonpath='{.data.spring\.datasource\.password}' | base64 -d
   # Devrait afficher : db-ultra-secure-pass
   ```

### Étape 4.5 — Accès local via l'Ingress (minikube tunnel & /etc/hosts)

Puisque le service d'ingress utilise le nom d'hôte `miage-bank.local`, vous devez mapper ce nom d'hôte vers l'adresse IP de votre cluster Minikube (ou de son Ingress controller) pour pouvoir y accéder depuis votre navigateur ou votre console locale.

#### 1. Démarrer le tunnel Minikube (Requis pour exposer l'Ingress sur l'hôte)
Le contrôleur Ingress nécessite un service de type LoadBalancer pour être exposé en dehors du cluster minikube. Dans un terminal séparé (qui restera actif), lancez la commande suivante :
```bash
minikube tunnel
```
*Note : Cette commande peut vous demander votre mot de passe administrateur (sudo) afin de configurer les routes réseau sur votre machine hôte.*

#### 2. Récupérer l'adresse IP de l'Ingress
Une fois le tunnel démarré, vérifiez l'adresse IP externe assignée à l'Ingress :
```bash
kubectl get ingress -n miage-bank
```
Vous devriez voir une ligne similaire à celle-ci :
```
NAME         CLASS   HOSTS              ADDRESS     PORTS   AGE
miage-bank   nginx   miage-bank.local   127.0.0.1   80      34m
```
*Note : Si vous utilisez le driver docker de Minikube (notamment sur Windows/WSL), l'adresse IP (ADDRESS) sera `127.0.0.1`.*

#### 3. Ajouter l'entrée dans le fichier `hosts` de votre système

##### Sur Windows (Édition manuelle) :
1. Ouvrez le Bloc-notes (Notepad) en mode **Administrateur**.
2. Ouvrez le fichier : `C:\Windows\System32\drivers\etc\hosts`.
3. Ajoutez la ligne suivante tout en bas :
   ```
   127.0.0.1 miage-bank.local
   ```
4. Enregistrez le fichier.

##### Sur Linux / WSL / macOS :
Ouvrez votre terminal et exécutez la commande suivante pour ajouter l'entrée dans `/etc/hosts` :
```bash
echo "127.0.0.1 miage-bank.local" | sudo tee -a /etc/hosts
```

#### 4. Tester l'accès à l'application
Une fois le fichier `hosts` édité et le tunnel actif, vous pouvez ouvrir votre navigateur et accéder à :
- L'application Frontend : [http://miage-bank.local/](http://miage-bank.local/)
- L'API Backend (Santé / Actuator) : [http://miage-bank.local/api/actuator/health](http://miage-bank.local/api/actuator/health)

Vous pouvez également vérifier en ligne de commande :
```bash
curl -I http://miage-bank.local/
```
Le serveur doit renvoyer une réponse HTTP 200 OK de l'application Next.js.

### Étape 4.6 — Validation des NetworkPolicies

Pour vérifier que la politique de **default-deny** bloque bien tout le trafic sauf celui provenant de l'Ingress :
1. Tentez d'accéder au backend depuis un pod temporaire dans un autre namespace (ex: `default`) :
   ```bash
   kubectl run test-pod-blocked --rm -i --tty --image=curlimages/curl -n default \
     -- curl -I -m 5 http://miage-bank.miage-bank.svc.cluster.local:8080
   # Résultat attendu : Connection timed out (bloqué par default-deny ingress)
   ```
2. Le trafic depuis l'Ingress Controller (pods autorisés avec le label du controller) est le seul autorisé à joindre le backend.

### Étape 4.7 — Validation du GitOps ArgoCD et démonstration de la dérive (Drift)

1. Installez **ArgoCD** sur votre cluster local :
   ```bash
   kubectl create namespace argocd
   kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
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
    ├── .containerignore                             ← Fichiers exclus du contexte de build
    ├── Containerfile.backend                        ← Containerfile backend (Approche 1)
    ├── Containerfile.frontend                       ← Containerfile frontend (Approche 1)
    ├── buildah-native-backend.sh                    ← Build natif Buildah backend (Approche 2)
    ├── buildah-native-frontend.sh                   ← Build natif Buildah frontend (Approche 2)
    ├── mise.toml                                    ← Gestion des outils et tâches locales
    ├── argocd/
    │   └── argocd-miage-bank.yaml                   ← Application ArgoCD déclarative
    │
    ├── miage-bank/                                  ← Chart principal (Backend / Infra)
    │   ├── Chart.yaml                               ← Dépendances Chart
    │   ├── values.yaml                              ← Valeurs dev
    │   ├── values-prod.yaml                         ← Surcharges prod
    │   └── templates/
    │       ├── _helpers.tpl
    │       ├── deployment.yaml
    │       ├── externalsecret.yaml
    │       ├── ingress.yaml
    │       ├── namespace.yaml
    │       ├── networkpolicy.yaml
    │       ├── pdb.yaml
    │       ├── rbac.yaml
    │       ├── service.yaml
    │       └── serviceaccount.yaml
    │
    ├── frontend/                                    ← Chart Frontend Next.js standalone
    │   ├── Chart.yaml
    │   ├── values.yaml
    │   └── templates/
    │       ├── _helpers.tpl
    │       ├── configmap.yaml
    │       ├── deployment.yaml
    │       └── service.yaml
    │
    └── database/                                    ← Chart Database MySQL standalone
        ├── Chart.yaml
        ├── values.yaml
        └── templates/
            ├── _helpers.tpl
            ├── persistentvolumeclaim.yaml
            ├── service.yaml
            └── statefulset.yaml
```
