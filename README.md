HELG Guillaume PATAPY Jeremy
# rendus-miage-2026

# TP — Buildah, Trivy, Dive & Helm/Kubernetes — MIAGE Bank

> Sujet original : [formation.afaivre.fr/projet-miage-2026](https://formation.afaivre.fr/projet-miage-2026)

## Modalités

> **Les outils d'intelligence artificielle sont autorisés.** Toute réponse générée doit cependant être comprise, maîtrisée et adaptée au contexte MIAGE-Bank.
>
> **Les groupes sont limités à 2 personnes.**
>
> Le TP de référence est MIAGE-BANK en micro-service, vous pouvez générer un front pour illustrer l'outil.

---

## Outils requis

Les outils suivants doivent être installés et opérationnels sur votre poste avant de commencer :

| Outil | Usage dans ce TP | Documentation officielle |
|---|---|---|
| **Buildah** | Build d'images OCI sans démon Docker | [buildah.io](https://buildah.io/) |
| **Trivy** | Scan de sécurité des images | [aquasecurity.github.io/trivy](https://aquasecurity.github.io/trivy/latest/getting-started/installation/) |
| **Dive** | Audit des layers d'image | [github.com/wagoodman/dive](https://github.com/wagoodman/dive#installation) |
| **Helm** | Packaging et déploiement Kubernetes | [helm.sh/docs](https://helm.sh/docs/) |
| **kubectl** | Interaction avec le cluster Kubernetes | [kubernetes.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/) |
| **ArgoCD CLI** | GitOps — déploiement et suivi | [argo-cd.readthedocs.io](https://argo-cd.readthedocs.io/en/stable/cli_installation/) |
| **Git + GitHub** | Versioning et rendu via Pull Request | [docs.github.com](https://docs.github.com/) |
| **GitHub Actions** | Pipeline CI/CD (obligatoire pour le bonus) | [docs.github.com/actions](https://docs.github.com/en/actions) |
| **Hadolint** | Linting du Containerfile dans la CI | [github.com/hadolint/hadolint](https://github.com/hadolint/hadolint) |

---

## Rendu

> **Le rendu se fait exclusivement par Pull Request GitHub.**
>
> Dépôt cible : [github.com/alex-faivre-formation/rendus-miage-2026/tree/main/tp-buildah-trivy-dive-helm](http://github.com/alex-faivre-formation/rendus-miage-2026/tree/main/tp-buildah-trivy-dive-helm)
>
> Votre PR doit cibler la branche `main` et contenir l'intégralité de vos livrables (code, scripts, rapports, README).
>
> Le `README` doit obligatoirement mentionner en première ligne votre **nom et prénom**, afin de permettre la correction.
>
> La date de rendu est fixée à la date du **05 juin**. Tout devoir rendu après cette date ne sera pas admis.

---

## Contexte

Ce TP s'inscrit dans la continuité du cours Kubernetes. Il est divisé en deux parties, chacune donnant lieu à une évaluation distincte. L'application cible est **MIAGE-Bank**, le projet fil rouge du cours.

Ressources du cours :
- Dépôt Git : [github.com/alex-faivre-formation/miage-2026-kubernetes](http://github.com/alex-faivre-formation/miage-2026-kubernetes)
- Support de cours : [formation.afaivre.fr/miage-2026](http://formation.afaivre.fr/miage-2026)

---

# Partie A — Chaîne de build OCI avec Buildah, Trivy et Dive

## Objectifs

- Construire des images OCI utilisant Buildah
- Analyser la sécurité des images avec Trivy
- Auditer la taille et les layers avec Dive
- Scanner la conformité de votre image via Hadolint
- Intégrer ces outils dans une chaîne de build reproductible pour MIAGE-Bank

---

## 1. Analyse comparative Docker vs Buildah

Rédigez une section d'analyse (dans votre README ou dans un document dédié) expliquant les différences fondamentales entre Docker et Buildah. Votre analyse doit couvrir :

- **Architecture** : modèle démon vs daemonless, exécution en espace utilisateur
- **Sécurité** : surface d'attaque, accès au socket Unix, escalade de privilèges
- **Conformité OCI** : compatibilité avec Docker, Podman et tout runtime OCI
- **Cas d'usage CI/CD** : pertinence dans des environnements rootless (runners GitLab, pipelines Kubernetes)

> **Attendu** : Cette analyse doit figurer dans votre livrable. Elle sera évaluée sur la précision technique et la capacité à argumenter un choix technologique.

---

## 2. Build de MIAGE-Bank avec Buildah

Constituez l'image OCI de MIAGE-Bank en utilisant **exclusivement Buildah**. Deux approches doivent être documentées et comparées :

1. **Via un Containerfile** (équivalent Dockerfile) — image de base adaptée à l'application, JAR MIAGE-Bank copié, port applicatif exposé
2. **Construction layer par layer** en mode natif Buildah — même résultat, sans Containerfile

Comparez les résultats des deux approches et commentez les différences éventuelles.

---

## 3. Scan de sécurité avec Trivy

Effectuez une analyse de sécurité complète de l'image construite :

- Scan de l'image locale
- Filtrage sur les sévérités **HIGH** et **CRITICAL**
- Export du rapport au format JSON
- Export au format SARIF (compatible GitHub Security)

**Livrables attendus :**
- Rapport Trivy complet (JSON ou table)
- Liste des CVE identifiées
- Pour chaque CVE HIGH/CRITICAL : explication de la vulnérabilité et plan de remédiation s'il existe.
- **Si votre image n'arrivait pas à passer cette gate, vous pouvez baisser le niveau de sécurité attendu mais vous devez l'indiquer dans votre rendu.**

---

## 4. Audit de l'image avec Dive

Inspectez le contenu de chaque layer de l'image et identifiez les fichiers superflus.

Configurez et exécutez Dive en mode CI avec des seuils d'efficacité :
- Efficacité minimale : 95%
- Espace gaspillé maximum : 20 Mo
- Pourcentage d'espace gaspillé maximum : 10%

**Livrables attendus :**
- Capture d'écran ou export de l'analyse Dive
- Taille de chaque layer et taille totale
- Identification des fichiers ou répertoires superflus
- Proposition d'optimisation (multi-stage build si applicable, suppression de cache, etc.)
- Un avant / après est une bonne approche
- **Si votre image n'arrivait pas à passer cette gate, vous pouvez baisser le niveau de sécurité attendu mais vous devez l'indiquer dans votre rendu.**

---

## 5. Script de build intégré

Assemblez les étapes précédentes dans un script `une chaine CI sur Github Actions` reproductible qui :

- Construit l'image via Buildah
- Lance le scan Trivy et génère le rapport JSON
- Interrompt le build si des CVE **CRITICAL** sont détectées
- Lance l'analyse Dive en mode CI
- Produit les rapports dans un répertoire `build-reports/`
- Exporte les rapports depuis build-reports ou les mets à un endroit où ils peuvent être lues.
- **Si votre image n'arrivait pas à passer cette gate, vous pouvez baisser le niveau de sécurité attendu mais vous devez l'indiquer dans votre rendu.**

> **Attendu** : Le script doit être intégré au dépôt Git et s'exécuter sans erreur. La pipeline **GitHub Actions** est un bonus évalué. Elle doit inclure au minimum les étapes suivantes : lint du Containerfile avec **Hadolint**, build Buildah, scan Trivy et audit Dive.

---

## Livrables — Partie A

- [ ] Analyse comparative Docker vs Buildah (rédigée, argumentée)
- [ ] Containerfile optimisé pour MIAGE-Bank
- [ ] Script de build `Github Actions` fonctionnel
- [ ] Rapport Trivy (JSON) avec plan de remédiation
- [ ] Rapport Dive avec analyse des layers et optimisations proposées
- [ ] README documentant la démarche et comment exécuter la chaîne

---

## Critères d'évaluation — Partie A

| Critère | Pondération |
|---|---|
| Analyse comparative Docker / Buildah | 15% |
| Chaîne de build Buildah fonctionnelle | 25% |
| Rapport Trivy + plan de remédiation | 20% |
| Analyse Dive + optimisations | 15% |
| Script de build intégré et documenté | 25% |

---

# Partie B — Packaging Helm & Déploiement Kubernetes de MIAGE-Bank

## Objectifs

- Packager MIAGE-Bank sous forme d'un chart Helm
- Déployer l'application dans Kubernetes avec l'ensemble des mécanismes vus en cours
- Mettre en place une gestion sécurisée des secrets via Vault et External Secrets Operator
- Exposer l'application via un Ingress Traefik / ou **minikube tunnel**
- Configurer le GitOps via ArgoCD pour chacune des applications (attention à l'oeuf ou la poule - si pas possible expliquez).

---

## 1. Chart Helm pour MIAGE-Bank

Créez un chart Helm pour MIAGE-Bank respectant la structure suivante :

```
miage-bank/
├── Chart.yaml
├── values.yaml
├── values-prod.yaml
└── templates/
    ├── _helpers.tpl
    ├── namespace.yaml
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    ├── configmap.yaml
    ├── networkpolicy.yaml
    └── serviceaccount.yaml
```

Exigences du chart :

**Deployment**
- Image buildée en Partie A (registry Harbor si déployé, sinon image locale soit via la registry Github)
- `readinessProbe` et `livenessProbe` configurées
- `resources.requests` et `resources.limits` définis
- `serviceAccountName` dédié

**Service** — Type `ClusterIP` uniquement (exposition externe via Ingress)

**Ingress** — Classe `traefik`, hostname paramétrable via `values.yaml`, TLS optionnel (bonus)

**NetworkPolicy** — Default-deny en ingress sur le namespace, autorisation uniquement depuis le controller Traefik / minikube

**RBAC** — `ServiceAccount` dédié, `Role` et `RoleBinding` minimalistes (least privilege)

### Gestion des secrets

Les credentials de MIAGE-Bank (base de données, secrets applicatifs) **ne doivent pas figurer en clair** dans `values.yaml`. Deux approches sont acceptées :

1. **Vault + External Secrets Operator** (approche recommandée, vue en TP12/TP13)
2. **Secret Kubernetes natif** avec `stringData` créé séparément du chart et référencé par nom mais perte de points associé

Validation attendue du chart avant déploiement : `helm lint`, `helm template` et `helm install --dry-run`.

---

## 2. Déploiement dans Kubernetes

Déployez le chart dans un namespace dédié `miage-bank` et validez :
- L'application est accessible via l'Ingress
- Les NetworkPolicies sont actives
- Les secrets ne sont pas exposés en clair

---

## 3. GitOps avec ArgoCD

Versionnez votre chart dans le dépôt Git et déployez-le via une `Application` ArgoCD ciblant la branche `main` avec synchronisation automatique (`prune: true`, `selfHeal: true`).

**Exercice de dérive** : Modifiez manuellement un paramètre de l'application (ex : nombre de réplicas), observez qu'ArgoCD détecte le statut `OutOfSync`, puis observez ou déclenchez la réconciliation. **Documentez cette démonstration dans votre README.**

---

## Livrables — Partie B

- [ ] Chart Helm complet et fonctionnel dans le dépôt Git
- [ ] `values.yaml` et `values-prod.yaml` documentés
- [ ] Application ArgoCD déployée et synchronisée
- [ ] Secrets gérés via Vault + ESO ou Secret Kubernetes séparé du chart
- [ ] NetworkPolicy en place et validée
- [ ] Ingress exposant MIAGE-Bank
- [ ] README décrivant le déploiement de bout en bout
- [ ] Démonstration de la dérive ArgoCD et de la réconciliation

---

## Critères d'évaluation — Partie B

| Critère | Pondération |
|---|---|
| Chart Helm complet et conforme | 30% |
| Déploiement Kubernetes avec sécurité (RBAC, NetworkPolicy, HPA) | 25% |
| Gestion des secrets (Vault/ESO ou Secret K8s) | 20% |
| GitOps ArgoCD fonctionnel + démo dérive | 25% |

---

## Bibliographie

- **Buildah — Documentation officielle** : [https://buildah.io/](https://buildah.io/)
- **Buildah — Dépôt GitHub** : [https://github.com/containers/buildah](https://github.com/containers/buildah)
- **OCI Image Format Specification** : [https://github.com/opencontainers/image-spec](https://github.com/opencontainers/image-spec)
- **Trivy — Documentation officielle** : [https://aquasecurity.github.io/trivy/](https://aquasecurity.github.io/trivy/)
- **Dive — Dépôt GitHub** : [https://github.com/wagoodman/dive](https://github.com/wagoodman/dive)
- **Helm — Documentation officielle** : [https://helm.sh/docs/](https://helm.sh/docs/)
- **ArgoCD — Documentation officielle** : [https://argo-cd.readthedocs.io/](https://argo-cd.readthedocs.io/)
- **HashiCorp Vault — Documentation** : [https://developer.hashicorp.com/vault](https://developer.hashicorp.com/vault)
- **External Secrets Operator** : [https://external-secrets.io/](https://external-secrets.io/)
- **Kubernetes — NetworkPolicy** : [https://kubernetes.io/docs/concepts/services-networking/network-policies/](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- **Kubernetes — RBAC** : [https://kubernetes.io/docs/reference/access-authn-authz/rbac/](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- **Traefik — Documentation officielle** : [https://doc.traefik.io/traefik/](https://doc.traefik.io/traefik/)
