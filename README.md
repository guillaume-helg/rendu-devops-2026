HELG Guillaume & PATAPY Jeremy - MIAGE 2026

# 🏦 MIAGE Bank — Projet DevSecOps

Ce dépôt contient les livrables du TP **Buildah, Trivy, Dive & Helm/Kubernetes** pour l'application **MIAGE-Bank**.

---

## 🧭 Navigation & Livrables

Pour faciliter la correction et l'exploration du projet, les réponses détaillées et guides d'exécution ont été séparés par thématiques :

| Section | Fichier & Lien | Description |
| :--- | :--- | :--- |
| **Sujet du TP** | [README_SUBJECT.md](./README_SUBJECT.md) | Énoncé et exigences initiales du projet |
| **Partie A** | [README_ANSWER_PART_A.md](./README_ANSWER_PART_A.md) | Analyse comparative Docker/Buildah, configuration de build, scans Trivy et rapports de layers Dive |
| **Partie B** | [README_ANSWER_PART_B.md](./README_ANSWER_PART_B.md) | Conception du Chart Helm, déploiement Kubernetes, politiques réseau, gestion des secrets (Vault/ESO) et GitOps ArgoCD |
| **Roadmap** | [README_TODO.md](./README_TODO.md) | Pistes d'améliorations futures (Dagger, Cosign, Kyverno, etc.) |

---

## 🏗️ Structure Simplifiée du Projet

```text
rendus-miage-2026/
├── .github/workflows/ci.yml    # Pipeline CI/CD GitHub Actions ( Hadolint -> Buildah -> Trivy -> Dive -> GHCR )
├── README_ANSWER_PART_A.md     # Réponses & livrables de la Partie A
├── README_ANSWER_PART_B.md     # Réponses & livrables de la Partie B
├── README_TODO.md              # Idées et perspectives DevSecOps futures
├── README_SUBJECT.md           # Énoncé original
└── tp-buildah-trivy-dive-helm/ # Répertoire de travail
    ├── Containerfile.backend   # Image OCI du Monolithe Backend
    ├── Containerfile.frontend  # Image OCI du Frontend Next.js
    ├── mise.toml               # Tâches orchestrées locales (Hadolint, Trivy, Dive, Helm)
    ├── argocd/                 # Manifestes déclaratifs ArgoCD
    ├── miage-bank/             # Chart Helm principal (Backend & Infrastructure)
    ├── frontend/               # Chart Helm Frontend Next.js
    └── database/               # Chart Helm Database MySQL (StatefulSet)
```

---

## 🚀 Démarrage Rapide

### 🛠️ Prérequis locaux (WSL2 / Linux)
Les outils de build (Buildah) nécessitent un noyau Linux. Nous utilisons [mise](https://mise.jdx.co/) pour installer et gérer les bonnes versions de Trivy, Dive, Hadolint et Helm de manière déterministe.

```bash
# 1. Installer mise
curl https://mise.run | sh
eval "$(~/.local/share/mise/bin/mise activate bash)"

# 2. Installer Buildah nativement sur votre distribution
sudo apt-get update && sudo apt-get install -y buildah
```

### 📦 Exécuter la Pipeline CI Localement
Depuis le dossier `tp-buildah-trivy-dive-helm/` :
```bash
cd tp-buildah-trivy-dive-helm/

# Lancer le build, le scan Trivy et l'audit Dive locaux
mise run ci
```

### ☸️ Déploiement Kubernetes (Minikube local)
Pour déployer la stack entière (Base de données, Backend monolithique, Frontend et gestion sécurisée via Vault + External Secrets) :

1. Lancer minikube et configurer les opérateurs (Vault, ESO). (Voir le guide détaillé d'installation dans [README_ANSWER_PART_B.md](./README_ANSWER_PART_B.md)).
2. Déployer l'application en mode dev via Helm :
   ```bash
   mise run helm:deploy
   ```

Pour plus de détails techniques, de commandes d'administration ou pour voir la démonstration de la dérive GitOps, veuillez consulter le [README de la Partie B](./README_ANSWER_PART_B.md).
