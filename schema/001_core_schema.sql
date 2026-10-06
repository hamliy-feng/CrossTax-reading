-- CrossTax database migration 001 (PostgreSQL 16)
-- Schema core: jurisdiction -> domestic law / bilateral treaty -> revisions -> provisions -> sources
BEGIN;
CREATE SCHEMA IF NOT EXISTS crosstax;
CREATE TABLE IF NOT EXISTS crosstax.jurisdictions (
 id text PRIMARY KEY, name_zh text, name_en text NOT NULL, kind text NOT NULL DEFAULT 'country',
 parent_id text REFERENCES crosstax.jurisdictions(id), iso_code text, created_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS crosstax.tax_types (
 code text PRIMARY KEY, name_zh text NOT NULL, description text
);
CREATE TABLE IF NOT EXISTS crosstax.income_categories (
 code text PRIMARY KEY, name_en text NOT NULL, name_zh text, description text
);
CREATE TABLE IF NOT EXISTS crosstax.sources (
 source_id text PRIMARY KEY, publisher text NOT NULL, publisher_kind text NOT NULL,
 title text NOT NULL, source_url text NOT NULL, country_id text REFERENCES crosstax.jurisdictions(id),
 source_category text NOT NULL, discovered_at date NOT NULL DEFAULT CURRENT_DATE,
 authority_level smallint NOT NULL DEFAULT 0 CHECK (authority_level BETWEEN 0 AND 5),
 source_note text, UNIQUE(source_url)
);
CREATE TABLE IF NOT EXISTS crosstax.documents (
 document_id text PRIMARY KEY, document_kind text NOT NULL, official_title text NOT NULL,
 issuing_body text, jurisdiction_id text REFERENCES crosstax.jurisdictions(id),
 source_id text REFERENCES crosstax.sources(source_id),
 original_language text, original_url text, published_at date, signed_at date,
 status text NOT NULL DEFAULT 'candidate' CHECK(status IN ('candidate','source_verified','professional_reviewed','withdrawn')),
 created_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS crosstax.document_versions (
 version_id text PRIMARY KEY, document_id text NOT NULL REFERENCES crosstax.documents(document_id),
 version_label text NOT NULL, source_sha256 text, retrieved_at timestamptz,
 entered_into_force_at date, applies_from date, applies_to date, law_valid_from date, law_valid_to date,
 ingested_at timestamptz DEFAULT now(),
 audit_status text NOT NULL DEFAULT 'unreviewed', content_locator text,
 UNIQUE(document_id,version_label)
);
CREATE TABLE IF NOT EXISTS crosstax.provisions (
 provision_id text PRIMARY KEY, version_id text NOT NULL REFERENCES crosstax.document_versions(version_id),
 article_path text NOT NULL, original_text text, original_language text,
 page_num integer, source_locator text, checksum_sha256 text,
 review_status text NOT NULL DEFAULT 'unreviewed', UNIQUE(version_id,article_path)
);
CREATE TABLE IF NOT EXISTS crosstax.treaties (
 treaty_id text PRIMARY KEY, title text NOT NULL,
 source_document_id text REFERENCES crosstax.documents(document_id),
 treaty_type text NOT NULL DEFAULT 'DTA', signed_at date, entered_into_force_at date,
 current_status text NOT NULL DEFAULT 'unverified'
);
CREATE TABLE IF NOT EXISTS crosstax.treaty_parties (
 treaty_id text NOT NULL REFERENCES crosstax.treaties(treaty_id),
 jurisdiction_id text NOT NULL REFERENCES crosstax.jurisdictions(id),
 party_role text NOT NULL DEFAULT 'party', PRIMARY KEY(treaty_id,jurisdiction_id)
);
CREATE TABLE IF NOT EXISTS crosstax.treaty_changes (
 change_id text PRIMARY KEY, treaty_id text NOT NULL REFERENCES crosstax.treaties(treaty_id),
 instrument_document_id text REFERENCES crosstax.documents(document_id),
 change_kind text NOT NULL CHECK(change_kind IN ('protocol','MLI','replacement','termination','other')),
 position_a jsonb, position_b jsonb, change_summary text,
 signed_at date, entered_into_force_at date, applies_from date,
 confirmed_status text NOT NULL DEFAULT 'unverified'
);
CREATE TABLE IF NOT EXISTS crosstax.applicability_windows (
 window_id text PRIMARY KEY, document_version_id text NOT NULL REFERENCES crosstax.document_versions(version_id),
 jurisdiction_id text REFERENCES crosstax.jurisdictions(id), tax_type text REFERENCES crosstax.tax_types(code),
 income_category text REFERENCES crosstax.income_categories(code), party_side text, applies_from date, applies_to date,
 proof_source_id text REFERENCES crosstax.sources(source_id),
 status text NOT NULL DEFAULT 'unreviewed'
);
CREATE TABLE IF NOT EXISTS crosstax.version_relations (
 relation_id text PRIMARY KEY, predecessor_version_id text REFERENCES crosstax.document_versions(version_id),
 successor_version_id text REFERENCES crosstax.document_versions(version_id),
 relation_kind text NOT NULL CHECK(relation_kind IN ('amends','repeals','replaces','clarifies','corrects')),
 proof_source_id text REFERENCES crosstax.sources(source_id)
);
CREATE TABLE IF NOT EXISTS crosstax.case_records (
 case_id text PRIMARY KEY, case_name text NOT NULL, jurisdiction_id text REFERENCES crosstax.jurisdictions(id),
 published_at date, occurred_at date, source_id text NOT NULL REFERENCES crosstax.sources(source_id),
 case_type text NOT NULL CHECK(case_type IN ('court_judgment','administrative_decision','tax_authority_notice','company_disclosure','pre_ruling','other')),
 issue_tags text[] NOT NULL DEFAULT '{}', legal_status text NOT NULL DEFAULT 'not_established',
 summary text, original_case_number text,
 professional_review_status text NOT NULL DEFAULT 'unreviewed',
 created_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS crosstax.case_provision_links (
 case_id text NOT NULL REFERENCES crosstax.case_records(case_id),
 provision_id text NOT NULL REFERENCES crosstax.provisions(provision_id),
 link_kind text NOT NULL CHECK(link_kind IN ('cites','applies','distinguishes','overrules','background')),
 reviewed_by text, PRIMARY KEY(case_id,provision_id,link_kind)
);
CREATE TABLE IF NOT EXISTS crosstax.claims (
 claim_id text PRIMARY KEY, text_zh text NOT NULL, jurisdiction_id text REFERENCES crosstax.jurisdictions(id),
 facts_snapshot_id text, asserted_at timestamptz DEFAULT now(), status text NOT NULL DEFAULT 'unverified'
);
CREATE TABLE IF NOT EXISTS crosstax.claim_evidence (
 claim_id text NOT NULL REFERENCES crosstax.claims(claim_id),
 provision_id text REFERENCES crosstax.provisions(provision_id),
 source_id text REFERENCES crosstax.sources(source_id),
 evidence_relation text NOT NULL CHECK(evidence_relation IN ('supports','contradicts','contextualizes')),
 verified_at timestamptz, reviewer text, evidence_text_locator text,
 evidence_level smallint CHECK (evidence_level BETWEEN 0 AND 5),
 CHECK (provision_id IS NOT NULL OR source_id IS NOT NULL)
);
CREATE TABLE IF NOT EXISTS crosstax.coverage_register (
 jurisdiction_id text NOT NULL REFERENCES crosstax.jurisdictions(id),
 tax_type text NOT NULL REFERENCES crosstax.tax_types(code),
 income_category text NOT NULL DEFAULT 'general',
 from_year integer NOT NULL, to_year integer NOT NULL,
 official_sources_count integer NOT NULL DEFAULT 0, provisions_reviewed_count integer NOT NULL DEFAULT 0,
 reviewed_rule_count integer NOT NULL DEFAULT 0,
 missing_materials jsonb NOT NULL DEFAULT '[]'::jsonb,
 last_checked_at timestamptz, PRIMARY KEY(jurisdiction_id,tax_type,income_category,from_year,to_year),
 CHECK (to_year >= from_year)
);
CREATE TABLE IF NOT EXISTS crosstax.ingestion_tasks (
 task_id text PRIMARY KEY, source_id text NOT NULL REFERENCES crosstax.sources(source_id),
 document_id text REFERENCES crosstax.documents(document_id),
 stage text NOT NULL DEFAULT 'discovered',
 status text NOT NULL DEFAULT 'queued', assigned_to text,
 log_note text, created_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS crosstax.text_chunks (
 chunk_id text PRIMARY KEY,
 provision_id text NOT NULL REFERENCES crosstax.provisions(provision_id),
 chunk_order integer NOT NULL CHECK (chunk_order >= 0),
 chunk_text text NOT NULL,
 language_code text,
 source_locator text,
 checksum_sha256 text,
 UNIQUE (provision_id, chunk_order)
);
CREATE TABLE IF NOT EXISTS crosstax.evidence_conflicts (
 conflict_id text PRIMARY KEY,
 claim_a_id text NOT NULL REFERENCES crosstax.claims(claim_id),
 claim_b_id text NOT NULL REFERENCES crosstax.claims(claim_id),
 jurisdiction_id text REFERENCES crosstax.jurisdictions(id),
 issue_note text, resolution_status text NOT NULL DEFAULT 'unresolved',
 reviewed_at timestamptz,
 CHECK (claim_a_id <> claim_b_id)
);
CREATE TABLE IF NOT EXISTS crosstax.confidence_assessments (
 assessment_id text PRIMARY KEY,
 claim_id text NOT NULL REFERENCES crosstax.claims(claim_id),
 source_quality smallint NOT NULL CHECK (source_quality BETWEEN 0 AND 100),
 version_certainty smallint NOT NULL CHECK (version_certainty BETWEEN 0 AND 100),
 applicability_match smallint NOT NULL CHECK (applicability_match BETWEEN 0 AND 100),
 fact_completeness smallint NOT NULL CHECK (fact_completeness BETWEEN 0 AND 100),
 evidence_consistency smallint NOT NULL CHECK (evidence_consistency BETWEEN 0 AND 100),
 heuristic_score numeric(5,2) GENERATED ALWAYS AS (
 (25 * source_quality + 20 * version_certainty + 25 * applicability_match +
 20 * fact_completeness + 10 * evidence_consistency) / 100.0
 ) STORED,
 rationale jsonb NOT NULL DEFAULT '{}'::jsonb,
 assessed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_provisions_article_path ON crosstax.provisions(article_path);
CREATE INDEX IF NOT EXISTS ix_treaty_party ON crosstax.treaty_parties(jurisdiction_id,treaty_id);
CREATE INDEX IF NOT EXISTS ix_case_published ON crosstax.case_records(published_at,case_type);
CREATE INDEX IF NOT EXISTS ix_doc_jurisdiction ON crosstax.documents(jurisdiction_id,document_kind);
CREATE INDEX IF NOT EXISTS ix_applicability ON crosstax.applicability_windows(jurisdiction_id,tax_type,applies_from,applies_to);
CREATE INDEX IF NOT EXISTS ix_versions_temporal ON crosstax.document_versions(document_id,applies_from,applies_to);
CREATE INDEX IF NOT EXISTS ix_cases_jurisdiction ON crosstax.case_records(jurisdiction_id,published_at);
CREATE INDEX IF NOT EXISTS ix_chunks_fts ON crosstax.text_chunks USING GIN (to_tsvector('simple', chunk_text));
COMMIT;
