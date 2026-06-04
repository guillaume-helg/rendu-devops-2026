# Production Readiness Checklist — MIAGE Bank

## Overview
This document tracks all production readiness improvements applied to the MIAGE Bank Kubernetes deployment.

---

## 1. ✅ Init Containers for Dependency Readiness (COMPLETED)

### What
Init containers ensure that dependencies (Discovery Service, Config Server) are ready before main containers start.

### Implementation
- **File**: `tp-buildah-trivy-dive-helm/miage-bank/templates/_init-containers.tpl`
- **Usage**: Gateway and Config deployments now wait for:
  - Discovery Service health (`/eureka/status`)
  - Config Server health (`/actuator/health`)

### Benefits
✅ Prevents cascading startup failures  
✅ No application code changes required  
✅ Kubernetes-native solution (no sidecars)  
✅ Uses lightweight `curlimages/curl` image  

### Deployment
Applied to:
- `gateway-deployment.yaml` — Waits for Discovery + Config
- `config-deployment.yaml` — Waits for Discovery

---

## 2. ✅ HTTP Health Probes (COMPLETED)

### What
Replaced TCP socket probes with semantic HTTP health checks using Spring Boot Actuator endpoints.

### Implementation
- **Replaced**: `tcpSocket` → `httpGet`
- **Endpoints**:
  - `startupProbe`: `/actuator/health/startup` (max 150s)
  - `livenessProbe`: `/actuator/health/liveness` (10s interval)
  - `readinessProbe`: `/actuator/health/readiness` (5s interval)

### Applied to
- `gateway-deployment.yaml`
- `config-deployment.yaml`

### Benefits
✅ Detects application-level failures (DB connectivity, config loading)  
✅ Better than TCP probes for complex services  
✅ Spring Boot provides detailed health info  

---

## 3. ✅ Pod Disruption Budgets (COMPLETED)

### What
Protects against voluntary disruptions (node drain, cluster upgrades).

### Implementation
Created PDB for all services:
- `gateway-pdb.yaml` — Minimum 1 pod available
- `config-pdb.yaml` — Minimum 1 pod available
- `discovery-pdb.yaml` — Minimum 1 pod available
- `customer-pdb.yaml` — Minimum 1 pod available
- `account-pdb.yaml` — Minimum 1 pod available
- `composite-pdb.yaml` — Minimum 1 pod available

### Benefits
✅ Ensures service availability during cluster operations  
✅ Kubernetes respects PDB before evicting pods  
✅ Prevents cascading service outages  

---

## 4. ✅ Horizontal Pod Autoscaling (COMPLETED)

### What
Automatic pod scaling based on CPU/Memory utilization.

### Configuration

#### Development (values.yaml)
```yaml
gateway:
  autoscaling:
    enabled: false
    minReplicas: 1
    maxReplicas: 3
```

#### Production (values-prod.yaml)
```yaml
gateway:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 75
    targetMemoryUtilizationPercentage: 80
```

### Implementation
- **File**: `gateway-hpa.yaml`
- **Metrics**: CPU + Memory utilization
- **Scale-up**: Immediate (0s stabilization)
- **Scale-down**: Slow (300s stabilization)

### Enable in Production
```bash
helm upgrade miage-bank ./miage-bank \
  --set gateway.autoscaling.enabled=true \
  -n miage-bank
```

---

## 5. ✅ Enhanced Ingress with TLS & Rate Limiting (COMPLETED)

### What
Add HTTPS/TLS and rate limiting to Ingress.

### Configuration

#### Development (values.yaml)
```yaml
ingress:
  className: "nginx"
  tls:
    enabled: false
  annotations:
    nginx.ingress.kubernetes.io/rate-limit: "100"
    nginx.ingress.kubernetes.io/rate-limit-window: "60m"
```

#### Production (values-prod.yaml)
```yaml
ingress:
  className: "traefik"
  tls:
    enabled: true
    certIssuer: "letsencrypt-prod"
  annotations:
    traefik.ingress.kubernetes.io/ratelimit.rps: "10"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
```

### Prerequisites
For HTTPS, install cert-manager:
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.crds.yaml
```

### Benefits
✅ HTTPS encryption for all traffic  
✅ Automatic certificate provisioning (Let's Encrypt)  
✅ Rate limiting prevents DDoS/abuse  

---

## 6. 📋 Image Tagging Strategy (RECOMMENDED)

### Current Issue
```yaml
tag: "latest"  # ❌ Non-deterministic, prone to breaking changes
```

### Recommended Approach
Use Git SHA or semantic versioning with digest:

#### Option A: Git SHA (Recommended for CI/CD)
```yaml
tag: "latest@sha256:abc123def456..."
# OR
tag: "v1.0.0-20240604"
```

#### Option B: ArgoCD Image Updater
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: gateway=ghcr.io/guillaume-helg/miage-bank-gateway
    argocd-image-updater.argoproj.io/gateway.update-strategy: digest
```

### Implementation in CI
Update `.github/workflows/ci.yml`:
```bash
- name: Update image tags with SHA
  run: |
    GATEWAY_SHA=$(buildah inspect miage-bank-gateway:latest | jq -r '.RepoDigests[0]')
    sed -i "s|gateway.image.tag:.*|gateway.image.tag: \"${GATEWAY_SHA}\"|" values.yaml
```

---

## 7. 📋 Resource Monitoring & Prometheus (RECOMMENDED)

### Implementation
Create ServiceMonitor for metrics collection:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: miage-bank-gateway
spec:
  selector:
    matchLabels:
      component: gateway
  endpoints:
  - port: metrics
    path: /actuator/prometheus
    interval: 30s
```

### Setup
```bash
# Install Prometheus Operator
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
```

---

## 8. 📋 Database Backups (RECOMMENDED)

### Implement MySQL CronJob
Create daily backups at 2 AM:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: mysql-backup
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: mysql:8.0
            command:
            - /bin/sh
            - -c
            - |
              mysqldump -h mysql -u root -p${MYSQL_ROOT_PASSWORD} --all-databases | \
              gzip > /backup/mysql-$(date +%Y%m%d_%H%M%S).sql.gz
```

---

## Deployment Instructions

### Development
```bash
cd tp-buildah-trivy-dive-helm/
mise run helm:deploy
```

### Production (with all features)
```bash
export DB_PASSWORD="your-secure-password"
export VAULT_TOKEN="your-vault-token"

helm upgrade --install miage-bank ./miage-bank \
  -f ./miage-bank/values.yaml \
  -f ./miage-bank/values-prod.yaml \
  -n miage-bank --create-namespace
```

### Enable HPA + TLS
```bash
helm upgrade miage-bank ./miage-bank \
  -f ./miage-bank/values-prod.yaml \
  --set gateway.autoscaling.enabled=true \
  --set ingress.tls.enabled=true \
  -n miage-bank
```

---

## Production Checklist

| Feature | Status | Priority | Action |
|---------|--------|----------|--------|
| Init Containers | ✅ Done | HIGH | Deployed |
| HTTP Health Probes | ✅ Done | HIGH | Deployed |
| Pod Disruption Budgets | ✅ Done | HIGH | Deployed |
| HPA on Gateway | ✅ Done | HIGH | Enable in values-prod.yaml |
| TLS on Ingress | ✅ Done | HIGH | Install cert-manager + enable |
| Rate Limiting | ✅ Done | MEDIUM | Configured in annotations |
| Image Digest Strategy | ⚠️ Recommended | MEDIUM | Implement in CI |
| Prometheus Monitoring | 📋 Template Ready | MEDIUM | Apply ServiceMonitor |
| MySQL Backups | 📋 Template Ready | MEDIUM | Apply CronJob |
| Network Policies | ⚠️ Assumed | MEDIUM | Document + validate |

---

## Next Steps

1. **Immediate (Next Deployment)**
   - Deploy init containers ✅
   - Deploy HTTP health probes ✅
   - Deploy PDB ✅

2. **This Week**
   - Enable HPA in prod values
   - Install cert-manager + enable TLS
   - Test Ingress rate limiting

3. **This Month**
   - Implement image SHA strategy in CI
   - Deploy Prometheus monitoring
   - Set up automated MySQL backups
   - Document and test network policies

---

## References
- [Kubernetes Init Containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)
- [Pod Disruption Budgets](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)
- [Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Spring Boot Health Endpoints](https://spring.io/guides/gs/actuator-service/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
