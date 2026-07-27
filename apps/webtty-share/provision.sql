-- One-time Postgres provisioning for webtty-share.
--
-- This is NOT applied by Flux. Creating a role/database needs the Postgres SUPERUSER,
-- and we deliberately keep that credential out of the `apps` namespace / the app pod
-- (least privilege — the app should only ever hold its own scoped DATABASE_URL). So this
-- is a documented, idempotent, out-of-band admin action. The app creates its own tables
-- (schema) idempotently at boot under an advisory lock; this only creates the login role
-- and the database.
--
-- Run once as the superuser, passing the role password (the same one that appears in the
-- SOPS `webtty-share` Secret's DATABASE_URL):
--
--   POD=$(kubectl get pods -n core -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}')
--   PGPW=$(kubectl get secret -n core postgres -o jsonpath='{.data.postgres-password}' | base64 -d)
--   kubectl exec -i -n core "$POD" -- env PGPASSWORD="$PGPW" \
--     psql -U postgres -v pw="<role-password>" -f - < apps/webtty-share/provision.sql
--
-- Idempotent: safe to re-run. To rotate the role password, ALTER ROLE ... PASSWORD and
-- update DATABASE_URL in the SOPS secret together.

\set ON_ERROR_STOP on

-- Login role (idempotent).
SELECT format('CREATE ROLE webtty_share LOGIN PASSWORD %L', :'pw')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'webtty_share')\gexec

-- Database owned by the role (idempotent; CREATE DATABASE cannot run inside a transaction).
SELECT 'CREATE DATABASE webtty_share OWNER webtty_share'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'webtty_share')\gexec

-- Let the role manage its own schema; the app creates the tables at boot.
\connect webtty_share
ALTER SCHEMA public OWNER TO webtty_share;
GRANT ALL ON SCHEMA public TO webtty_share;
