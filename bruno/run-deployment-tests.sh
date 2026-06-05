#!/usr/bin/env bash
#
# Run the full MIAGE Bank deployment test suite against a running cluster.
#
# Requires the Bruno CLI:  npm install -g @usebruno/cli
# Requires the gateway to be reachable at the env's baseUrl
# (e.g. http://miage-bank.local/api — needs an /etc/hosts entry for minikube,
#  or run `kubectl port-forward -n miage-bank svc/miage-bank-gateway 8080:8080`
#  and set baseUrl to http://localhost:8080/api).
#
# Usage:  ./run-deployment-tests.sh [environment]
#         (environment defaults to "minikube")

set -euo pipefail

cd "$(dirname "$0")"

ENV="${1:-minikube}"

echo "Running MIAGE Bank deployment tests against environment: $ENV"
echo "Folders run in dependency order: Health -> Auth -> Customers -> Accounts -> Composite -> Demo"
echo

# A single `bru run` invocation keeps runtime variables (accessToken, clientId,
# accountId...) alive across requests. folder.bru seq values enforce the order.
bru run . \
  --env "$ENV" \
  --reporter-junit results.xml

echo
echo "Done. JUnit report written to results.xml"
