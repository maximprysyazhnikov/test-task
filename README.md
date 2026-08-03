# WinWin.travel DevOps test task

A tiny dependency-free Python service runs behind nginx. Compose publishes only nginx on `127.0.0.1:8080`; the app stays on a private user-defined network. The bonus manifests run the same image in Kind behind ingress-nginx.

## Repository layout

```text
app/                 Python service and Dockerfile
nginx/nginx.conf     reverse proxy, request IDs, and rate limiting
scripts/test.ps1     deterministic local acceptance checks
k8s/                 Kind config and Kubernetes resources
docker-compose.yml   mandatory two-service stack
Makefile             operational shortcuts
.github/workflows/   cloud-based Compose acceptance test
```

## Prerequisites

Mandatory: Docker Desktop or Docker Engine with Compose v2, plus GNU Make, a POSIX shell, and `curl`. On Windows, GNU Make can be installed with Chocolatey (`choco install make`), or the PowerShell commands below can be run directly.

Bonus: Kind, kubectl, and Helm 3. Host ports `8080` (Compose) and `80` (Kind) must be free.

## Docker Compose (mandatory)

```sh
cp .env.example .env
# Edit ENV_NAME in .env if desired.
make up
make test
make logs
make down
```

Without Make:

```powershell
Copy-Item .env.example .env
docker compose up -d --build --wait
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
docker compose logs --follow --tail=200
docker compose down --volumes --remove-orphans
```

Expected health response:

```console
$ curl -s http://localhost:8080/healthz
{"status":"ok","service":"app","env":"local"}
```

`make test` also sends 20 concurrent requests. Its HTTP summary must contain both `200` and `429`, proving that normal traffic succeeds while the per-client 10 r/s nginx limit is active. It also checks end-to-end `X-Request-ID` pass-through. Inspect health and published ports with:

```sh
docker compose ps
docker compose port proxy 8080
```

To verify request-ID handling in logs, send a known value and inspect nginx output:

```sh
curl -H 'X-Request-ID: reviewer-123' http://localhost:8080/healthz
docker compose logs proxy | grep reviewer-123
```

## Kind + ingress-nginx (bonus)

The Kind node maps localhost port 80 to ingress-nginx. Build once, load the local image, install the controller, and apply all manifests:

```sh
kind create cluster --name winwin --config k8s/kind-config.yaml
docker build -t winwin-app:local app
kind load docker-image winwin-app:local --name winwin

helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.hostPort.enabled=true \
  --set controller.service.type=NodePort \
  --set controller.watchIngressWithoutClass=false \
  --set controller.allowSnippetAnnotations=true \
  --set-string controller.nodeSelector."ingress-ready"=true \
  --set controller.admissionWebhooks.enabled=false

kubectl wait --namespace ingress-nginx \
  --for=condition=Ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s
kubectl apply -k k8s
kubectl rollout status deployment/app --timeout=120s
kubectl get pods,services,ingress
curl -s http://localhost/healthz
```

Expected bonus response:

```json
{"status":"ok","service":"app","env":"kubernetes"}
```

Clean up the cluster with `kind delete cluster --name winwin`.

## Cloud verification

The `Compose acceptance tests` GitHub Actions workflow runs automatically for pushes and pull requests targeting `main`. It validates Compose, builds both services on a clean Ubuntu runner, waits for both healthchecks, runs the JSON/request-ID/rate-limit tests, prints diagnostic logs, and cleans up. It can also be started manually from **Actions → Compose acceptance tests → Run workflow**.

## Troubleshooting

- If Compose reports an unhealthy proxy immediately after a flood test, wait a second for the rate-limit bucket to drain and rerun `docker compose ps`.
- If port 8080 or 80 is occupied, stop the conflicting local service; the fixed ports are part of the acceptance contract.
- If Kind cannot pull the app, confirm `kind load docker-image winwin-app:local --name winwin` ran after the Docker build.

## Design notes

- Python's standard library avoids runtime packages and returns stable compact JSON.
- nginx preserves an incoming `X-Request-ID` or creates `$request_id` when absent, and records the effective ID in access logs.
- The app has no published host port. Both containers use unprivileged identities, healthchecks, and `no-new-privileges`; the Kubernetes container also drops all capabilities and uses a read-only root filesystem.
- TLS was intentionally omitted because it is optional and would add certificate setup without improving the required local flow.
