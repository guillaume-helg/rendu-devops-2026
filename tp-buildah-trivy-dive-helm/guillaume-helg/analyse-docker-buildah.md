# Analyse Comparative : Docker vs Buildah

## 1. Architecture (Daemon vs Daemonless)
- **Docker** repose sur une architecture client-serveur. Le client Docker communique avec un démon (`dockerd`). Ce démon doit tourner en permanence en arrière-plan avec les droits `root`.
- **Buildah** adopte une architecture dite "daemonless" (sans démon). Il n'y a pas besoin d'un processus central pour gérer les containers ou les images, ce qui le rend léger. Son exécution peut se faire en espace utilisateur ("user namespace").

## 2. Sécurité et Surface d'Attaque
- Dans le cas de **Docker**, l'accès au socket Unix (`/var/run/docker.sock`) confère à l'utilisateur des privilèges équivalents à `root`. Cela ouvre le vecteur à l'escalade de privilèges.
- **Buildah** fonctionne nativement en mode "rootless". Chaque utilisateur gère ses propres images sans privilèges super-utilisateur. La surface d'attaque est grandement réduite puisqu'aucune compromission ne donne accès aux privilèges de la machine hôte.

## 3. Conformité OCI (Open Container Initiative)
- **Docker** et **Buildah** construisent tous deux des images respectant le standard OCI.
- Les images Buildah sont donc parfaitement interopérables : elles peuvent être manipulées ou par `Podman`, `Docker`, ou exécutées dans n'importe quel orchestrateur de clusters (comme Kubernetes via `CRI-O` ou `containerd`).

## 4. Cas d'usage CI/CD
- Intégrer **Docker** dans une CI (ex: runners GitHub Commands) est complexe et peu sécurisé : l'utilisation du mode "Docker-in-Docker" (`dind`) nécessitant un container "privilégié" présente des risques structurels.
- **Buildah** excelle dans des pipelines d'Intégration Continue. Il autorise le build d'images au sein de pods totalement non-privilégiés ou runners "rootless", en garantissant ainsi une chaîne de sécurité inentamée de bout en bout.
