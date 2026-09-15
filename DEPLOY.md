# Deploying the demo on a VPS

Target setup: one VM (tested sizing: 4 vCPU / 8 GB RAM), Docker Compose, Caddy terminating TLS for:

- `https://demo-a.gruzewski.dev` → api-service
- `https://demo-b.gruzewski.dev` → external-service
- `https://grafana.gruzewski.dev` → Grafana (anonymous viewer access, admin login for editing)
- `https://zipkin.gruzewski.dev` → Zipkin (basic auth)

Logs go through Promtail to Loki and are browsed in Grafana (dashboard panel or Explore). Prometheus and Loki are not exposed publicly — access them over an SSH tunnel.

## 1. Provision the VM

- Ubuntu 24.04, 4 vCPU / 8 GB RAM / 80 GB disk (e.g. Hetzner CX32), SSH key auth.
- Cloud firewall (enforced outside the VM, so Docker cannot bypass it): allow inbound 22, 80, 443 only.

## 2. DNS

Create A records pointing to the VM's public IP:

```
demo-a.gruzewski.dev   A  <VM_IP>
demo-b.gruzewski.dev   A  <VM_IP>
grafana.gruzewski.dev  A  <VM_IP>
zipkin.gruzewski.dev   A  <VM_IP>
```

Do this before starting the stack so Caddy can obtain Let's Encrypt certificates.

## 3. Install Docker

```bash
curl -fsSL https://get.docker.com | sh
```

## 4. Configure secrets

```bash
git clone <repo-url>
cd from-metrics-to-root-cause-jvm
cp .env.example .env
```

Edit `.env`:

- `GRAFANA_ADMIN_PASSWORD` — Grafana admin password.
- `DEMO_AUTH_HASH` — bcrypt hash for the basic auth user `demo` (Zipkin), generated with:

```bash
docker run --rm caddy:2 caddy hash-password --plaintext 'your-password'
```

`.env` is gitignored and never committed.

## 5. Start the stack

```bash
docker compose up -d --build
```

The first build downloads Maven dependencies and takes a few minutes.

## 6. Verify

```bash
curl "https://demo-b.gruzewski.dev/enrichment?userId=1"
curl "https://demo-a.gruzewski.dev/orders?userId=40&details=true"
docker compose ps
```

All containers should be `Up`, both curls should return 200 with valid TLS.

## 7. Observability UIs

- Grafana: https://grafana.gruzewski.dev — dashboard "From Metrics to Root Cause" in the Demo folder; viewing needs no login, editing needs admin + `GRAFANA_ADMIN_PASSWORD`. Logs: the "Application logs" panel or Explore with the Loki datasource; a `traceId` in a log line links to the trace in the Zipkin datasource.
- Zipkin: https://zipkin.gruzewski.dev (user `demo`, basic auth password)
- Prometheus and Loki (not public): `ssh -N -L 9090:localhost:9090 -L 3100:localhost:3100 root@<VM_IP>`

## 8. Generate traffic (from your laptop)

```bash
./scripts/baseline-traffic.sh
./scripts/demo.sh
```

Both default to `https://demo-a.gruzewski.dev`; override with `BASE_URL=...` if needed.

## 9. After it works

- Take a VM snapshot so the environment can be recreated quickly.
- The stack has `restart: unless-stopped`, so it survives a VM reboot.
