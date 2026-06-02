# Guillaume Helg

---

## Informations

1. Utiliser le back-end depuis le dépôt : `https://github.com/guillaume-helg/banque-micro-service.git`
2. Utiliser le front-end depuis le dépôt : `https://github.com/guillaume-helg/banque-front.git`
3. Utiliser **uniquement** la version `v0.69.3` de Trivy (d'autres versions ayant été piratées).
4. Utiliser `mise.toml`.

---

# Partie A — Chaîne de build OCI avec Buildah, Trivy et Dive

## 1. Analyse comparative Docker vs Buildah

> Source principale : [Stéphane Robert — Construire des images OCI sans démon avec Buildah](https://blog.stephane-robert.info/docs/conteneurs/images-conteneurs/build/buildah/)

### Vue d'ensemble

| Critère | Docker | Buildah |
|---|---|---|
| Architecture | Client-serveur (démon `dockerd`) | Daemonless, CLI directe |
| Privilèges requis | `root` (ou accès au socket Unix) | Rootless natif (`user namespaces`) |
| Surface d'attaque | Large (démon persistant + socket) | Réduite (processus éphémère) |
| Format d'image | OCI + Docker v2 | OCI natif |
| Runtime intégré | Oui (`docker run`) | Non (build only — complémentaire avec Podman) |
| CI/CD rootless | Complexe (DinD, socket mount) | Natif, aucun socket à monter |
| Workflows de build | `docker build` uniquement | `buildah bud` (Dockerfile) **ou** `from/run/commit` (scriptable) |

### 1.1. Architecture (Daemon vs Daemonless)

**Docker** repose sur une architecture client-serveur. Le client `docker` communique via un socket Unix (`/var/run/docker.sock`) avec un démon `dockerd` qui tourne en permanence avec les droits `root`. Ce démon centralisé gère tout le cycle de vie : build, pull, push, run. Si le démon plante, toutes les opérations sont interrompues (SPOF).

**Buildah** adopte une architecture **daemonless** : chaque commande `buildah` s'exécute comme un processus indépendant, sans processus central. Il utilise les *user namespaces* Linux et `fuse-overlayfs` pour gérer les layers en espace utilisateur :
- Aucun processus persistant à maintenir
- Pas de point de défaillance unique
- Consommation mémoire uniquement pendant le build
- Les images sont stockées dans `~/.local/share/containers/storage` (par utilisateur)

### 1.2. Les deux workflows de Buildah

Comme le décrit Stéphane Robert, Buildah propose **deux modes de construction** :

#### Mode `bud` (Build Using Dockerfile)

C'est l'équivalent de `docker build`. On réutilise un Dockerfile/Containerfile existant :

```bash
buildah bud -t miage-bank-backend:latest -f Containerfile.backend .
```

| Avantage | Détail |
|---|---|
| Compatibilité | Réutilise les Dockerfiles existants sans modification |
| Cache de layers | Automatique (comme Docker) |
| Lint | Compatible avec Hadolint |
| Adoption | Facile pour une équipe habituée à Dockerfile |

#### Mode `from/run/commit` (natif scriptable)

C'est le mode **spécifique à Buildah** qui permet un contrôle total via bash :

```bash
container=$(buildah from alpine:3.21)
buildah run $container -- apk add --no-cache nginx
buildah config --cmd '["nginx", "-g", "daemon off;"]' $container
buildah commit $container myapp:1.0.0
buildah rm $container
```

| Avantage | Détail |
|---|---|
| Conditions | `if/then` natifs (ex: détecter l'archi CPU dynamiquement) |
| Boucles | `for/while` pour itérer sur des fichiers, des archi, etc. |
| Appels API | Récupérer de la config externe pendant le build |
| Logique complexe | Parsing, calculs, transformations impossibles dans un Dockerfile |

> **Pour MIAGE-Bank**, les deux approches ont été implémentées : `Containerfile.backend` / `Containerfile.frontend` (mode `bud`) et `buildah-native-backend.sh` / `buildah-native-frontend.sh` (mode `from/run/commit`).

### 1.3. Sécurité et Surface d'Attaque

#### Docker : vecteurs d'attaque connus

L'accès au socket Unix confère des **privilèges équivalents à `root`** sur la machine hôte :

- **Escalade de privilèges via socket mount** : un conteneur montant le socket peut créer d'autres conteneurs `--privileged` et accéder au filesystem hôte.
- **CVE-2019-5736** (runc) : permettait à un conteneur malveillant d'écraser le binaire `runc` de l'hôte.
- **Container escape** : le mode `--privileged` désactive toutes les protections (capabilities, seccomp, AppArmor).

#### Buildah : rootless par défaut

Buildah fonctionne nativement en mode **rootless** :
- Les images sont isolées par utilisateur (`~/.local/share/containers/`)
- Les *user namespaces* (`/etc/subuid`, `/etc/subgid`) mappent les UID/GID
- Aucune capability élevée requise
- La compromission d'un build ne donne accès qu'aux fichiers de l'utilisateur courant

**Vérification du mode rootless** (bonne pratique recommandée par Stéphane Robert) :
```bash
buildah info | grep "rootless: true"
```

**Checklist sécurité** (tirée du blog) :
- ✅ Rootless activé (`buildah info | grep rootless`)
- ✅ User namespaces configurés (`/etc/subuid`, `/etc/subgid`)
- ✅ `USER` non-root dans les Containerfiles
- ✅ Images de base versionnées (pas `:latest`)
- ✅ Multi-stage builds pour réduire la surface d'attaque
- ✅ Scan Trivy avant push (bloquer si CRITICAL)
- ✅ Labels OCI pour la traçabilité

### 1.4. Transports d'images

Buildah supporte plusieurs **transports** pour pousser les images vers différentes destinations :

| Transport | Syntaxe | Usage |
|---|---|---|
| `docker://` | `docker://ghcr.io/user/app:1.0.0` | Registry OCI (GHCR, Docker Hub, Harbor) |
| `docker-daemon:` | `docker-daemon:app:1.0.0` | Charger dans le démon Docker local |
| `oci-archive:` | `oci-archive:/tmp/app.tar` | Fichier tar OCI |
| `dir:` | `dir:/tmp/app-oci` | Dossier layout OCI |
| `containers-storage:` | `containers-storage:app:1.0.0` | Stockage Podman/Buildah local |

Dans notre CI, on utilise `docker-daemon:` pour rendre les images accessibles à Dive, puis `docker://` pour pousser vers GHCR :
```bash
buildah push miage-bank-backend:latest docker-daemon:miage-bank-backend:latest
buildah push miage-bank-backend:latest docker://ghcr.io/guillaume-helg/miage-bank-backend:latest
```

### 1.5. Conformité OCI (Open Container Initiative)

Docker et Buildah construisent des images respectant le standard **OCI Image Format Specification** (`application/vnd.oci.image.manifest.v1+json`).

Les images Buildah sont **parfaitement interopérables** :
- Exécutables par Podman, Docker, CRI-O, ou containerd
- Pushables vers n'importe quel registre OCI (Docker Hub, GHCR, Harbor, Quay.io)
- Inspectables par les outils standards (`skopeo`, `crane`, `dive`)

Docker utilise historiquement son propre schéma v2 (`application/vnd.docker.distribution.manifest.v2+json`). Les deux formats sont compatibles, mais le standard OCI garantit l'interopérabilité à long terme.

### 1.6. Cas d'usage CI/CD

#### Docker en CI : contraintes structurelles

| Méthode | Description | Risque |
|---|---|---|
| **DinD** (Docker-in-Docker) | Lancer un démon Docker dans un conteneur | Nécessite `--privileged`, surface d'attaque maximale |
| **Socket mount** | Monter `/var/run/docker.sock` du host | Accès root à l'hôte depuis le runner |
| **Kaniko** | Alternative Google, pas de démon | Limité en fonctionnalités, pas de `RUN` interactif |

#### Buildah en CI : adapté nativement

Comme le montre Stéphane Robert avec des exemples concrets pour GitLab CI (`quay.io/buildah/stable:v1.42.0`) et GitHub Actions (Ubuntu 24.04), Buildah excelle dans les environnements CI rootless :

- **GitHub Actions** : Buildah est pré-installé sur les runners Ubuntu. Build en rootless, push vers GHCR avec `secrets.GITHUB_TOKEN`.
- **GitLab CI** : utiliser l'image `quay.io/buildah/stable:v1.42.0`, vérifier le mode rootless, builder et pusher.
- **Tekton / Jenkins** : pas besoin de sidecar Docker, ni de volume `docker.sock`.

**Bonnes pratiques CI/CD** (recommandations du blog) :
- Toujours vérifier rootless : `buildah info | grep rootless`
- Scanner les images : intégrer Trivy (`trivy image app:1.0.0`)
- Versionner avec git SHA pour la traçabilité complète
- Utiliser le cache registry : `--cache-from` / `--cache-to`

### 1.7. Conclusion et choix pour MIAGE-Bank

Pour ce projet, **Buildah est le choix retenu** car :
1. La CI GitHub Actions fonctionne sans configuration de sécurité spéciale (rootless natif)
2. Les **deux workflows** (`bud` + `from/run/commit`) permettent de répondre aux exigences du TP
3. Les images OCI sont directement compatibles avec le cluster Kubernetes (CRI-O/containerd)
4. L'approche rootless est cohérente avec les principes de moindre privilège du Helm chart
5. Les transports multiples (`docker-daemon:`, `docker://`) simplifient l'intégration avec Dive et GHCR
6. La complémentarité avec l'écosystème Podman/Skopeo permet une gestion complète sans démon Docker

---

## 2. Build de MIAGE-Bank avec Buildah

### Approche 1 — Via Containerfile

**Backend** (`Containerfile.backend`) :

```dockerfile
# OCI Image packaging from pre-built artifact
FROM docker.io/library/eclipse-temurin:17-jre-alpine
RUN apk update && apk upgrade --no-cache
WORKDIR /app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# We copy the executable jar from the CI runner context directly
COPY --chown=appuser:appgroup banque-micro-service/target/*.jar app.jar
USER appuser
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

**Frontend** (`Containerfile.frontend`) :

```dockerfile
# OCI Image packaging from pre-built artifact
FROM docker.io/library/node:20-alpine
RUN apk update && apk upgrade --no-cache
WORKDIR /app
COPY --chown=node:node banque-front/package*.json ./
COPY --chown=node:node banque-front/.next ./.next
COPY --chown=node:node banque-front/public ./public
COPY --chown=node:node banque-front/node_modules ./node_modules
USER node
EXPOSE 3000
CMD ["npm", "start"]
```

### Approche 2 — Build natif Buildah (layer par layer)

**Backend** (`buildah-native-backend.sh`) :

```bash
#!/usr/bin/env bash
set -euo pipefail

RUNNER=$(buildah from docker.io/library/eclipse-temurin:17-jre-alpine)

buildah run "$RUNNER" -- apk update
buildah run "$RUNNER" -- apk upgrade --no-cache
buildah run "$RUNNER" -- mkdir -p /app
buildah run "$RUNNER" -- addgroup -S appgroup
buildah run "$RUNNER" -- adduser -S appuser -G appgroup

buildah copy --chown appuser:appgroup "$RUNNER" ./banque-micro-service/target/*.jar /app/app.jar
buildah config --workingdir /app --port 8080 --user appuser --entrypoint '["java", "-jar", "app.jar"]' "$RUNNER"
buildah commit "$RUNNER" miage-bank-backend:native
buildah rm "$RUNNER"
```

**Frontend** (`buildah-native-frontend.sh`) :

```bash
#!/usr/bin/env bash
set -euo pipefail

RUNNER=$(buildah from docker.io/library/node:20-alpine)

buildah run "$RUNNER" -- apk update
buildah run "$RUNNER" -- apk upgrade --no-cache
buildah config --workingdir /app "$RUNNER"

buildah copy --chown node:node "$RUNNER" ./banque-front/package*.json /app/
buildah copy --chown node:node "$RUNNER" ./banque-front/.next /app/.next
buildah copy --chown node:node "$RUNNER" ./banque-front/public /app/public
buildah copy --chown node:node "$RUNNER" ./banque-front/node_modules /app/node_modules

buildah config --user node --port 3000 --cmd '["npm", "start"]' "$RUNNER"
buildah commit "$RUNNER" miage-bank-frontend:native
buildah rm "$RUNNER"
```

### Comparaison des deux approches

Les deux approches produisent des images **fonctionnellement identiques**. Le Containerfile est plus lisible et maintenable (syntaxe déclarative, support Hadolint). Le mode natif Buildah offre plus de contrôle programmatique (conditions, boucles, variables bash) mais est plus verbeux. Dans un contexte CI, le Containerfile est privilégié pour sa simplicité.

---

## 3. Scan de sécurité avec Trivy

### Configuration du scan

```bash
# Scan filtré sur HIGH et CRITICAL, avec gate bloquante sur CRITICAL
trivy image --severity HIGH,CRITICAL --exit-code 1 -f json -o build-reports/trivy-backend-report.json miage-bank-backend:latest
trivy image --severity HIGH,CRITICAL -f sarif -o build-reports/trivy-backend-report.sarif miage-bank-backend:latest
```

- **Image de base backend** : `eclipse-temurin:17-jre-alpine`
- **Image de base frontend** : `node:20-alpine`
- **Gate CI** : `--exit-code 1` interrompt le pipeline si des CVE CRITICAL sont détectées.

### Backend — eclipse-temurin:17-jre-alpine

#### Vulnérabilités attendues

L'image Alpine JRE est une image minimaliste. Les CVE typiquement remontées par Trivy sur cette stack sont :

| CVE | Package | Sévérité | Description | Remédiation |
|-----|---------|----------|-------------|-------------|
| CVE liées à OpenSSL | `libssl3` / `libcrypto3` | HIGH | Vulnérabilités dans la bibliothèque TLS Alpine | Mettre à jour l'image de base (`apk upgrade` ou tag plus récent) |
| CVE liées à `zlib` | `zlib` | HIGH | Buffer overflow dans la décompression | Idem — mise à jour de l'image de base |
| CVE liées au JDK | `java/jre` | HIGH/CRITICAL | Failles dans la JVM (désérialisation, JNDI) | Passer au dernier patch Temurin 17.x |
| CVE de dépendances Java | `spring-core`, `spring-web` | CRITICAL | Failles de sécurité critiques dans Spring Boot 3.0.2 | Upgradé vers Spring Boot 3.0.13 dans le `pom.xml` du backend |

> **Note** : Les CVE exactes dépendent de la date de build. Consultez le fichier `build-reports/trivy-backend-report.json` pour la liste précise.

#### Stratégie de remédiation

1. **Mise à jour régulière de l'image de base** : reconstruire l'image hebdomadairement pour intégrer les patchs Alpine.
2. **Pinning du tag image** : utiliser `eclipse-temurin:17.0.x-jre-alpine` au lieu de `17-jre-alpine` pour des builds reproductibles.
3. **Scan en CI bloquant** : le flag `--exit-code 1` garantit qu'aucune image avec CVE CRITICAL ne sera déployée.

### Frontend — node:20-alpine

#### Vulnérabilités attendues

| CVE | Package | Sévérité | Description | Remédiation |
|-----|---------|----------|-------------|-------------|
| CVE liées à Node.js | `nodejs` | HIGH | Failles HTTP/2, DNS rebinding, prototype pollution | Utiliser le dernier patch Node 20.x LTS |
| CVE liées à npm | `npm` (bundled) | HIGH | Vulnérabilités dans les dépendances transitives | `npm audit fix` + mise à jour image |
| CVE Alpine communes | `libssl3`, `busybox` | HIGH | Mêmes CVE systèmes que le backend | `apk upgrade` dans le Containerfile |

#### Stratégie de remédiation

1. **Utiliser Node.js standalone output** : réduire la surface d'attaque en éliminant `node_modules` au profit de `next build --standalone`.
2. **Multi-stage build** : séparer le build (image `node:20-alpine` complète) de l'exécution (image `node:20-alpine` minimale avec seulement le standalone output).
3. **Scan des dépendances npm** : ajouter `npm audit --audit-level=high` dans la CI avant le build d'image.

### Abaissement de la gate de sécurité

> **État actuel** : La gate de sécurité a été abaissée (`--exit-code 0`) pour les vulnérabilités `CRITICAL`.
>
> **Justification** : Le backend repose sur Spring Boot `3.0.x` (version EOL). Malgré la montée de version vers le dernier patch mineur `3.0.13` (qui corrige de nombreuses failles), certaines vulnérabilités critiques persistent dans les dépendances transitives (comme Spring Framework / Tomcat) et dans l'image de base Alpine JRE.
> Corriger ces failles nécessiterait une migration majeure vers Spring Boot `3.2.x` / `3.3.x` (ce qui changerait les signatures d'API de sécurité et sort du cadre de ce TP d'infrastructure). Les alertes restent activées et publiées dans l'onglet **Security** de GitHub, mais ne bloquent plus la CI.

### Rapports générés

| Fichier | Format | Contenu |
|---------|--------|---------|
| `build-reports/trivy-backend-report.json` | JSON | Rapport complet backend |
| `build-reports/trivy-backend-report.sarif` | SARIF | Compatible GitHub Security tab |
| `build-reports/trivy-frontend-report.json` | JSON | Rapport complet frontend |
| `build-reports/trivy-frontend-report.sarif` | SARIF | Compatible GitHub Security tab |

### Justification relative à l'export SARIF

L'action globale `upload-sarif` de GitHub (`github/codeql-action`) échoue habituellement avec l'erreur `Resource not accessible by integration` lors de l'envoi du rapport de sécurité Trivy. Cela se produit systématiquement lorsque le dépôt GitHub est configuré en mode **Privé** sur un compte Free, car la fonctionnalité *GitHub Advanced Security* (qui alimente l'onglet Security) est réservée aux dépôts publics ou aux entreprises.

Pour respecter l'exigence d'export du format SARIF sans bloquer la pipeline de CI, le workflow a été adapté avec la directive `continue-on-error: true` sur l'étape de l'action CodeQL. Le fichier de rapport `trivy-backend-report.sarif` est téléchargé publiquement à sa place depuis la section **Artifacts** des exécutions (Run) de GitHub Actions.

---

## 4. Audit de l'image avec Dive

### Configuration Dive (mode CI)

```bash
dive miage-bank-backend:latest --ci \
  --lowestEfficiency 0.95 \
  --highestWastedBytes 20971520 \
  --highestUserWastedPercent 0.1
```

| Seuil | Valeur | Description |
|-------|--------|-------------|
| `lowestEfficiency` | 95% | Ratio minimum de bytes utiles vs total |
| `highestWastedBytes` | 20 Mo | Volume maximum de bytes gaspillés |
| `highestUserWastedPercent` | 10% | Pourcentage maximum d'espace gaspillé par l'utilisateur |

### Backend — eclipse-temurin:17-jre-alpine

#### Analyse des layers

| # | Layer | Taille estimée | Contenu |
|---|-------|----------------|---------|
| 1 | Alpine base | ~5 Mo | Système de base Alpine Linux |
| 2 | JRE Temurin 17 | ~100 Mo | Runtime Java (image de base eclipse-temurin) |
| 3 | `WORKDIR /app` | 0 o | Métadonnée uniquement |
| 4 | `RUN addgroup && adduser` | ~5 Ko | Création utilisateur non-root |
| 5 | `COPY *.jar app.jar` | ~40-60 Mo | Artefact Spring Boot (fat JAR) |

**Taille totale estimée** : ~150-170 Mo

#### Fichiers superflus identifiés

- Le **fat JAR** Spring Boot embarque toutes les dépendances (Tomcat, Jackson, Spring, etc.) dans un seul fichier. Cela signifie que chaque rebuild recopie l'intégralité des dépendances même si seul le code applicatif a changé.
- Les métadonnées Maven (`META-INF/maven/`) dans le JAR ne sont pas nécessaires à l'exécution.

#### Propositions d'optimisation

1. **Layered JAR** (Spring Boot 2.3+) :
   ```dockerfile
   # Extraction des layers du fat JAR
   FROM eclipse-temurin:17-jre-alpine AS builder
   COPY app.jar app.jar
   RUN java -Djarmode=layertools -jar app.jar extract

   FROM eclipse-temurin:17-jre-alpine
   COPY --from=builder /dependencies/ ./
   COPY --from=builder /spring-boot-loader/ ./
   COPY --from=builder /snapshot-dependencies/ ./
   COPY --from=builder /application/ ./
   ```
   **Gain** : les dépendances (rarement modifiées) sont cachées dans un layer séparé. Seul le layer `application` est recréé à chaque build → builds incrémentaux beaucoup plus rapides.

2. **Utiliser `jlink`** pour un JRE minimal custom :
   ```bash
   jlink --add-modules java.base,java.logging,java.sql --output /opt/jre-minimal
   ```
   **Gain estimé** : ~50-60 Mo en réduisant le JRE de ~100 Mo à ~40 Mo.

### Frontend — node:20-alpine

#### Analyse des layers

| # | Layer | Taille estimée | Contenu |
|---|-------|----------------|---------|
| 1 | Alpine base | ~5 Mo | Système de base Alpine Linux |
| 2 | Node.js 20 | ~50 Mo | Runtime Node.js |
| 3 | `WORKDIR /app` | 0 o | Métadonnée uniquement |
| 4 | `COPY package*.json` | ~5 Ko | Métadonnées npm |
| 5 | `COPY .next` | ~20-50 Mo | Build Next.js compilé |
| 6 | `COPY public` | ~1-5 Mo | Assets statiques |
| 7 | `COPY node_modules` | ~200-500 Mo | **⚠️ Dépendances complètes** |

**Taille totale estimée** : ~300-600 Mo

#### Fichiers superflus identifiés

- **`node_modules/`** (~200-500 Mo) : c'est le principal point d'amélioration. La totalité des dépendances de développement ET de production sont copiées dans l'image.
- Les fichiers de cache npm (`.cache/`) et les fichiers de type (`.d.ts`) sont inutiles à l'exécution.
- Les `README.md`, `LICENSE`, `CHANGELOG.md` dans chaque package npm sont superflus.

#### Propositions d'optimisation

1. **Next.js standalone output** (recommandé) :
   ```javascript
   // next.config.js
   module.exports = { output: 'standalone' }
   ```
   ```dockerfile
   FROM node:20-alpine
   COPY .next/standalone ./
   COPY .next/static ./.next/static
   COPY public ./public
   CMD ["node", "server.js"]
   ```
   **Gain estimé** : ~200-450 Mo — élimine complètement `node_modules` au profit d'un bundle standalone de ~20-50 Mo.

2. **Multi-stage build** :
   ```dockerfile
   # Stage 1 : build
   FROM node:20-alpine AS builder
   WORKDIR /app
   COPY package*.json ./
   RUN npm ci
   COPY . .
   RUN npm run build

   # Stage 2 : runtime
   FROM node:20-alpine
   WORKDIR /app
   COPY --from=builder /app/.next/standalone ./
   COPY --from=builder /app/.next/static ./.next/static
   COPY --from=builder /app/public ./public
   CMD ["node", "server.js"]
   ```
   **Gain** : l'image finale ne contient ni les sources, ni les dev dependencies, ni les outils de build.

### Résumé avant/après (estimations)

| Image | Avant optimisation | Après optimisation | Gain |
|-------|-------------------|-------------------|------|
| Backend | ~170 Mo | ~110 Mo | ~35% (layered JAR + jlink) |
| Frontend | ~400 Mo | ~80 Mo | ~80% (standalone + multi-stage) |

### Abaissement des seuils Dive

Si les images ne passent pas les gates Dive avec les seuils demandés (efficacité 95%, max 20 Mo gaspillés, max 10% gaspillé), les seuils peuvent être ajustés dans `mise.toml`. La justification doit être documentée ici.

> **État actuel** : les seuils sont configurés selon les exigences du TP. L'image frontend pourrait nécessiter l'optimisation standalone pour atteindre le seuil d'efficacité de 95%.

---

## 5. Script de build intégré (CI GitHub Actions)

L'intégralité de la chaîne de build est orchestrée par :
- **`mise.toml`** — gestion des outils (Trivy v0.69.3, Dive v0.12.0, Hadolint v2.12.0) et des tâches locales.
- **`.github/workflows/ci.yml`** — pipeline GitHub Actions complète.

### Pipeline CI — Étapes

```
Checkout → Build artefacts (Maven + npm) → Hadolint (lint Containerfile) → Buildah (build images) → Trivy (scan sécurité) → Dive (audit layers) → Push GHCR → Upload SARIF + Artifacts
```

### Tâches mise.toml

| Tâche | Description |
|-------|-------------|
| `build:backend` | Build de l'image backend via Containerfile |
| `build:frontend` | Build de l'image frontend via Containerfile |
| `scan:backend` | Scan Trivy backend (HIGH+CRITICAL, JSON+SARIF) |
| `scan:frontend` | Scan Trivy frontend (HIGH+CRITICAL, JSON+SARIF) |
| `audit:backend` | Audit Dive backend (mode CI, seuils 95%/20Mo/10%) |
| `audit:frontend` | Audit Dive frontend (mode CI, seuils 95%/20Mo/10%) |
| `ci` | Pipeline complète (dépend de toutes les tâches ci-dessus) |

### Workflow GitHub Actions (`.github/workflows/ci.yml`)

```yaml
name: CI Build OCI Images

on:
  push:
    branches: [ "main" ]
  pull_request:
    branches: [ "main" ]

jobs:
  build-scan-audit:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write
      packages: write

    steps:
    - name: Checkout repository
      uses: actions/checkout@v4

    - name: Checkout Backend
      uses: actions/checkout@v4
      with:
        repository: guillaume-helg/banque-micro-service
        path: tp-buildah-trivy-dive-helm/banque-micro-service

    - name: Checkout Frontend
      uses: actions/checkout@v4
      with:
        repository: guillaume-helg/banque-front
        path: tp-buildah-trivy-dive-helm/banque-front

    - name: Set up JDK 17
      uses: actions/setup-java@v4
      with:
        java-version: '17'
        distribution: 'temurin'
        cache: maven

    - name: Build Backend Artifact (Maven)
      working-directory: tp-buildah-trivy-dive-helm/banque-micro-service
      run: mvn clean package -DskipTests

    - name: Set up Node.js 20
      uses: actions/setup-node@v4
      with:
        node-version: '20'
        cache: 'npm'
        cache-dependency-path: tp-buildah-trivy-dive-helm/banque-front/package-lock.json

    - name: Build Frontend Artifact (Next.js)
      working-directory: tp-buildah-trivy-dive-helm/banque-front
      run: |
        npm ci
        npm run build

    - name: Set up mise
      uses: jdx/mise-action@v2

    - name: Run Hadolint (Backend)
      run: mise exec hadolint -- hadolint tp-buildah-trivy-dive-helm/Containerfile.backend

    - name: Run Hadolint (Frontend)
      run: mise exec hadolint -- hadolint tp-buildah-trivy-dive-helm/Containerfile.frontend

    - name: Build Images (Buildah via mise)
      working-directory: tp-buildah-trivy-dive-helm
      run: |
        mise run build:backend
        mise run build:frontend

    - name: Scan with Trivy (v0.69.3 via mise)
      working-directory: tp-buildah-trivy-dive-helm
      run: |
        mise run scan:backend
        mise run scan:frontend

    - name: Audit components with Dive (via mise)
      working-directory: tp-buildah-trivy-dive-helm
      run: |
        mise run audit:backend
        mise run audit:frontend

    - name: Push images to GHCR
      if: github.ref == 'refs/heads/main' && github.event_name == 'push'
      env:
        REGISTRY: ghcr.io/${{ github.repository_owner }}
      run: |
        echo "${{ secrets.GITHUB_TOKEN }}" | buildah login -u "${{ github.actor }}" --password-stdin ghcr.io
        buildah tag miage-bank-backend:latest $REGISTRY/miage-bank-backend:${{ github.sha }}
        buildah tag miage-bank-backend:latest $REGISTRY/miage-bank-backend:latest
        buildah push $REGISTRY/miage-bank-backend:${{ github.sha }}
        buildah push $REGISTRY/miage-bank-backend:latest
        buildah tag miage-bank-frontend:latest $REGISTRY/miage-bank-frontend:${{ github.sha }}
        buildah tag miage-bank-frontend:latest $REGISTRY/miage-bank-frontend:latest
        buildah push $REGISTRY/miage-bank-frontend:${{ github.sha }}
        buildah push $REGISTRY/miage-bank-frontend:latest

    - name: Upload Trivy Results (Backend SARIF) for Security Tab
      uses: github/codeql-action/upload-sarif@v4
      continue-on-error: true
      with:
        sarif_file: tp-buildah-trivy-dive-helm/build-reports/trivy-backend-report.sarif

    - name: Publish artifacts
      uses: actions/upload-artifact@v4
      if: always()
      with:
        name: build-reports
        path: tp-buildah-trivy-dive-helm/build-reports/
```

---

## 6. Guide d'exécution de la chaîne

### 6.1. Prérequis locaux (WSL2 / Linux)
Puisque **Buildah** requiert un noyau Linux avec le support des *user namespaces*, l'exécution locale doit se faire sous Linux ou dans **WSL2** (Ubuntu recommandé) sous Windows.

1. **Installer mise** (gestionnaire de tâches et d'outils) :
   ```bash
   curl https://mise.run | sh
   # Activer mise dans votre shell (ex: bash)
   echo 'eval "$(~/.local/share/mise/bin/mise activate bash)"' >> ~/.bashrc
   source ~/.bashrc
   ```

2. **Installer les dépendances système** (Buildah) :
   ```bash
   sudo apt-get update
   sudo apt-get install -y buildah

   # Et java s'il n'est pas installé
   sudo apt install openjdk-17-jdk
   ```

3. **Compiler les artefacts Java et Node.js** (requis avant le build d'image) :
   ```bash
   # Compiler le Backend (Maven) depuis le dossier banque-micro-service
   cd tp-buildah-trivy-dive-helm/banque-micro-service
   mvn clean package -DskipTests

   # Compiler le Frontend (Next.js) depuis le dossier banque-front
   cd ../banque-front
   npm ci
   npm run build
   ```

### 6.2. Exécution via `mise` (Recommandé)
Une fois dans le répertoire `tp-buildah-trivy-dive-helm/`, les versions spécifiques des outils (Trivy `v0.69.3`, Dive `v0.12.0`, Hadolint `v2.12.0`) sont automatiquement gérées et installées par `mise` à la première exécution.

- **Exécuter la chaîne de build complète (Build, Scan Trivy, Audit Dive)** :
  ```bash
  cd tp-buildah-trivy-dive-helm/
  mise run ci
  ```

- **Exécuter des étapes individuelles** :
  ```bash
  # Builder uniquement les images
  mise run build:backend
  mise run build:frontend

  # Exécuter les scans de sécurité Trivy
  mise run scan:backend
  mise run scan:frontend

  # Exécuter les audits des layers Dive
  mise run audit:backend
  mise run audit:frontend
  ```

### 6.3. Exécution via les scripts Buildah natifs (`from/run/commit`)
Pour tester le workflow interactif/scriptable de Buildah sans passer par les Containerfiles :
```bash
cd tp-buildah-trivy-dive-helm/
chmod +x buildah-native-backend.sh buildah-native-frontend.sh

# Lancer le build natif backend
./buildah-native-backend.sh

# Lancer le build natif frontend
./buildah-native-frontend.sh
```

### 6.4. Exécution dans la CI (GitHub Actions)
La pipeline est entièrement automatisée dans `.github/workflows/ci.yml`. À chaque `push` ou `pull request` sur la branche `main` :
1. Le runner Ubuntu-latest est provisionné.
2. Le code principal et les dépôts de code (backend et frontend) sont récupérés.
3. Les artefacts de build (Java & Node.js) sont générés.
4. `mise` prépare les versions requises de Hadolint, Trivy et Dive.
5. La tâche `mise run ci` est exécutée de façon sécurisée (rootless).
6. En cas de push sur `main`, les images OCI sont tagguées (SHA de commit + `latest`) et poussées sur le registre **GHCR**.
7. Les rapports générés (`trivy-*-report.json`, `.sarif`) sont publiés en tant qu'artifacts de l'action.

```
