# kratos (Vellum auth) — styx / `apps`

Self-hosted Ory Kratos for Vellum. Deployed via Flux with the bjw-s `app-template`
chart, mirroring the other `apps/*` services. **No ingress of its own** — Kratos
is fronted by the Vellum web BFF at `https://vellum.${TAILSCALE_DOMAIN}/kratos/*`
(same-origin), so the `ory_kratos_session` cookie is valid for the app origin.

## Files

| File | Purpose |
|---|---|
| `helmrelease.yaml` | app-template HelmRelease, values from the `kratos-values` ConfigMap |
| `values.yaml` | migrate init + `kratos serve`; services `kratos-public` (4433) / `kratos-admin` (4434); config volume; `envFrom` the `kratos` Secret; admin-port probes |
| `config/kratos.yml` | **cluster overlay** of Kratos config (same-origin URLs, JSON logs, `leak_sensitive_values: false`, DSN/secrets from env) |
| `config/identity.schema.json` | minimal identity schema (`traits.email` only) — identical to cv-builder `infra/kratos/` |
| `kustomization.yaml` / `kustomizeconfig.yaml` | generate `kratos-values` (hashed) + `kratos-config` (stable name, mounted at `/etc/config/kratos`) |

Registered by `clusters/styx/apps/kratos.yaml` (`dependsOn: apps-base, postgres`).

## Secret contract — create BEFORE deploy (SOPS)

A SOPS-encrypted `Secret` named **`kratos`** in namespace **`apps`**, consumed via
`envFrom` on both the migrate init container and the serve container. Ory maps
these env keys onto config paths (`SECRETS_COOKIE` → `secrets.cookie`, etc.; a
scalar is coerced to a single-element array).

| Secret key | Maps to | Notes |
|---|---|---|
| `DSN` | `dsn` | `postgres://kratos:<PW>@postgres.core.svc.cluster.local:5432/kratos?sslmode=disable` (match your PG TLS/sslmode) |
| `SECRETS_COOKIE` | `secrets.cookie` | long random string; rotating invalidates active sessions |
| `SECRETS_CIPHER` | `secrets.cipher` | **exactly 32 bytes** (Kratos requirement) |

Example plaintext before `sops --encrypt` (add to `apps/kratos/` as `secret.yaml`
and to `kustomization.yaml` `resources:`, matching the outline/miniflux pattern):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: kratos
  namespace: apps
type: Opaque
stringData:
  DSN: postgres://kratos:CHANGEME@postgres.core.svc.cluster.local:5432/kratos?sslmode=disable
  SECRETS_COOKIE: <32+ random chars>
  SECRETS_CIPHER: <EXACTLY 32 chars>
```

## Vellum HelmRelease wiring (add when `apps/vellum/` lands)

Kratos has no hostname; the web BFF proxies it. Add these envs to the Vellum
HelmRelease (`apps/vellum/values.yaml`):

```yaml
# API (Gin) container — derives the principal from the forwarded session cookie:
env:
  KRATOS_PUBLIC_URL: http://kratos-public.apps.svc.cluster.local:4433

# WEB (SvelteKit BFF) container:
env:
  # internal base for the /kratos proxy + server-side whoami / flow fetch
  KRATOS_PUBLIC_URL: http://kratos-public.apps.svc.cluster.local:4433
  # browser-facing base — same-origin path prefix through the BFF proxy
  PUBLIC_KRATOS_BROWSER_URL: https://vellum.${TAILSCALE_DOMAIN}/kratos
```

The web app already ships the catch-all proxy route (`/kratos/[...path]`) that
forwards to `KRATOS_PUBLIC_URL`, streaming bodies and preserving cookies both
directions. No Kratos ingress/hostname is created.

## Deploy order

1. Create the `kratos` DB + role in `postgres.core` (done) and the SOPS `kratos` Secret.
2. Deploy Kratos first (this app). The `01-migrate` init runs `kratos migrate sql up`
   against the `kratos` DB, then `kratos serve` starts; readiness is `:4434/health/ready`.
3. Create a pre-verified default admin via the **admin API** (SMTP is deferred):

   ```bash
   # from inside the cluster / a debug pod that can reach kratos-admin:4434
   curl -s -X POST http://kratos-admin.apps.svc.cluster.local:4434/admin/identities \
     -H 'Content-Type: application/json' \
     -d '{
       "schema_id": "default",
       "traits": {"email": "you@example.com"},
       "verifiable_addresses": [{"value":"you@example.com","verified":true,"via":"email","status":"completed"}],
       "credentials": {"password": {"config": {"password": "<initial-password>"}}}
     }'
   ```

4. Deploy/redeploy Vellum with the envs above; verify sign-in end-to-end over the
   tailnet at `https://vellum.${TAILSCALE_DOMAIN}`.

## Deferred

- **SMTP courier** — `config/kratos.yml` keeps a placeholder `smtp` URI; verification
  is done via the admin API for the beta. Swap in a transactional provider
  (SPF/DKIM/DMARC) later; no manifest change beyond the Secret/URI.
- **Image** pinned by digest (`v1.3.1@sha256:fe2428…`); SQLite→Postgres is already
  handled here (cluster uses the `kratos` Postgres DB).
