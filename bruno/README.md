# MIAGE Bank API - Bruno Collection

This is a [Bruno](https://www.usebruno.com/) collection for testing the MIAGE Bank API.

## Setup

1. **Install Bruno** — Download from [usebruno.com](https://www.usebruno.com/)

2. **Open the collection** — Open the `bruno` folder in Bruno (File → Open Collection)

3. **Select environment** — Click on the environment dropdown and select `minikube`

4. **Update base URL if needed** — Edit `environments/minikube.bru` to point to your gateway:
   - For local: `http://localhost:8080/api`
   - For Minikube: `http://miage-bank.local/api` (requires `/etc/hosts` entry)
   - For direct pod access: `http://miage-bank-gateway:8080/api` (requires port-forward)

## What is tested

Every request now carries `assert` + `tests` blocks that validate the
deployment, not just the happy-path status code:

- **Health** — gateway is reachable, reports `UP`, responds under 2s
- **Auth** — register/login return valid JWTs, refresh issues a new token, logout works
- **Customers / Accounts / Composite** — CRUD endpoints return the right status,
  shapes, and balances (e.g. opening balance, +50 credit -> 150)
- **Demo** — secured endpoint is reachable only with a valid token

Tokens and IDs are captured automatically into environment variables
(`accessToken`, `refreshToken`, `clientId`, `accountId`) as the suite runs, so
the requests chain together without manual copy/paste.

## Running automatically (CLI — recommended for deployment checks)

The whole suite can be run headless against a live cluster with the
[Bruno CLI](https://docs.usebruno.com/bru-cli/overview):

```bash
npm install -g @usebruno/cli

# from the bruno/ folder
bru run . --env minikube --reporter-junit results.xml
# or use the helper script:
./run-deployment-tests.sh
```

Folders carry a `seq` (via `folder.bru`) so they run in dependency order:
**Health → Auth → Customers → Accounts → Composite → Demo**. A single
`bru run` invocation keeps the captured variables alive across requests.

`Register` generates a unique email on every run (`test-<timestamp>@example.com`)
so the suite is repeatable without hitting "email already in use".

> The `Accounts/Transfer.bru` request needs a second, pre-provisioned account.
> Set the `destinationAccountId` env var before running it; otherwise skip it.

## Manual testing flow (Bruno GUI)

1. **Register** (`Auth/Register.bru`) — creates an account and stores the token
2. **Login** (`Auth/Login.bru`) — refreshes the access token
3. **Test endpoints** — run Customers / Accounts / Composite requests; IDs are
   captured automatically as you go

## Port Forward (if needed)

To access the API directly without ingress:

```bash
kubectl port-forward -n miage-bank svc/miage-bank-gateway 8080:8080
```

Then use: `http://localhost:8080/api` in the environment

## Debugging

Check backend logs:
```bash
kubectl logs -n miage-bank -l app=miage-bank-gateway -f
```

Check specific service logs:
```bash
kubectl logs -n miage-bank miage-bank-customer-xxx -f
```
