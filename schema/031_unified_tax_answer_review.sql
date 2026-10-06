-- CrossTax 031: single legal-and-tax review object; preserved legacy L1/L2/L3 views.
-- One decision packet covers authentic law, applicability, tax base, conditions,
-- amendments, computation, and dated review. Source observations remain separately searchable.
BEGIN;

CREATE TABLE IF NOT EXISTS crosstax.unified_tax_answer_packages (
  package_id text PRIMARY KEY,
  payer_jurisdiction_id text NOT NULL REFERENCES crosstax.jurisdictions(id),
  recipient_jurisdiction_id text NOT NULL REFERENCES crosstax.jurisdictions(id),
  income_type text NOT NULL CHECK (income_type IN ('DIVIDENDS','INTEREST','ROYALTIES','CIT','OTHER')),
  transaction_subtype text NOT NULL,
  treaty_id text REFERENCES crosstax.treaties(treaty_id),
  title text NOT NULL,
  effective_from date NOT NULL,
  effective_until date,
  nominal_rate numeric(12,6) NOT NULL CHECK(nominal_rate BETWEEN 0 AND 1),
  taxable_fraction numeric(12,6) NOT NULL DEFAULT 1 CHECK(taxable_fraction BETWEEN 0 AND 1),
  rate_basis text NOT NULL,
  required_facts jsonb NOT NULL,
  exceptions jsonb NOT NULL,
  official_evidence jsonb NOT NULL,
  evidence_sha256 text NOT NULL CHECK(length(evidence_sha256)=64),
  legal_change_checks jsonb NOT NULL,
  audit_status text NOT NULL DEFAULT 'evidence_compiled'
    CHECK(audit_status IN ('evidence_compiled','official_crosschecked','professionally_approved','published')),
  qa_review_id text REFERENCES crosstax.qa_reviews(review_id),
  professional_case_id text REFERENCES crosstax.crossborder_professional_case_tests(case_id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK(effective_until IS NULL OR effective_until>=effective_from),
  CHECK(jsonb_typeof(required_facts)='array'),
  CHECK(jsonb_typeof(exceptions)='array'),
  CHECK(jsonb_typeof(official_evidence)='array'),
  CHECK(jsonb_array_length(official_evidence)>=2),
  CHECK(jsonb_typeof(legal_change_checks)='object'),
  CHECK(audit_status NOT IN ('professionally_approved','published')
        OR (qa_review_id IS NOT NULL AND professional_case_id IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS ix_unified_tax_answer_lookup
 ON crosstax.unified_tax_answer_packages(payer_jurisdiction_id,recipient_jurisdiction_id,income_type,transaction_subtype,effective_from);

-- Serve source-backed research to the application with exact conditions and links.
-- Releasing a concrete assessed case adds ONE professional legal-and-tax review,
-- not two separate L2/L3 runs.
CREATE OR REPLACE VIEW crosstax.v_unified_tax_answer_evidence AS
SELECT p.package_id,p.payer_jurisdiction_id,p.recipient_jurisdiction_id,
       p.income_type,p.transaction_subtype,p.title,p.effective_from,p.effective_until,
       p.nominal_rate,p.taxable_fraction,p.rate_basis,p.required_facts,p.exceptions,
       p.official_evidence,p.legal_change_checks,p.evidence_sha256,p.audit_status,
       p.treaty_id
FROM crosstax.unified_tax_answer_packages p
WHERE p.audit_status IN ('official_crosschecked','professionally_approved','published');

-- Strictly gated, query-ready audited legal outcomes.
CREATE OR REPLACE VIEW crosstax.v_unified_tax_answer_published AS
SELECT p.*,r.reviewer,r.reviewed_at AS legal_reviewed_at
FROM crosstax.unified_tax_answer_packages p
JOIN crosstax.qa_reviews r ON r.review_id=p.qa_review_id
JOIN crosstax.crossborder_professional_case_tests c ON c.case_id=p.professional_case_id
WHERE p.audit_status='published'
  AND r.review_type='legal'
  AND r.decision='approved'
  AND r.target_type='unified_tax_answer_package'
  AND r.target_id=p.package_id
  AND r.evidence_locator=p.evidence_sha256
  AND c.verdict='pass'
  AND c.reference_review_id=r.review_id
  AND c.payer_jurisdiction_id=p.payer_jurisdiction_id
  AND c.recipient_jurisdiction_id=p.recipient_jurisdiction_id
  AND c.income_type=p.income_type
  AND c.transaction_date>=p.effective_from
  AND (p.effective_until IS NULL OR c.transaction_date<=p.effective_until)
  AND NOT EXISTS(
      SELECT 1 FROM crosstax.qa_findings f
      WHERE f.object_type='unified_tax_answer_package'
        AND f.object_id=p.package_id
        AND f.severity IN ('critical','high')
        AND f.disposition='open'
  );

-- All 2026 statistical observations can be inspected with original year, unit,
-- dimensions, row SHA, raw dataset locator and publisher; they never masquerade as statute.
CREATE OR REPLACE VIEW crosstax.v_oecd_2026_observation_evidence AS
SELECT o.dataset_id,o.record_number,o.reference_area,o.counterparty_area,o.observation_period,
       o.value_number,o.value_raw,o.dimensions->>'MEASURE' AS statistical_measure,
       o.dimensions->>'UNIT_MEASURE' AS statistical_unit,
       o.dimensions->>'TREATY_DATE' AS treaty_reference_year,
       o.source_row_sha256,o.verification_status,
       s.dataset_name,s.original_url AS dataset_source_url,s.local_locator,
       s.sha256 AS dataset_snapshot_sha256,s.provenance_note
FROM crosstax.oecd_2026_observations o
JOIN crosstax.research_dataset_snapshots s ON s.dataset_id=o.dataset_id;
COMMIT;
