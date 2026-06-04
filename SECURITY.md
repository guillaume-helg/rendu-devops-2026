# Security Guidelines

## Overview
This project implements DevSecOps best practices with Kubernetes, Helm, container scanning, and secret management via Vault.

## Secret Management

### Environment Variables
- All secrets are managed via environment variables, never hardcoded
- Use `.env.example` as a template for configuration
- Deploy with actual secrets from Vault or CI/CD secrets manager
- Database passwords, API tokens, and credentials are externalized

### Vault Integration
- Vault tokens expire every 24 hours (configure in Vault)
- Database passwords are rotated quarterly
- Use External Secrets Operator (ESO) for automatic secret syncing to Kubernetes

### Rotation Steps
1. Generate new credentials in Vault CLI or UI
2. Update ExternalSecret resource to trigger resync
3. Restart affected pods: `kubectl rollout restart deployment/miage-bank-frontend -n miage-bank`

## RBAC & Least Privilege
- ServiceAccount has minimal permissions via Role bindings
- Only read access to necessary secrets
- API gateway uses specific credentials per service
- All microservices run as non-root users (uid: 1000)

## Container Security
- All images use non-root containers with `runAsNonRoot: true`
- Read-only root filesystem where possible
- Dropped all Linux capabilities: `drop: ["ALL"]`
- Security context: `seccompProfile: RuntimeDefault`
- Regular image scanning with Trivy (HIGH + CRITICAL severities)

## Image Scanning
All container images are scanned before deployment:
```bash
# Vulnerability scanning
trivy image --severity HIGH,CRITICAL --exit-code 0 miage-bank-gateway:latest

# Secret detection
trivy image --severity HIGH,CRITICAL --scanners secret miage-bank-backend:latest
```

## Network Policies
- Default-deny ingress/egress with explicit allowlists
- Frontend only accepts traffic from ingress controller
- Backend services only communicate with authorized peers
- Database restricted to backend services only

## CI/CD Security
- Secrets are masked in CI logs
- No credentials in build artifacts or Docker layer history
- Image provenance tracking via signed builds
- Automated scanning on every build

## Compliance
- PCI-DSS aligned for banking application
- Audit logs for all secret access
- Data encryption at rest and in transit
- Regular security assessments and penetration testing

## Incident Response
1. Rotate all compromised credentials immediately
2. Review audit logs for unauthorized access
3. Update IP allowlists if needed
4. Redeploy affected pods with new credentials

## Resources
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)
- [OWASP Container Security Top 10](https://owasp.org/www-project-container-security/)
- [Vault Documentation](https://www.vaultproject.io/docs)
