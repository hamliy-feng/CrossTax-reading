-- Application data is isolated from crosstax legal evidence; additive migration.
BEGIN;
CREATE SCHEMA IF NOT EXISTS crosstax_app;
CREATE TABLE IF NOT EXISTS crosstax_app.records (
 owner_id text NOT NULL,
 kind text NOT NULL CHECK (kind IN ('case','project','file','summary','task','search','evidence','preferences','recommendation','assessment','check')),
 record_id text NOT NULL,
 payload jsonb NOT NULL,
 revision bigint NOT NULL DEFAULT 1,
 created_at double precision NOT NULL,
 updated_at double precision NOT NULL,
 PRIMARY KEY (owner_id,kind,record_id)
);
CREATE INDEX IF NOT EXISTS app_records_owner_kind ON crosstax_app.records(owner_id,kind,updated_at DESC);
COMMENT ON TABLE crosstax_app.records IS 'Owner scoped workbench records; never accessed from a browser SQL client. Server derives owner from verified identity.';
CREATE TABLE IF NOT EXISTS crosstax_app.schema_migrations (
 version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO crosstax_app.schema_migrations(version) VALUES ('033') ON CONFLICT DO NOTHING;
COMMIT;
