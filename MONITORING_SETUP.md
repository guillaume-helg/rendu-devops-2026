# Monitoring Setup — Prometheus & Grafana

## Quick Start

### 1. Install Prometheus Operator (Kube-Prometheus Stack)

```bash
# Add Prometheus Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --set prometheus.prometheusSpec.retention=30d \
  --set grafana.adminPassword=admin
```

### 2. Enable Monitoring in MIAGE Bank

```bash
# Deploy with monitoring enabled
helm upgrade miage-bank ./tp-buildah-trivy-dive-helm/miage-bank \
  --set monitoring.enabled=true \
  -n miage-bank
```

This will:
- Create `ServiceMonitor` for Gateway & Config services
- Scrape metrics from `/actuator/prometheus` endpoint
- 30s scrape interval

### 3. Access Grafana

```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Login
# URL: http://localhost:3000
# Username: admin
# Password: admin
```

### 4. Add Prometheus Data Source

In Grafana:
1. Configuration → Data Sources → Add Data Source
2. Select Prometheus
3. URL: `http://prometheus-kube-prometheus-prometheus:9090`
4. Save & Test

### 5. Import Dashboards

**Spring Boot Dashboard:**
- ID: `12900` (Spring Boot Statistics)
- ID: `13457` (Spring Boot 2.x Kubernetes)

```bash
# CLI approach
curl -s https://grafana.com/api/dashboards/12900/revisions/2/download | \
  curl -X POST -H "Content-Type: application/json" \
    -d @- \
    http://admin:admin@localhost:3000/api/dashboards/db
```

---

## Metrics Available

### Gateway Service
- **HTTP Requests**: `http_server_requests_seconds_bucket`
- **Active Threads**: `jvm_threads_live_threads`
- **Memory Usage**: `jvm_memory_used_bytes`
- **GC Time**: `jvm_gc_duration_seconds`
- **DB Connections**: `hikaricp_connections_active`

### Custom Metrics Example

Add to Spring Boot application:

```java
import io.micrometer.core.instrument.MeterRegistry;

@Component
public class CustomMetrics {
    public CustomMetrics(MeterRegistry registry) {
        registry.counter("banking.transactions.total", "status", "success").increment();
    }
}
```

Query in Prometheus:
```promql
banking_transactions_total{status="success"}
```

---

## Alerting

### Create PrometheusRule

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: miage-bank-alerts
  namespace: monitoring
spec:
  groups:
  - name: miage-bank
    interval: 30s
    rules:
    - alert: GatewayHighErrorRate
      expr: rate(http_server_requests_seconds_count{status=~"5.."}[5m]) > 0.05
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High error rate on gateway"

    - alert: HighMemoryUsage
      expr: jvm_memory_used_bytes / jvm_memory_max_bytes > 0.9
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: "JVM memory usage > 90%"
```

### Configure Alert Routing

Setup AlertManager for Slack/PagerDuty:

```yaml
global:
  resolve_timeout: 5m
  slack_api_url: 'YOUR_SLACK_WEBHOOK'

route:
  receiver: 'slack'
  routes:
  - match:
      severity: critical
    receiver: 'critical-team'
```

---

## Database Backups

### Enable Automated Backups

```bash
# Update database chart with backups enabled
helm upgrade database ./tp-buildah-trivy-dive-helm/database \
  --set backup.enabled=true \
  --set backup.schedule="0 2 * * *" \
  -n miage-bank
```

This creates:
- **CronJob**: Runs daily at 2 AM
- **PersistentVolumeClaim**: Stores 7 days of backups
- **Automatic Cleanup**: Deletes backups older than 7 days

### Restore from Backup

```bash
# List available backups
kubectl exec -it mysql-0 -n miage-bank -- ls -lah /backup/

# Restore specific backup
kubectl exec -it mysql-0 -n miage-bank -- \
  zcat /backup/mysql-backup-20240604_020000.sql.gz | \
  mysql -u root -p$MYSQL_ROOT_PASSWORD
```

---

## Troubleshooting

### Check ServiceMonitor Discovery

```bash
kubectl get servicemonitor -n miage-bank
kubectl describe servicemonitor miage-bank-gateway -n miage-bank
```

### Verify Prometheus Scraping

```bash
# Access Prometheus UI
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Check targets: http://localhost:9090/targets
# Check scrape configs: http://localhost:9090/service-discovery
```

### Check Metrics Endpoints

```bash
# Port-forward to gateway
kubectl port-forward svc/miage-bank-gateway 8080:8080 -n miage-bank

# Test metrics endpoint
curl http://localhost:8080/actuator/prometheus | head -20
```

---

## Production Recommendations

1. **Persistent Storage for Prometheus**
   ```yaml
   prometheus:
     prometheusSpec:
       storageSpec:
         volumeClaimTemplate:
           spec:
             storageClassName: standard
             accessModes: ["ReadWriteOnce"]
             resources:
               requests:
                 storage: 50Gi
   ```

2. **Retention & Performance**
   - Set retention to 30 days for production
   - Adjust scrape intervals (default 30s)
   - Enable metric relabeling to reduce cardinality

3. **High Availability**
   ```bash
   helm install prometheus prometheus-community/kube-prometheus-stack \
     --set prometheus.replicas=2 \
     --set alertmanager.replicas=2 \
     -n monitoring
   ```

4. **Backup Prometheus Data**
   ```bash
   kubectl exec -it prometheus-kube-prometheus-prometheus-0 \
     -n monitoring -- /bin/sh -c 'tar czf - /prometheus' > prometheus-backup.tar.gz
   ```

---

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Kube-Prometheus-Stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Spring Boot Metrics](https://spring.io/guides/gs/metrics-monitoring/)
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/)
