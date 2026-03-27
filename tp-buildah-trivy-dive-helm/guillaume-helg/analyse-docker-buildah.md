# Analyse Comparative : Docker vs Buildah

## Vue d'ensemble

| Critère | Docker | Buildah |
|---|---|---|
| Architecture | Client-serveur (démon `dockerd`) | Daemonless, exécution directe |
| Privilèges requis | `root` (ou accès au socket Unix) | Rootless natif (user namespace) |
| Surface d'attaque | Large (démon persistant + socket) | Réduite (processus éphémère) |
| Format d'image | OCI + Docker v2 | OCI natif |
| Runtime intégré | Oui (`docker run`) | Non (build only) |
| CI/CD rootless | Complexe (DinD, socket mount) | Natif, sans configuration spéciale |

---

## 1. Architecture (Daemon vs Daemonless)

**Docker** repose sur une architecture client-serveur. Le client Docker (`docker`) communique via un socket Unix avec un démon (`dockerd`) qui tourne en permanence en arrière-plan avec les droits `root`. Ce démon centralisé gère l'ensemble du cycle de vie : build, pull, push, run. Si le démon plante, toutes les opérations sont interrompues.

**Buildah** adopte une architecture « daemonless ». Chaque commande `buildah` s'exécute comme un processus indépendant, sans processus central. Il utilise les *user namespaces* Linux et `fuse-overlayfs` pour gérer les layers en espace utilisateur. Cela signifie :
- Aucun processus persistant à maintenir
- Pas de point de défaillance unique (SPOF)
- Consommation mémoire uniquement pendant le build

---

## 2. Sécurité et Surface d'Attaque

### Docker : vecteurs d'attaque connus

L'accès au socket Unix (`/var/run/docker.sock`) confère à un utilisateur des **privilèges équivalents à `root`** sur la machine hôte. Cela ouvre plusieurs vecteurs :

- **Escalade de privilèges via socket mount** : un conteneur qui monte le socket Docker peut créer d'autres conteneurs avec `--privileged` et accéder au filesystem hôte.
- **CVE-2019-5736** (runc) : permettait à un conteneur malveillant d'écraser le binaire `runc` de l'hôte et d'obtenir un shell root.
- **Container escape** : le mode `--privileged` désactive toutes les protections de sécurité (capabilities, seccomp, AppArmor).

### Buildah : architecture rootless

Buildah fonctionne nativement en mode « rootless » :
- Chaque utilisateur gère ses propres images dans `~/.local/share/containers/`
- Les opérations utilisent les *user namespaces* (`--userns=auto`) pour isoler les UID/GID
- Aucune capability Linux élevée n'est requise (`--cap-add` non nécessaire)
- La compromission d'un build ne donne accès qu'aux fichiers de l'utilisateur courant, jamais aux privilèges de la machine hôte

---

## 3. Conformité OCI (Open Container Initiative)

Docker et Buildah construisent tous deux des images respectant le standard **OCI Image Format Specification** (`application/vnd.oci.image.manifest.v1+json`).

Les images produites par Buildah sont donc **parfaitement interopérables** :
- Exécutables par `Podman`, `Docker`, `CRI-O`, ou `containerd`
- Pushables vers n'importe quel registre OCI (Docker Hub, GHCR, Harbor, Quay.io)
- Inspectables par les outils standards (`skopeo`, `crane`, `dive`)

Docker supporte aussi le format OCI mais historiquement utilise son propre schéma v2 (`application/vnd.docker.distribution.manifest.v2+json`). Les deux formats sont largement compatibles, mais le standard OCI garantit l'interopérabilité à long terme.

---

## 4. Cas d'usage CI/CD

### Docker en CI : contraintes structurelles

Intégrer Docker dans une pipeline CI/CD présente des difficultés fondamentales :

| Méthode | Description | Risque |
|---|---|---|
| **DinD** (Docker-in-Docker) | Lancer un démon Docker dans un conteneur | Nécessite `--privileged`, surface d'attaque maximale |
| **Socket mount** | Monter `/var/run/docker.sock` du host | Accès root à l'hôte depuis le runner |
| **Kaniko** | Alternative Google, pas de démon | Limité en fonctionnalités, pas de `RUN` interactif |

### Buildah en CI : adapté nativement

Buildah excelle dans les environnements CI « rootless » :
- **GitHub Actions** : fonctionne directement sur les runners Ubuntu sans configuration
- **GitLab CI** : s'exécute dans des pods Kubernetes non-privilégiés
- **Tekton / Jenkins** : pas besoin de sidecar Docker, ni de volume `docker.sock`

Cela garantit une **chaîne de confiance inentamée** du code source à l'image OCI, sans jamais élever les privilèges.

---

## 5. Conclusion et choix pour MIAGE-Bank

Pour ce projet, **Buildah est le choix retenu** car :
1. La CI GitHub Actions fonctionne sans configuration de sécurité spéciale
2. Les images OCI produites sont directement compatibles avec le cluster Kubernetes (CRI-O/containerd)
3. L'approche rootless est cohérente avec les principes de moindre privilège appliqués dans le Helm chart (ServiceAccount dédié, NetworkPolicy restrictive)
4. La complémentarité avec l'écosystème Podman/Skopeo permet une gestion complète sans démon Docker
