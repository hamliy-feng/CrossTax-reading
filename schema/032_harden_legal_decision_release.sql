-- 032: hardened legal/tax publication release checks (additive / reversible).
-- Prevents a historical treaty scan, statistical data, or a single "approved"
-- flag from being treated as a legally effective decision.
BEGIN;
CREATE OR REPLACE VIEW crosstax.v_unified_tax_answer_review_queue AS
SELECT p.package_id,p.payer_jurisdiction_id,p.recipient_jurisdiction_id,
       p.income_type,p.transaction_subtype,p.effective_from,p.effective_until,
       p.audit_status,p.evidence_sha256,p.qa_review_id,p.professional_case_id,
       p.created_at,p.updated_at,
       (SELECT count(*) FROM jsonb_array_elements(p.official_evidence) src
        WHERE length(coalesce(src->>'sha256',''))<>64) AS unarchived_evidence_items,
       NOT (
         p.legal_change_checks @> '{"all_treaty_amendments_verified":true,
            "counterparty_mli_positions_verified":true,
            "both_domestic_laws_verified":true,
            "tax_type_and_period_verified":true,
            "withholding_procedure_verified":true}'::jsonb
       ) AS missing_effective_law_checks,
       (SELECT count(*) FROM crosstax.qa_findings f
        WHERE f.object_type='unified_tax_answer_package'
          AND f.object_id=p.package_id
          AND f.disposition='open' AND f.severity IN ('critical','high')) AS blocking_qa_findings
FROM crosstax.unified_tax_answer_packages p;

CREATE OR REPLACE VIEW crosstax.v_unified_tax_answer_published AS
SELECT p.*, r.reviewer, r.reviewed_at AS legal_reviewed_at
FROM crosstax.unified_tax_answer_packages p
JOIN crosstax.qa_reviews r ON r.review_id=p.qa_review_id
JOIN crosstax.crossborder_professional_case_tests c ON c.case_id=p.professional_case_id
JOIN crosstax.v_unified_tax_answer_review_queue gate ON gate.package_id=p.package_id
WHERE p.audit_status='published'
  AND gate.unarchived_evidence_items=0
  AND gate.missing_effective_law_checks=false
  AND gate.blocking_qa_findings=0
  AND r.review_type='legal' AND r.decision='approved'
  AND r.target_type='unified_tax_answer_package'
  AND r.target_id=p.package_id
  AND r.evidence_locator=p.evidence_sha256
  AND c.verdict='pass' AND c.reference_review_id=r.review_id
  AND c.payer_jurisdiction_id=p.payer_jurisdiction_id
  AND c.recipient_jurisdiction_id=p.recipient_jurisdiction_id
  AND c.income_type=p.income_type
  AND c.transaction_date>=p.effective_from
  AND (p.effective_until IS NULL OR c.transaction_date<=p.effective_until)
  AND c.fact_pattern->>'transaction_subtype'=p.transaction_subtype
  AND jsonb_typeof(c.expert_expected_result)='object'
  AND c.expert_expected_result @> jsonb_build_object(
    'package_id',p.package_id,
    'evidence_sha256',p.evidence_sha256,
    'legal_and_tax_review_complete',true)
  AND NOT EXISTS(
    SELECT 1 FROM jsonb_array_elements_text(p.required_facts) required
    WHERE c.fact_pattern->>required.value IS DISTINCT FROM 'true'
  );
COMMIT;
