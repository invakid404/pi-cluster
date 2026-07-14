# Provision Vellum storage (U0.3 tenant isolation) — runbook

Live-provisioning steps for the orchestrator. These are **not** run by Flux; they
create the Postgres DB/role and the MinIO bucket/scoped key that back Vellum's
tenant-isolated storage, then hand three secret values to the SOPS `vellum`
Secret. Additive only — nothing here drops or mutates another app.

All `<PW>` / key placeholders below must be replaced with freshly generated
values before running. Generate strong random values, e.g.:

```bash
openssl rand -base64 24 | tr -d '/+=' | cut -c1-32   # DB password  -> <PW>
openssl rand -hex 20                                  # S3 access key id  -> <S3_KEY_ID>
openssl rand -base64 32 | tr -d '/+=' | cut -c1-40    # S3 secret key     -> <S3_SECRET>
```

Cluster facts this runbook relies on (verified read-only):

| Thing | Value |
|---|---|
| Postgres pod | `postgres-0` (StatefulSet `postgres`, namespace `core`) |
| Postgres superuser | `postgres` |
| Superuser password | in-pod env `$POSTGRES_PASSWORD` (from Secret `core/postgres` key `postgres-password`) |
| Postgres service | `postgres.core.svc.cluster.local:5432` |
| MinIO pod | label `app.kubernetes.io/name=minio`, namespace `core` (e.g. `minio-5955d796dd-94zs6`) |
| `mc` binary in pod | `/opt/bitnami/minio-client/bin/mc`, preconfigured root alias **`local`** |
| MinIO S3 endpoint (in-cluster) | `http://minio.core.svc.cluster.local:9000` |

This mirrors the established **kratos** DB pattern (manual `kubectl exec` against
`postgres-0` using the bitnami superuser env var — no operator, no init job).

---

## 1. Postgres — create `vellum` DB + non-superuser, non-BYPASSRLS role

The role owns its schema so migrations can `CREATE TABLE`, but is `NOSUPERUSER`
and has **no** `BYPASSRLS` (a superuser/BYPASSRLS role silently skips RLS — the
contract forbids it).

### 1a. SQL

Save as reference (the exec below feeds it on stdin). Replace `<PW>`:

```sql
-- Role: login, owns its schema, but MUST NOT bypass RLS.
CREATE ROLE vellum WITH LOGIN PASSWORD '<PW>' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION;

-- Database owned by the vellum role.
CREATE DATABASE vellum OWNER vellum;
```

Then, connected **to the `vellum` database**, lock down the public schema so only
`vellum` can create objects (defense-in-depth; RLS is enforced by the app tables):

```sql
-- run inside database "vellum"
ALTER SCHEMA public OWNER TO vellum;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO vellum;
```

### 1b. Exact kubectl exec invocations

`CREATE DATABASE` cannot run inside a transaction block or be combined with the
role in one `psql -c`, so issue the role, the database, then the schema grants as
three calls. `$POSTGRES_PASSWORD` is already present in the pod; `psql` reads it
via `PGPASSWORD`.

```bash
# 1) create the role (replace <PW> first)
kubectl -n core exec -i postgres-0 -- \
  env PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -c "CREATE ROLE vellum WITH LOGIN PASSWORD '<PW>' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION;"

# 2) create the database owned by vellum
kubectl -n core exec -i postgres-0 -- \
  env PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -c "CREATE DATABASE vellum OWNER vellum;"

# 3) lock down the public schema INSIDE the vellum database
kubectl -n core exec -i postgres-0 -- \
  env PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -U postgres -d vellum \
  -c "ALTER SCHEMA public OWNER TO vellum; REVOKE ALL ON SCHEMA public FROM PUBLIC; GRANT ALL ON SCHEMA public TO vellum;"
```

### 1c. Verify the role is NOT a superuser and does NOT bypass RLS

```bash
kubectl -n core exec -i postgres-0 -- \
  env PGPASSWORD="$POSTGRES_PASSWORD" psql -U postgres -d postgres \
  -c "SELECT rolname, rolsuper, rolbypassrls FROM pg_roles WHERE rolname='vellum';"
# expect: vellum | f | f
```

---

## 2. MinIO — create `vellum` bucket + bucket-scoped access key

Run inside the MinIO pod; the `local` alias is already authenticated as root.
Capture the pod name once:

```bash
MINIO_POD=$(kubectl -n core get pod -l app.kubernetes.io/name=minio -o jsonpath='{.items[0].metadata.name}')
MC=/opt/bitnami/minio-client/bin/mc
```

### 2a. Create the bucket (idempotent)

```bash
kubectl -n core exec "$MINIO_POD" -- $MC mb --ignore-existing local/vellum
```

### 2b. Create a policy scoped to just the `vellum` bucket

Write the policy in the pod, then register it as `vellum-rw`:

```bash
kubectl -n core exec -i "$MINIO_POD" -- sh -c 'cat > /tmp/vellum-policy.json' <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": ["arn:aws:s3:::vellum"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
      "Resource": ["arn:aws:s3:::vellum/*"]
    }
  ]
}
EOF

kubectl -n core exec "$MINIO_POD" -- $MC admin policy create local vellum-rw /tmp/vellum-policy.json
```

### 2c. Create the scoped service account (access key) and attach the policy

Use an explicit access key + secret so the values are known for the SOPS secret.
Replace `<S3_KEY_ID>` / `<S3_SECRET>` first:

```bash
kubectl -n core exec "$MINIO_POD" -- $MC admin user svcacct add \
  --access-key '<S3_KEY_ID>' \
  --secret-key '<S3_SECRET>' \
  --policy /tmp/vellum-policy.json \
  local vellum-rw
```

> The service account inherits the parent user's policy unless `--policy` is
> given; passing the same `/tmp/vellum-policy.json` guarantees the key can touch
> **only** the `vellum` bucket even if `vellum-rw` is later broadened.

Clean up the temp file:

```bash
kubectl -n core exec "$MINIO_POD" -- rm -f /tmp/vellum-policy.json
```

### 2d. Verify the key sees only `vellum`

```bash
kubectl -n core exec -i "$MINIO_POD" -- sh -c \
  '/opt/bitnami/minio-client/bin/mc alias set scoped http://localhost:9000 <S3_KEY_ID> <S3_SECRET> >/dev/null && \
   /opt/bitnami/minio-client/bin/mc ls scoped && \
   /opt/bitnami/minio-client/bin/mc alias rm scoped'
# expect: only "vellum/" listed
```

---

## 3. Keys to add to the SOPS `vellum` Secret

Add the following keys to `apps/vellum/secret.yaml` (`stringData`), alongside the
existing `OPENROUTER_API_KEY`, then re-encrypt with SOPS. The api container
already consumes this Secret via `envFrom.secretRef.name: vellum`, so these reach
the pod as env vars — matching the non-secret vars now in the HelmRelease
(`STORAGE_BACKEND=postgres`, `BLOB_BACKEND=s3`, `S3_ENDPOINT`, `S3_REGION`,
`S3_BUCKET=vellum`, `S3_USE_PATH_STYLE=true`).

| Secret key | Value |
|---|---|
| `DATABASE_URL` | `postgres://vellum:<PW>@postgres.core.svc.cluster.local:5432/vellum?sslmode=disable` |
| `S3_ACCESS_KEY_ID` | `<S3_KEY_ID>` |
| `S3_SECRET_ACCESS_KEY` | `<S3_SECRET>` |

`<PW>`, `<S3_KEY_ID>`, `<S3_SECRET>` must be the exact values used in steps 1 & 2.

> Note: the contract's example DSN string is missing the `@` between password and
> host; the correct pgx DSN is the one in the table above
> (`...vellum:<PW>@postgres.core...`).

Re-encrypt (in-place) after editing:

```bash
sops --encrypt --in-place apps/vellum/secret.yaml
```

Flux + Reloader then roll the api pod (annotation `reloader.stakater.com/auto`),
which runs the embedded migrations (replicas=1, advisory-locked) against the new
`vellum` DB on startup.
