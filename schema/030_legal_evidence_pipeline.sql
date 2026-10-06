-- CrossTax legal evidence pipeline, additive: legacy ingestion and QA views remain unchanged.
-- 030 | L1 machine candidate -> L2 verified citation -> L3 verified dated rule.
BEGIN;
CREATE TABLE IF NOT EXISTS crosstax.instrument_qa_profiles (
 document_id text PRIMARY KEY REFERENCES crosstax.documents(document_id),
 version_id text NOT NULL REFERENCES crosstax.document_versions(version_id),
 original_sha256 text NOT NULL,
 instrument_class text NOT NULL CHECK (instrument_class IN
   ('treaty_text','protocol','exchange_of_notes','mli_synthesized',
    'translation','annex','administrative_material','unknown')),
 classification_basis text NOT NULL,
 identified_signed_year integer CHECK (identified_signed_year BETWEEN 1800 AND 2200),
 directory_signed_years integer[] NOT NULL DEFAULT '{}'::integer[],
 version_identity_status text NOT NULL DEFAULT 'pending_review'
   CHECK (version_identity_status IN ('pending_review','conflicting_evidence','officially_verified')),
 boundary_status text NOT NULL DEFAULT 'not_reviewed'
   CHECK (boundary_status IN ('not_reviewed','machine_candidate','expert_verified')),
 qa_issues text[] NOT NULL DEFAULT '{}',
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (version_id)
);
CREATE TABLE IF NOT EXISTS crosstax.legal_article_candidates (
 candidate_id text PRIMARY KEY,
 version_id text NOT NULL REFERENCES crosstax.document_versions(version_id),
 source_provision_id text REFERENCES crosstax.provisions(provision_id),
 article_number text NOT NULL,
 body_text text NOT NULL,
 body_sha256 text NOT NULL CHECK (length(body_sha256)=64),
 source_file_sha256 text NOT NULL CHECK (length(source_file_sha256)=64),
 pdf_page_start integer NOT NULL CHECK (pdf_page_start>0),
 pdf_page_end integer NOT NULL CHECK (pdf_page_end>=pdf_page_start),
 signature_or_afterword text,
 extraction_method text NOT NULL,
 qa_issues text[] NOT NULL DEFAULT '{}',
 candidate_level text NOT NULL DEFAULT 'L1_machine'
  CHECK (candidate_level IN ('L1_machine','L1_technical_checked')),
 parsed_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(version_id,article_number)
);
CREATE INDEX IF NOT EXISTS idx_legal_article_candidates_ver ON crosstax.legal_article_candidates(version_id,article_number);
CREATE INDEX IF NOT EXISTS idx_legal_article_search ON crosstax.legal_article_candidates USING GIN (to_tsvector('simple',body_text));
CREATE TABLE IF NOT EXISTS crosstax.verified_tax_rules (
 rule_id text PRIMARY KEY,
 candidate_id text NOT NULL REFERENCES crosstax.legal_article_candidates(candidate_id),
 jurisdiction_id text NOT NULL REFERENCES crosstax.jurisdictions(id),
 tax_type text NOT NULL REFERENCES crosstax.tax_types(code),
 income_category text REFERENCES crosstax.income_categories(code),
 rule_type text NOT NULL,
 rate numeric(18,8),
 rate_unit text,
 taxable_base text,
 conditions jsonb NOT NULL DEFAULT '[]'::jsonb,
 exceptions jsonb NOT NULL DEFAULT '[]'::jsonb,
 applies_from date NOT NULL,
 applies_to date,
 proof_source_id text NOT NULL REFERENCES crosstax.sources(source_id),
 verified_by text NOT NULL CHECK (length(trim(verified_by))>0),
 verified_at timestamptz NOT NULL DEFAULT now(),
 CHECK (applies_to IS NULL OR applies_to>=applies_from)
);
-- L1 is traceable machine source text; not certified for current legal effect.
CREATE OR REPLACE VIEW crosstax.v_legal_text_l1 AS
 SELECT a.candidate_id,a.article_number,a.body_text,a.body_sha256,
        a.pdf_page_start,a.pdf_page_end,a.source_file_sha256,a.candidate_level,
        a.qa_issues,a.signature_or_afterword,
        v.version_id,v.content_locator,v.audit_status,
        d.document_id,d.official_title,d.document_kind,d.source_id,d.signed_at,
        t.treaty_id,p.jurisdiction_id AS partner_code,
        i.instrument_class,i.version_identity_status,i.identified_signed_year,i.directory_signed_years
 FROM crosstax.legal_article_candidates a
 JOIN crosstax.document_versions v ON v.version_id=a.version_id
 JOIN crosstax.documents d ON d.document_id=v.document_id
 JOIN crosstax.instrument_qa_profiles i ON i.version_id=a.version_id
 LEFT JOIN crosstax.treaty_instruments t ON t.document_id=d.document_id
 LEFT JOIN crosstax.treaty_parties p ON p.treaty_id=t.treaty_id AND p.jurisdiction_id<>'CN'
 WHERE v.source_sha256=a.source_file_sha256;
-- L2 requires verified official identity + verified citation boundary + explicit legal review
-- recorded for this exact body hash. Machine agreement alone never upgrades.
CREATE OR REPLACE VIEW crosstax.v_legal_citation_l2 AS
 SELECT x.*,
   r.reviewer AS reviewing_person,r.reviewed_at AS legal_review_at
 FROM crosstax.v_legal_text_l1 x
 JOIN crosstax.instrument_qa_profiles i ON i.version_id=x.version_id
 JOIN crosstax.qa_reviews r ON r.target_type='legal_article_candidate'
   AND r.target_id=x.candidate_id AND r.review_type='legal' AND r.decision='approved'
   AND r.evidence_locator=x.body_sha256
 WHERE i.version_identity_status='officially_verified'
  AND i.boundary_status='expert_verified'
  AND NOT EXISTS(SELECT 1 FROM crosstax.qa_findings f
      WHERE f.disposition='open' AND f.severity IN ('high','critical')
        AND ((f.object_type='provision' AND f.object_id=
            (SELECT a.source_provision_id FROM crosstax.legal_article_candidates a
              WHERE a.candidate_id=x.candidate_id))
          OR (f.object_type='legal_article_candidate' AND f.object_id=x.candidate_id)));
-- L3 is an explicit rule with verified conditions and dated applicability,
-- AND its supporting source must be legally reviewed/citable at L2.
CREATE OR REPLACE VIEW crosstax.v_legal_rule_l3 AS
 SELECT r.*,l.article_number,l.body_sha256,l.official_title,l.content_locator,
        l.legal_review_at,l.version_id
 FROM crosstax.verified_tax_rules r
 JOIN crosstax.v_legal_citation_l2 l ON l.candidate_id=r.candidate_id;
COMMIT;
