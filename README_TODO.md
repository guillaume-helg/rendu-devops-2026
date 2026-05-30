# Roadmap & Améliorations Futures (TODO)

Ce document répertorie les idées d'amélioration et les outils DevSecOps modernes qui n'ont pas pu être implémentés par manque de temps, mais qui renforceraient la robustesse, la sécurité et la portabilité de la chaîne CI/CD et du déploiement Kubernetes.

---

## 1. Pipeline CI/CD et Portabilité

### 🚀 Dagger — Pipeline as Code & Exécution Locale
* **Objectif** : Écrire et exécuter la pipeline CI/CD en utilisant un vrai langage de programmation (Go, Python ou TypeScript) à la place du YAML complexe de GitHub Actions.
* **Intérêt** : 
  - **Identité locale / CI** : Le moteur Dagger tourne dans des conteneurs, ce qui permet de lancer la pipeline *exactement* de la même façon sur son PC local (`dagger run go run main.go`) et dans GitHub Actions. Fini le cycle fastidieux de push/test sur GitHub pour déboguer la CI.
  - **Cachage intelligent** : Dagger gère le cache au niveau des instructions de build de manière extrêmement efficace.

### 🔍 Plumber & Actionlint — Validation et Conformité de la CI
* **Objectif** : Analyser les fichiers YAML de la CI/CD pour s'assurer du respect des bonnes pratiques et de la conformité de sécurité.
* **Intérêt** :
  - **Actionlint** : Détecte les fautes de syntaxe, les injections d'expressions, les mauvaises pratiques de sécurité (ex. utilisation de `secrets` mal sécurisés) dans les workflows GitHub Actions.
  - **Conftest (OPA / Rego)** : Écrire des règles de conformité (ex. "chaque step doit spécifier une version fixe de l'action, pas de tag `master`/`main` mouvant") et vérifier le workflow CI/CD avec un parser comme Plumber.

---

## 2. Sécurité de la Chaîne d'Approvisionnement (Software Supply Chain)

### ✍️ Cosign (Sigstore) — Signature des Images OCI
* **Objectif** : Signer cryptographiquement les images construites avec Buildah pour en garantir l'origine et l'intégrité.
* **Intérêt** :
  - Dans la CI, générer une paire de clés éphémère (via OIDC de GitHub) et signer l'image dans GHCR.
  - Empêcher l'exécution d'images altérées ou malveillantes sur le cluster.

### 🛡️ Kyverno / OPA Gatekeeper — Contrôle d'Admission des Signatures
* **Objectif** : Bloquer le déploiement sur Kubernetes de toute image non signée.
* **Intérêt** :
  - Kyverno intercepte chaque demande de création de Pod, vérifie la signature de l'image auprès de GHCR via Cosign, et rejette le Pod si la signature est invalide ou absente.

### 🔑 Gitleaks — Prévention des Fuites de Secrets
* **Objectif** : Scanner l'historique Git à chaque commit pour bloquer tout push contenant des secrets en clair (tokens Vault, mots de passe, clés SSH).
* **Intérêt** :
  - Éviter d'exposer accidentellement le token Kubernetes ou le mot de passe de base de données de production sur un dépôt public.

---

## 3. Qualité et Sécurité Kubernetes / Helm

### 🧪 Kube-linter & Datree — Validation des manifests Helm
* **Objectif** : Détecter les erreurs de configuration Kubernetes et de sécurité dans le chart Helm avant le déploiement.
* **Intérêt** :
  - Vérifie la conformité par rapport aux standards (ex. manque de limites CPU/Memory, conteneurs tournant en root, absence de probes).

### ⏳ Argo Rollouts — Déploiement Progressif (Canary / Blue-Green)
* **Objectif** : Remplacer le déploiement Kubernetes standard (RollingUpdate) par des stratégies de déploiement avancées.
* **Intérêt** :
  - Lancer les nouvelles versions de MIAGE-Bank sur 10% des utilisateurs, analyser les métriques (Prometheus/Jaeger), et faire un rollback automatique si le taux d'erreur augmente.

### 🔒 Re-chiffrement des secrets Git (Mozilla SOPS)
* **Objectif** : Chiffrer les secrets directement dans Git si l'on ne souhaite pas utiliser Vault.
* **Intérêt** :
  - Permet de stocker les secrets de manière chiffrée (via PGP ou KMS Cloud) dans Git et de laisser ArgoCD les déchiffrer à la volée sur le cluster lors de l'application.
