# Rapport Dive — Analyse des layers et optimisation des images

> Ce rapport documente l'audit des images OCI de MIAGE-Bank réalisé avec Dive en mode CI.

## Configuration Dive (mode CI)

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

---

## Backend — eclipse-temurin:17-jre-alpine

### Analyse des layers

| # | Layer | Taille estimée | Contenu |
|---|-------|----------------|---------|
| 1 | Alpine base | ~5 Mo | Système de base Alpine Linux |
| 2 | JRE Temurin 17 | ~100 Mo | Runtime Java (image de base eclipse-temurin) |
| 3 | `WORKDIR /app` | 0 o | Métadonnée uniquement |
| 4 | `RUN addgroup && adduser` | ~5 Ko | Création utilisateur non-root |
| 5 | `COPY *.jar app.jar` | ~40-60 Mo | Artefact Spring Boot (fat JAR) |

**Taille totale estimée** : ~150-170 Mo

### Fichiers superflus identifiés

- Le **fat JAR** Spring Boot embarque toutes les dépendances (Tomcat, Jackson, Spring, etc.) dans un seul fichier. Cela signifie que chaque rebuild recopie l'intégralité des dépendances même si seul le code applicatif a changé.
- Les métadonnées Maven (`META-INF/maven/`) dans le JAR ne sont pas nécessaires à l'exécution.

### Propositions d'optimisation

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

---

## Frontend — node:20-alpine

### Analyse des layers

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

### Fichiers superflus identifiés

- **`node_modules/`** (~200-500 Mo) : c'est le principal point d'amélioration. La totalité des dépendances de développement ET de production sont copiées dans l'image.
- Les fichiers de cache npm (`.cache/`) et les fichiers de type (`.d.ts`) sont inutiles à l'exécution.
- Les `README.md`, `LICENSE`, `CHANGELOG.md` dans chaque package npm sont superflus.

### Propositions d'optimisation

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

---

## Résumé avant/après (estimations)

| Image | Avant optimisation | Après optimisation | Gain |
|-------|-------------------|-------------------|------|
| Backend | ~170 Mo | ~110 Mo | ~35% (layered JAR + jlink) |
| Frontend | ~400 Mo | ~80 Mo | ~80% (standalone + multi-stage) |

---

## Abaissement des seuils

Si les images ne passent pas les gates Dive avec les seuils demandés (efficacité 95%, max 20 Mo gaspillés, max 10% gaspillé), les seuils peuvent être ajustés dans `mise.toml`. La justification doit être documentée ici.

> **État actuel** : les seuils sont configurés selon les exigences du TP. L'image frontend pourrait nécessiter l'optimisation standalone pour atteindre le seuil d'efficacité de 95%.
