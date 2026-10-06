--
-- PostgreSQL database dump
--

\restrict bKgAB1tZ6eSYILck9zwLdtPfOzqOmebk82fms7M12pTHOx4JH334Sz1lQyPs7sl

-- Dumped from database version 16.14
-- Dumped by pg_dump version 16.14

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: crosstax; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA crosstax;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: applicability_windows; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.applicability_windows (
    window_id text NOT NULL,
    document_version_id text NOT NULL,
    jurisdiction_id text,
    tax_type text,
    income_category text,
    party_side text,
    applies_from date,
    applies_to date,
    proof_source_id text,
    status text DEFAULT 'unreviewed'::text NOT NULL
);


--
-- Name: case_provision_links; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.case_provision_links (
    case_id text NOT NULL,
    provision_id text NOT NULL,
    link_kind text NOT NULL,
    reviewed_by text,
    CONSTRAINT case_provision_links_link_kind_check CHECK ((link_kind = ANY (ARRAY['cites'::text, 'applies'::text, 'distinguishes'::text, 'overrules'::text, 'background'::text])))
);


--
-- Name: case_records; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.case_records (
    case_id text NOT NULL,
    case_name text NOT NULL,
    jurisdiction_id text,
    published_at date,
    occurred_at date,
    source_id text NOT NULL,
    case_type text NOT NULL,
    issue_tags text[] DEFAULT '{}'::text[] NOT NULL,
    legal_status text DEFAULT 'not_established'::text NOT NULL,
    summary text,
    original_case_number text,
    professional_review_status text DEFAULT 'unreviewed'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT case_records_case_type_check CHECK ((case_type = ANY (ARRAY['court_judgment'::text, 'administrative_decision'::text, 'tax_authority_notice'::text, 'company_disclosure'::text, 'pre_ruling'::text, 'other'::text])))
);


--
-- Name: claim_evidence; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.claim_evidence (
    claim_id text NOT NULL,
    provision_id text,
    source_id text,
    evidence_relation text NOT NULL,
    verified_at timestamp with time zone,
    reviewer text,
    evidence_text_locator text,
    evidence_level smallint,
    CONSTRAINT claim_evidence_check CHECK (((provision_id IS NOT NULL) OR (source_id IS NOT NULL))),
    CONSTRAINT claim_evidence_evidence_level_check CHECK (((evidence_level >= 0) AND (evidence_level <= 5))),
    CONSTRAINT claim_evidence_evidence_relation_check CHECK ((evidence_relation = ANY (ARRAY['supports'::text, 'contradicts'::text, 'contextualizes'::text])))
);


--
-- Name: claims; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.claims (
    claim_id text NOT NULL,
    text_zh text NOT NULL,
    jurisdiction_id text,
    facts_snapshot_id text,
    asserted_at timestamp with time zone DEFAULT now(),
    status text DEFAULT 'unverified'::text NOT NULL
);


--
-- Name: confidence_assessments; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.confidence_assessments (
    assessment_id text NOT NULL,
    claim_id text NOT NULL,
    source_quality smallint NOT NULL,
    version_certainty smallint NOT NULL,
    applicability_match smallint NOT NULL,
    fact_completeness smallint NOT NULL,
    evidence_consistency smallint NOT NULL,
    heuristic_score numeric(5,2) GENERATED ALWAYS AS ((((((((25 * source_quality) + (20 * version_certainty)) + (25 * applicability_match)) + (20 * fact_completeness)) + (10 * evidence_consistency)))::numeric / 100.0)) STORED,
    rationale jsonb DEFAULT '{}'::jsonb NOT NULL,
    assessed_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT confidence_assessments_applicability_match_check CHECK (((applicability_match >= 0) AND (applicability_match <= 100))),
    CONSTRAINT confidence_assessments_evidence_consistency_check CHECK (((evidence_consistency >= 0) AND (evidence_consistency <= 100))),
    CONSTRAINT confidence_assessments_fact_completeness_check CHECK (((fact_completeness >= 0) AND (fact_completeness <= 100))),
    CONSTRAINT confidence_assessments_source_quality_check CHECK (((source_quality >= 0) AND (source_quality <= 100))),
    CONSTRAINT confidence_assessments_version_certainty_check CHECK (((version_certainty >= 0) AND (version_certainty <= 100)))
);


--
-- Name: country_registry_page_snapshots; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.country_registry_page_snapshots (
    treaty_id text NOT NULL,
    source_url text NOT NULL,
    source_page_sha256 text,
    local_html_locator text,
    attachment_links_found integer DEFAULT 0 NOT NULL,
    checked_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT country_registry_page_snapshots_attachment_links_found_check CHECK ((attachment_links_found >= 0)),
    CONSTRAINT country_registry_page_snapshots_check CHECK ((((source_page_sha256 IS NULL) AND (local_html_locator IS NULL)) OR ((source_page_sha256 IS NOT NULL) AND (local_html_locator IS NOT NULL))))
);


--
-- Name: coverage_register; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.coverage_register (
    jurisdiction_id text NOT NULL,
    tax_type text NOT NULL,
    income_category text DEFAULT 'general'::text NOT NULL,
    from_year integer NOT NULL,
    to_year integer NOT NULL,
    official_sources_count integer DEFAULT 0 NOT NULL,
    provisions_reviewed_count integer DEFAULT 0 NOT NULL,
    reviewed_rule_count integer DEFAULT 0 NOT NULL,
    missing_materials jsonb DEFAULT '[]'::jsonb NOT NULL,
    last_checked_at timestamp with time zone,
    CONSTRAINT coverage_register_check CHECK ((to_year >= from_year))
);


--
-- Name: crossborder_professional_case_tests; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.crossborder_professional_case_tests (
    case_id text NOT NULL,
    title text NOT NULL,
    payer_jurisdiction_id text NOT NULL,
    recipient_jurisdiction_id text NOT NULL,
    income_type text NOT NULL,
    transaction_date date NOT NULL,
    fact_pattern jsonb NOT NULL,
    expert_expected_result jsonb,
    reference_review_id text,
    verdict text DEFAULT 'pending_professional_review'::text NOT NULL,
    evaluated_at timestamp with time zone,
    CONSTRAINT crossborder_professional_case_tests_check CHECK (((verdict = 'pending_professional_review'::text) OR ((expert_expected_result IS NOT NULL) AND (reference_review_id IS NOT NULL)))),
    CONSTRAINT crossborder_professional_case_tests_check1 CHECK (((payer_jurisdiction_id = 'CN'::text) OR (recipient_jurisdiction_id = 'CN'::text))),
    CONSTRAINT crossborder_professional_case_tests_income_type_check CHECK ((income_type = ANY (ARRAY['DIVIDENDS'::text, 'INTEREST'::text, 'ROYALTIES'::text]))),
    CONSTRAINT crossborder_professional_case_tests_verdict_check CHECK ((verdict = ANY (ARRAY['pending_professional_review'::text, 'expert_adjudicated'::text, 'pass'::text, 'fail'::text])))
);


--
-- Name: crossborder_tax_rule_candidates; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.crossborder_tax_rule_candidates (
    rule_id text NOT NULL,
    payer_jurisdiction_id text NOT NULL,
    recipient_jurisdiction_id text NOT NULL,
    income_type text NOT NULL,
    rule_kind text NOT NULL,
    rate_percent numeric(8,4),
    source_provision_id text,
    version_id text,
    applicability_from date,
    applicability_to date,
    condition_details jsonb DEFAULT '{}'::jsonb NOT NULL,
    professional_review_id text,
    review_status text DEFAULT 'candidate_unreviewed'::text NOT NULL,
    inserted_at timestamp with time zone DEFAULT now(),
    CONSTRAINT crossborder_tax_rule_candidates_check CHECK (((review_status = 'candidate_unreviewed'::text) OR ((source_provision_id IS NOT NULL) AND (version_id IS NOT NULL) AND (applicability_from IS NOT NULL) AND (professional_review_id IS NOT NULL)))),
    CONSTRAINT crossborder_tax_rule_candidates_check1 CHECK (((applicability_to IS NULL) OR (applicability_from IS NULL) OR (applicability_to >= applicability_from))),
    CONSTRAINT crossborder_tax_rule_candidates_income_type_check CHECK ((income_type = ANY (ARRAY['DIVIDENDS'::text, 'INTEREST'::text, 'ROYALTIES'::text]))),
    CONSTRAINT crossborder_tax_rule_candidates_rate_percent_check CHECK (((rate_percent >= (0)::numeric) AND (rate_percent <= (100)::numeric))),
    CONSTRAINT crossborder_tax_rule_candidates_review_status_check CHECK ((review_status = ANY (ARRAY['candidate_unreviewed'::text, 'legal_reviewed_pending_tests'::text, 'case_tested_released'::text]))),
    CONSTRAINT crossborder_tax_rule_candidates_rule_kind_check CHECK ((rule_kind = ANY (ARRAY['DOMESTIC'::text, 'TREATY_LIMIT'::text, 'EXEMPTION'::text, 'PROCEDURE'::text])))
);


--
-- Name: document_versions; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.document_versions (
    version_id text NOT NULL,
    document_id text NOT NULL,
    version_label text NOT NULL,
    source_sha256 text,
    retrieved_at timestamp with time zone,
    entered_into_force_at date,
    applies_from date,
    applies_to date,
    law_valid_from date,
    law_valid_to date,
    ingested_at timestamp with time zone DEFAULT now(),
    audit_status text DEFAULT 'unreviewed'::text NOT NULL,
    content_locator text
);


--
-- Name: documents; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.documents (
    document_id text NOT NULL,
    document_kind text NOT NULL,
    official_title text NOT NULL,
    issuing_body text,
    jurisdiction_id text,
    source_id text,
    original_language text,
    original_url text,
    published_at date,
    signed_at date,
    status text DEFAULT 'candidate'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT documents_status_check CHECK ((status = ANY (ARRAY['candidate'::text, 'source_verified'::text, 'professional_reviewed'::text, 'withdrawn'::text])))
);


--
-- Name: domestic_law_topic_links; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.domestic_law_topic_links (
    document_id text NOT NULL,
    tax_type text NOT NULL,
    research_topic text NOT NULL,
    scope_status text DEFAULT 'document_relevance_machine_or_research_reviewed_not_legal_rules'::text NOT NULL
);


--
-- Name: evidence_conflicts; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.evidence_conflicts (
    conflict_id text NOT NULL,
    claim_a_id text NOT NULL,
    claim_b_id text NOT NULL,
    jurisdiction_id text,
    issue_note text,
    resolution_status text DEFAULT 'unresolved'::text NOT NULL,
    reviewed_at timestamp with time zone,
    CONSTRAINT evidence_conflicts_check CHECK ((claim_a_id <> claim_b_id))
);


--
-- Name: global_tax_collection_matrix; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.global_tax_collection_matrix (
    jurisdiction_id text NOT NULL,
    tax_type text NOT NULL,
    research_topic text NOT NULL,
    latest_candidate_year integer,
    official_law_document_id text,
    reviewed_rule_count integer DEFAULT 0 NOT NULL,
    collection_status text DEFAULT 'not_collected'::text NOT NULL,
    checked_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT global_tax_collection_matrix_reviewed_rule_count_check CHECK ((reviewed_rule_count >= 0))
);


--
-- Name: income_categories; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.income_categories (
    code text NOT NULL,
    name_en text NOT NULL,
    name_zh text,
    description text
);


--
-- Name: ingestion_tasks; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.ingestion_tasks (
    task_id text NOT NULL,
    source_id text NOT NULL,
    document_id text,
    stage text DEFAULT 'discovered'::text NOT NULL,
    status text DEFAULT 'queued'::text NOT NULL,
    assigned_to text,
    log_note text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: instrument_qa_profiles; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.instrument_qa_profiles (
    document_id text NOT NULL,
    version_id text NOT NULL,
    original_sha256 text NOT NULL,
    instrument_class text NOT NULL,
    classification_basis text NOT NULL,
    identified_signed_year integer,
    directory_signed_years integer[] DEFAULT '{}'::integer[] NOT NULL,
    version_identity_status text DEFAULT 'pending_review'::text NOT NULL,
    boundary_status text DEFAULT 'not_reviewed'::text NOT NULL,
    qa_issues text[] DEFAULT '{}'::text[] NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT instrument_qa_profiles_boundary_status_check CHECK ((boundary_status = ANY (ARRAY['not_reviewed'::text, 'machine_candidate'::text, 'expert_verified'::text]))),
    CONSTRAINT instrument_qa_profiles_identified_signed_year_check CHECK (((identified_signed_year >= 1800) AND (identified_signed_year <= 2200))),
    CONSTRAINT instrument_qa_profiles_instrument_class_check CHECK ((instrument_class = ANY (ARRAY['treaty_text'::text, 'protocol'::text, 'exchange_of_notes'::text, 'mli_synthesized'::text, 'translation'::text, 'annex'::text, 'administrative_material'::text, 'unknown'::text]))),
    CONSTRAINT instrument_qa_profiles_version_identity_status_check CHECK ((version_identity_status = ANY (ARRAY['pending_review'::text, 'conflicting_evidence'::text, 'officially_verified'::text])))
);


--
-- Name: international_organizations; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.international_organizations (
    org_id text NOT NULL,
    name_zh text NOT NULL,
    name_en text NOT NULL,
    org_kind text NOT NULL,
    parent_org_id text,
    official_url text,
    scope_note text
);


--
-- Name: jurisdictions; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.jurisdictions (
    id text NOT NULL,
    name_zh text,
    name_en text NOT NULL,
    kind text DEFAULT 'country'::text NOT NULL,
    parent_id text,
    iso_code text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: legal_article_candidates; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.legal_article_candidates (
    candidate_id text NOT NULL,
    version_id text NOT NULL,
    source_provision_id text,
    article_number text NOT NULL,
    body_text text NOT NULL,
    body_sha256 text NOT NULL,
    source_file_sha256 text NOT NULL,
    pdf_page_start integer NOT NULL,
    pdf_page_end integer NOT NULL,
    signature_or_afterword text,
    extraction_method text NOT NULL,
    qa_issues text[] DEFAULT '{}'::text[] NOT NULL,
    candidate_level text DEFAULT 'L1_machine'::text NOT NULL,
    parsed_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT legal_article_candidates_body_sha256_check CHECK ((length(body_sha256) = 64)),
    CONSTRAINT legal_article_candidates_candidate_level_check CHECK ((candidate_level = ANY (ARRAY['L1_machine'::text, 'L1_technical_checked'::text]))),
    CONSTRAINT legal_article_candidates_check CHECK ((pdf_page_end >= pdf_page_start)),
    CONSTRAINT legal_article_candidates_pdf_page_start_check CHECK ((pdf_page_start > 0)),
    CONSTRAINT legal_article_candidates_source_file_sha256_check CHECK ((length(source_file_sha256) = 64))
);


--
-- Name: oecd_2026_observations; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.oecd_2026_observations (
    dataset_id text NOT NULL,
    record_number integer NOT NULL,
    reference_area text,
    counterparty_area text,
    observation_period text NOT NULL,
    value_raw text,
    value_number numeric,
    dimensions jsonb NOT NULL,
    source_row_sha256 text NOT NULL,
    verification_status text DEFAULT 'official_statistical_observation_unverified_law'::text NOT NULL,
    CONSTRAINT oecd_2026_observations_observation_period_check CHECK ((observation_period = '2026'::text)),
    CONSTRAINT oecd_2026_observations_record_number_check CHECK ((record_number > 0)),
    CONSTRAINT oecd_2026_observations_source_row_sha256_check CHECK ((length(source_row_sha256) = 64))
);


--
-- Name: oecd_country_iso_crosswalk; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.oecd_country_iso_crosswalk (
    oecd_ref_area text NOT NULL,
    jurisdiction_id text NOT NULL,
    derived_from_sha256 text NOT NULL,
    source_class text NOT NULL,
    CONSTRAINT oecd_country_iso_crosswalk_derived_from_sha256_check CHECK ((length(derived_from_sha256) = 64)),
    CONSTRAINT oecd_country_iso_crosswalk_oecd_ref_area_check CHECK ((length(oecd_ref_area) = 3))
);


--
-- Name: provisions; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.provisions (
    provision_id text NOT NULL,
    version_id text NOT NULL,
    article_path text NOT NULL,
    original_text text,
    original_language text,
    page_num integer,
    source_locator text,
    checksum_sha256 text,
    review_status text DEFAULT 'unreviewed'::text NOT NULL
);


--
-- Name: qa_findings; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.qa_findings (
    finding_id text NOT NULL,
    run_id text NOT NULL,
    check_code text NOT NULL,
    object_type text NOT NULL,
    object_id text NOT NULL,
    severity text NOT NULL,
    description text NOT NULL,
    evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
    disposition text DEFAULT 'open'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT qa_findings_disposition_check CHECK ((disposition = ANY (ARRAY['open'::text, 'fixed'::text, 'false_positive'::text, 'accepted_limitation'::text]))),
    CONSTRAINT qa_findings_severity_check CHECK ((severity = ANY (ARRAY['critical'::text, 'high'::text, 'medium'::text, 'low'::text, 'info'::text])))
);


--
-- Name: qa_reviews; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.qa_reviews (
    review_id text NOT NULL,
    target_type text NOT NULL,
    target_id text NOT NULL,
    run_id text,
    review_type text NOT NULL,
    reviewer text NOT NULL,
    decision text NOT NULL,
    rationale text NOT NULL,
    evidence_locator text,
    reviewed_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT qa_reviews_review_type_check CHECK ((review_type = ANY (ARRAY['technical'::text, 'legal'::text])))
);


--
-- Name: qa_runs; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.qa_runs (
    run_id text NOT NULL,
    scope text NOT NULL,
    script_version text NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    run_status text DEFAULT 'running'::text NOT NULL,
    summary jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT qa_runs_run_status_check CHECK ((run_status = ANY (ARRAY['running'::text, 'completed'::text, 'failed'::text])))
);


--
-- Name: research_dataset_snapshots; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.research_dataset_snapshots (
    dataset_id text NOT NULL,
    publisher text NOT NULL,
    dataset_name text NOT NULL,
    published_year integer,
    original_url text NOT NULL,
    local_locator text NOT NULL,
    sha256 text NOT NULL,
    retrieved_at timestamp with time zone DEFAULT now() NOT NULL,
    provenance_note text NOT NULL,
    CONSTRAINT research_dataset_snapshots_sha256_check CHECK ((length(sha256) = 64))
);


--
-- Name: research_document_chunks; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.research_document_chunks (
    chunk_id text NOT NULL,
    version_id text NOT NULL,
    page_num integer NOT NULL,
    part_no integer NOT NULL,
    chunk_text text NOT NULL,
    original_sha256 text NOT NULL,
    chunk_sha256 text NOT NULL,
    source_locator text NOT NULL,
    extraction_status text DEFAULT 'machine_extracted_secondary_unreviewed'::text NOT NULL,
    CONSTRAINT research_document_chunks_chunk_sha256_check CHECK ((length(chunk_sha256) = 64)),
    CONSTRAINT research_document_chunks_original_sha256_check CHECK ((length(original_sha256) = 64)),
    CONSTRAINT research_document_chunks_page_num_check CHECK ((page_num >= 1)),
    CONSTRAINT research_document_chunks_part_no_check CHECK ((part_no >= 1))
);


--
-- Name: source_organization_links; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.source_organization_links (
    source_id text NOT NULL,
    org_id text NOT NULL,
    relation_kind text DEFAULT 'publisher'::text NOT NULL
);


--
-- Name: sources; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.sources (
    source_id text NOT NULL,
    publisher text NOT NULL,
    publisher_kind text NOT NULL,
    title text NOT NULL,
    source_url text NOT NULL,
    country_id text,
    source_category text NOT NULL,
    discovered_at date DEFAULT CURRENT_DATE NOT NULL,
    authority_level smallint DEFAULT 0 NOT NULL,
    source_note text,
    CONSTRAINT sources_authority_level_check CHECK (((authority_level >= 0) AND (authority_level <= 5)))
);


--
-- Name: sta_treaty_registry_entries; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.sta_treaty_registry_entries (
    entry_id text NOT NULL,
    treaty_id text NOT NULL,
    official_listing_url text NOT NULL,
    listing_sha256 text NOT NULL,
    registry_serial integer NOT NULL,
    historical_listing_row boolean DEFAULT false NOT NULL,
    registry_name text NOT NULL,
    signed_at date,
    entered_into_force_at date,
    force_at_original text NOT NULL,
    applicability_original text,
    detail_url text,
    recorded_at timestamp with time zone DEFAULT now(),
    CONSTRAINT sta_treaty_registry_entries_registry_serial_check CHECK (((registry_serial >= 1) AND (registry_serial <= 111)))
);


--
-- Name: tax_rate_candidates; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.tax_rate_candidates (
    candidate_id text NOT NULL,
    dataset_id text NOT NULL,
    jurisdiction_id text NOT NULL,
    tax_type text NOT NULL,
    metric_code text NOT NULL,
    observation_year integer NOT NULL,
    nominal_rate_percent numeric(12,5) NOT NULL,
    source_row text NOT NULL,
    source_content_sha256 text NOT NULL,
    review_status text DEFAULT 'secondary_research_unverified'::text NOT NULL,
    official_provision_id text,
    inserted_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tax_rate_candidates_check CHECK (((review_status <> 'professionally_reviewed'::text) OR (official_provision_id IS NOT NULL))),
    CONSTRAINT tax_rate_candidates_nominal_rate_percent_check CHECK (((nominal_rate_percent >= (0)::numeric) AND (nominal_rate_percent <= (100)::numeric))),
    CONSTRAINT tax_rate_candidates_observation_year_check CHECK (((observation_year >= 1800) AND (observation_year <= 2200)))
);


--
-- Name: tax_types; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.tax_types (
    code text NOT NULL,
    name_zh text NOT NULL,
    description text
);


--
-- Name: text_chunks; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.text_chunks (
    chunk_id text NOT NULL,
    provision_id text NOT NULL,
    chunk_order integer NOT NULL,
    chunk_text text NOT NULL,
    language_code text,
    source_locator text,
    checksum_sha256 text,
    CONSTRAINT text_chunks_chunk_order_check CHECK ((chunk_order >= 0))
);


--
-- Name: treaties; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.treaties (
    treaty_id text NOT NULL,
    title text NOT NULL,
    source_document_id text,
    treaty_type text DEFAULT 'DTA'::text NOT NULL,
    signed_at date,
    entered_into_force_at date,
    current_status text DEFAULT 'unverified'::text NOT NULL
);


--
-- Name: treaty_changes; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.treaty_changes (
    change_id text NOT NULL,
    treaty_id text NOT NULL,
    instrument_document_id text,
    change_kind text NOT NULL,
    position_a jsonb,
    position_b jsonb,
    change_summary text,
    signed_at date,
    entered_into_force_at date,
    applies_from date,
    confirmed_status text DEFAULT 'unverified'::text NOT NULL,
    CONSTRAINT treaty_changes_change_kind_check CHECK ((change_kind = ANY (ARRAY['protocol'::text, 'MLI'::text, 'replacement'::text, 'termination'::text, 'other'::text])))
);


--
-- Name: treaty_instruments; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.treaty_instruments (
    treaty_id text NOT NULL,
    document_id text NOT NULL,
    instrument_kind text NOT NULL,
    registry_country_page text NOT NULL,
    discovered_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: treaty_parties; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.treaty_parties (
    treaty_id text NOT NULL,
    jurisdiction_id text NOT NULL,
    party_role text DEFAULT 'party'::text NOT NULL
);


--
-- Name: unified_tax_answer_packages; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.unified_tax_answer_packages (
    package_id text NOT NULL,
    payer_jurisdiction_id text NOT NULL,
    recipient_jurisdiction_id text NOT NULL,
    income_type text NOT NULL,
    transaction_subtype text NOT NULL,
    treaty_id text,
    title text NOT NULL,
    effective_from date NOT NULL,
    effective_until date,
    nominal_rate numeric(12,6) NOT NULL,
    taxable_fraction numeric(12,6) DEFAULT 1 NOT NULL,
    rate_basis text NOT NULL,
    required_facts jsonb NOT NULL,
    exceptions jsonb NOT NULL,
    official_evidence jsonb NOT NULL,
    evidence_sha256 text NOT NULL,
    legal_change_checks jsonb NOT NULL,
    audit_status text DEFAULT 'evidence_compiled'::text NOT NULL,
    qa_review_id text,
    professional_case_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT unified_tax_answer_packages_audit_status_check CHECK ((audit_status = ANY (ARRAY['evidence_compiled'::text, 'official_crosschecked'::text, 'professionally_approved'::text, 'published'::text]))),
    CONSTRAINT unified_tax_answer_packages_check CHECK (((effective_until IS NULL) OR (effective_until >= effective_from))),
    CONSTRAINT unified_tax_answer_packages_check1 CHECK (((audit_status <> ALL (ARRAY['professionally_approved'::text, 'published'::text])) OR ((qa_review_id IS NOT NULL) AND (professional_case_id IS NOT NULL)))),
    CONSTRAINT unified_tax_answer_packages_evidence_sha256_check CHECK ((length(evidence_sha256) = 64)),
    CONSTRAINT unified_tax_answer_packages_exceptions_check CHECK ((jsonb_typeof(exceptions) = 'array'::text)),
    CONSTRAINT unified_tax_answer_packages_income_type_check CHECK ((income_type = ANY (ARRAY['DIVIDENDS'::text, 'INTEREST'::text, 'ROYALTIES'::text, 'CIT'::text, 'OTHER'::text]))),
    CONSTRAINT unified_tax_answer_packages_legal_change_checks_check CHECK ((jsonb_typeof(legal_change_checks) = 'object'::text)),
    CONSTRAINT unified_tax_answer_packages_nominal_rate_check CHECK (((nominal_rate >= (0)::numeric) AND (nominal_rate <= (1)::numeric))),
    CONSTRAINT unified_tax_answer_packages_official_evidence_check CHECK ((jsonb_typeof(official_evidence) = 'array'::text)),
    CONSTRAINT unified_tax_answer_packages_official_evidence_check1 CHECK ((jsonb_array_length(official_evidence) >= 2)),
    CONSTRAINT unified_tax_answer_packages_required_facts_check CHECK ((jsonb_typeof(required_facts) = 'array'::text)),
    CONSTRAINT unified_tax_answer_packages_taxable_fraction_check CHECK (((taxable_fraction >= (0)::numeric) AND (taxable_fraction <= (1)::numeric)))
);


--
-- Name: v_china_treaty_evidence_coverage; Type: VIEW; Schema: crosstax; Owner: -
--

CREATE VIEW crosstax.v_china_treaty_evidence_coverage AS
 SELECT t.treaty_id,
    tp.jurisdiction_id AS partner_id,
    j.name_zh AS partner_name_zh,
    j.name_en AS partner_name_en,
    t.current_status AS treaty_relationship_status,
    count(DISTINCT ti.document_id) AS archived_pdf_documents,
    count(DISTINCT ti.document_id) FILTER (WHERE (ti.instrument_kind = 'treaty_text_candidate'::text)) AS archived_treaty_text_candidates,
    count(DISTINCT ti.document_id) FILTER (WHERE (ti.instrument_kind = 'protocol'::text)) AS archived_protocol_candidates,
    count(DISTINCT ti.document_id) FILTER (WHERE (ti.instrument_kind = 'mli_synthesised_or_consolidated'::text)) AS archived_mli_synthesised_candidates,
    count(DISTINCT pr.provision_id) FILTER (WHERE (pr.review_status = 'machine_extracted_unreviewed'::text)) AS machine_extracted_articles,
    count(DISTINCT pr.provision_id) FILTER (WHERE (pr.review_status = 'professionally_reviewed'::text)) AS professionally_reviewed_articles,
        CASE
            WHEN (count(DISTINCT pr.provision_id) FILTER (WHERE (pr.review_status = 'professionally_reviewed'::text)) > 0) THEN 'partial_professional_review'::text
            WHEN (count(DISTINCT pr.provision_id) FILTER (WHERE (pr.review_status = 'machine_extracted_unreviewed'::text)) > 0) THEN 'machine_extracted_unreviewed'::text
            WHEN (count(DISTINCT ti.document_id) > 0) THEN 'raw_pdf_archived'::text
            ELSE 'directory_only'::text
        END AS verifiable_stage
   FROM (((((crosstax.treaties t
     JOIN crosstax.treaty_parties tp ON (((tp.treaty_id = t.treaty_id) AND (tp.jurisdiction_id <> 'CN'::text))))
     JOIN crosstax.jurisdictions j ON ((j.id = tp.jurisdiction_id)))
     LEFT JOIN crosstax.treaty_instruments ti ON ((ti.treaty_id = t.treaty_id)))
     LEFT JOIN crosstax.document_versions dv ON (((dv.document_id = ti.document_id) AND (dv.source_sha256 IS NOT NULL))))
     LEFT JOIN crosstax.provisions pr ON ((pr.version_id = dv.version_id)))
  WHERE (t.treaty_type = 'DTA'::text)
  GROUP BY t.treaty_id, tp.jurisdiction_id, j.name_zh, j.name_en, t.current_status;


--
-- Name: v_provision_release_gate; Type: VIEW; Schema: crosstax; Owner: -
--

CREATE VIEW crosstax.v_provision_release_gate AS
 SELECT p.provision_id,
    p.version_id,
    p.article_path,
    p.review_status,
    d.document_kind,
    v.audit_status,
    (EXISTS ( SELECT 1
           FROM crosstax.qa_findings f
          WHERE ((f.object_type = 'provision'::text) AND (f.object_id = p.provision_id) AND (f.disposition = 'open'::text) AND (f.severity = ANY (ARRAY['critical'::text, 'high'::text]))))) AS has_blocking_quality_finding,
    (EXISTS ( SELECT 1
           FROM crosstax.qa_reviews r
          WHERE ((r.target_type = 'provision'::text) AND (r.target_id = p.provision_id) AND (r.review_type = 'legal'::text) AND (r.decision = 'approved'::text) AND (r.evidence_locator = p.checksum_sha256)))) AS attested_legal_review,
    ((p.review_status = 'professionally_reviewed'::text) AND (EXISTS ( SELECT 1
           FROM crosstax.qa_reviews r
          WHERE ((r.target_type = 'provision'::text) AND (r.target_id = p.provision_id) AND (r.review_type = 'legal'::text) AND (r.decision = 'approved'::text) AND (r.evidence_locator = p.checksum_sha256)))) AND (NOT (EXISTS ( SELECT 1
           FROM crosstax.qa_findings f
          WHERE ((f.object_type = 'provision'::text) AND (f.object_id = p.provision_id) AND (f.disposition = 'open'::text) AND (f.severity = ANY (ARRAY['critical'::text, 'high'::text])))))) AND (v.source_sha256 IS NOT NULL)) AS legal_content_release_eligible
   FROM ((crosstax.provisions p
     JOIN crosstax.document_versions v ON ((v.version_id = p.version_id)))
     JOIN crosstax.documents d ON ((d.document_id = v.document_id)));


--
-- Name: v_china_crossborder_practical_scenarios; Type: VIEW; Schema: crosstax; Owner: -
--

CREATE VIEW crosstax.v_china_crossborder_practical_scenarios AS
 SELECT v.treaty_id,
    v.partner_id,
    v.partner_name_zh,
        CASE
            WHEN (di.direction = 'CN_TO_PARTNER'::text) THEN 'CN'::text
            ELSE v.partner_id
        END AS payer_jurisdiction_id,
        CASE
            WHEN (di.direction = 'CN_TO_PARTNER'::text) THEN v.partner_id
            ELSE 'CN'::text
        END AS recipient_jurisdiction_id,
    di.direction,
    ic.income_type,
    ic.expected_article,
    v.treaty_relationship_status,
    v.archived_pdf_documents,
    v.archived_treaty_text_candidates,
    v.archived_protocol_candidates,
    v.archived_mli_synthesised_candidates,
    COALESCE(articles.article_candidate_count, (0)::bigint) AS income_treaty_article_candidates,
    COALESCE(articles.legally_released_article_count, (0)::bigint) AS released_treaty_article_count,
    COALESCE(rls.released_rules, (0)::bigint) AS released_rules,
    ((COALESCE(rls.released_rules, (0)::bigint) > 0) AND (COALESCE(articles.legally_released_article_count, (0)::bigint) > 0)) AS legal_rules_available,
        CASE
            WHEN ((COALESCE(rls.released_rules, (0)::bigint) > 0) AND (COALESCE(articles.legally_released_article_count, (0)::bigint) > 0)) THEN 'legal_evidence_ready_for_fact_sensitive_case_tests'::text
            WHEN (v.archived_pdf_documents > 0) THEN 'official_treaty_pdf_downloaded_but_application_unverified'::text
            ELSE 'official_treaty_raw_document_missing'::text
        END AS actual_status
   FROM ((((crosstax.v_china_treaty_evidence_coverage v
     CROSS JOIN ( VALUES ('CN_TO_PARTNER'::text), ('PARTNER_TO_CN'::text)) di(direction))
     CROSS JOIN ( VALUES ('DIVIDENDS'::text,'Article 10'::text), ('INTEREST'::text,'Article 11'::text), ('ROYALTIES'::text,'Article 12'::text)) ic(income_type, expected_article))
     LEFT JOIN LATERAL ( SELECT count(DISTINCT p.provision_id) AS article_candidate_count,
            count(DISTINCT p.provision_id) FILTER (WHERE l.legal_content_release_eligible) AS legally_released_article_count
           FROM (((crosstax.treaty_instruments ti
             JOIN crosstax.document_versions ver ON ((ver.document_id = ti.document_id)))
             JOIN crosstax.provisions p ON ((p.version_id = ver.version_id)))
             LEFT JOIN crosstax.v_provision_release_gate l ON ((l.provision_id = p.provision_id)))
          WHERE ((ti.treaty_id = v.treaty_id) AND (lower(p.article_path) = lower(ic.expected_article)))) articles ON (true))
     LEFT JOIN LATERAL ( SELECT count(*) AS released_rules
           FROM crosstax.crossborder_tax_rule_candidates x
          WHERE ((x.payer_jurisdiction_id =
                CASE
                    WHEN (di.direction = 'CN_TO_PARTNER'::text) THEN 'CN'::text
                    ELSE v.partner_id
                END) AND (x.recipient_jurisdiction_id =
                CASE
                    WHEN (di.direction = 'CN_TO_PARTNER'::text) THEN v.partner_id
                    ELSE 'CN'::text
                END) AND (x.income_type = ic.income_type) AND (x.review_status = 'case_tested_released'::text))) rls ON (true));


--
-- Name: v_china_crossborder_product_release; Type: VIEW; Schema: crosstax; Owner: -
--

CREATE VIEW crosstax.v_china_crossborder_product_release AS
 WITH totals AS (
         SELECT count(*) AS case_count,
            count(*) FILTER (WHERE (crossborder_professional_case_tests.verdict = ANY (ARRAY['pass'::text, 'fail'::text]))) AS adjudicated_case_count,
            count(*) FILTER (WHERE (crossborder_professional_case_tests.verdict = 'pass'::text)) AS passed_case_count,
            count(*) FILTER (WHERE (crossborder_professional_case_tests.verdict = 'fail'::text)) AS failed_case_count
           FROM crosstax.crossborder_professional_case_tests
        ), evidence AS (
         SELECT count(*) AS legally_released_articles
           FROM crosstax.v_provision_release_gate
          WHERE v_provision_release_gate.legal_content_release_eligible
        ), rule_count AS (
         SELECT count(*) AS reviewed_rules
           FROM crosstax.crossborder_tax_rule_candidates
          WHERE (crossborder_tax_rule_candidates.review_status = 'case_tested_released'::text)
        ), source_count AS (
         SELECT count(*) AS official_cn_origin_documents
           FROM (crosstax.document_versions v
             JOIN crosstax.documents d ON ((d.document_id = v.document_id)))
          WHERE ((d.jurisdiction_id = 'CN'::text) AND (d.source_id ~~ 'CN-%'::text) AND (v.source_sha256 IS NOT NULL))
        )
 SELECT 200 AS target_professionally_adjudicated_cases,
    0.95 AS required_case_accuracy_ratio,
    totals.case_count,
    totals.adjudicated_case_count,
    totals.passed_case_count,
    totals.failed_case_count,
        CASE
            WHEN (totals.adjudicated_case_count > 0) THEN round(((totals.passed_case_count)::numeric / (totals.adjudicated_case_count)::numeric), 4)
            ELSE NULL::numeric
        END AS observed_case_accuracy_ratio,
    evidence.legally_released_articles,
    rule_count.reviewed_rules,
    source_count.official_cn_origin_documents,
    ((totals.adjudicated_case_count >= 200) AND ((totals.failed_case_count * 20) <= totals.adjudicated_case_count) AND (evidence.legally_released_articles > 0) AND (rule_count.reviewed_rules > 0)) AS legal_calculation_release_allowed,
    'Technical tests are not legal expert validation. Primary source + amendments + scope + tax year + legal reviewer and test evidence mandatory.'::text AS policy
   FROM (((totals
     CROSS JOIN evidence)
     CROSS JOIN rule_count)
     CROSS JOIN source_count);


--
-- Name: v_china_dta_collection_progress; Type: VIEW; Schema: crosstax; Owner: -
--

CREATE VIEW crosstax.v_china_dta_collection_progress AS
 SELECT t.treaty_id,
    jp.jurisdiction_id AS partner_id,
    t.current_status AS treaty_registry_status,
    (pg.source_page_sha256 IS NOT NULL) AS country_page_archived,
    pg.source_url AS official_detail_url,
    pg.attachment_links_found,
    COALESCE(agg.raw_pdf_count, (0)::bigint) AS raw_pdf_count,
    COALESCE(agg.treaty_pdf_candidates, (0)::bigint) AS treaty_pdf_candidates,
    COALESCE(agg.protocol_pdf_candidates, (0)::bigint) AS protocol_pdf_candidates,
    COALESCE(agg.machine_articles, (0)::bigint) AS machine_articles,
    COALESCE(agg.reviewed_articles, (0)::bigint) AS reviewed_articles,
    COALESCE(agg.located_articles, (0)::bigint) AS located_articles,
    COALESCE(dom.domestic_law_count, (0)::bigint) AS partner_domestic_law_versions
   FROM ((((crosstax.treaties t
     JOIN crosstax.treaty_parties jp ON (((jp.treaty_id = t.treaty_id) AND (jp.jurisdiction_id <> 'CN'::text))))
     LEFT JOIN crosstax.country_registry_page_snapshots pg ON ((pg.treaty_id = t.treaty_id)))
     LEFT JOIN LATERAL ( SELECT count(DISTINCT dv.version_id) FILTER (WHERE (dv.source_sha256 IS NOT NULL)) AS raw_pdf_count,
            count(DISTINCT dv.version_id) FILTER (WHERE ((dv.source_sha256 IS NOT NULL) AND (ti.instrument_kind = 'treaty_text_candidate'::text))) AS treaty_pdf_candidates,
            count(DISTINCT dv.version_id) FILTER (WHERE ((dv.source_sha256 IS NOT NULL) AND (ti.instrument_kind = 'protocol'::text))) AS protocol_pdf_candidates,
            count(pr.provision_id) FILTER (WHERE (pr.review_status = 'machine_extracted_unreviewed'::text)) AS machine_articles,
            count(pr.provision_id) FILTER (WHERE (pr.review_status = 'professionally_reviewed'::text)) AS reviewed_articles,
            count(pr.provision_id) FILTER (WHERE ((pr.page_num IS NOT NULL) AND (pr.source_locator IS NOT NULL))) AS located_articles
           FROM (((crosstax.treaty_instruments ti
             JOIN crosstax.documents d ON ((d.document_id = ti.document_id)))
             JOIN crosstax.document_versions dv ON ((dv.document_id = d.document_id)))
             LEFT JOIN crosstax.provisions pr ON ((pr.version_id = dv.version_id)))
          WHERE (ti.treaty_id = t.treaty_id)) agg ON (true))
     LEFT JOIN LATERAL ( SELECT count(*) AS domestic_law_count
           FROM (crosstax.document_versions dv
             JOIN crosstax.documents d ON ((d.document_id = dv.document_id)))
          WHERE ((d.jurisdiction_id = jp.jurisdiction_id) AND (d.document_kind = 'domestic_law'::text))) dom ON (true))
  WHERE (t.treaty_type = 'DTA'::text);


--
-- Name: v_china_oecd_2026_evidence; Type: VIEW; Schema: crosstax; Owner: -
--

CREATE VIEW crosstax.v_china_oecd_2026_evidence AS
 SELECT c.treaty_id,
    c.partner_id,
    c.partner_name_zh,
    c.payer_jurisdiction_id,
    c.recipient_jurisdiction_id,
    c.direction,
    c.income_type,
    c.expected_article,
    c.treaty_relationship_status,
    c.archived_pdf_documents,
    c.archived_treaty_text_candidates,
    c.archived_protocol_candidates,
    c.archived_mli_synthesised_candidates,
    c.income_treaty_article_candidates,
    c.released_treaty_article_count,
    c.released_rules,
    c.legal_rules_available,
    c.actual_status,
    COALESCE(o.oecd_2026_observation_count, (0)::bigint) AS oecd_2026_treaty_observation_count,
    COALESCE(o.research_rate_percent, NULL::numeric) AS oecd_2026_treaty_research_rate_percent,
    o.oecd_2026_legal_basis_label,
    'OECD snapshot from third-party public cache. Historical/treaty effective dates, MLI and exact taxpayer eligibility NOT legal-verified.'::text AS statistical_source_caveat
   FROM (crosstax.v_china_crossborder_practical_scenarios c
     LEFT JOIN LATERAL ( SELECT count(*) AS oecd_2026_observation_count,
                CASE
                    WHEN (count(*) = 1) THEN max(r.value_number)
                    ELSE NULL::numeric
                END AS research_rate_percent,
                CASE
                    WHEN (count(*) = 1) THEN max((r.dimensions ->> 'LEGAL_BASIS'::text))
                    ELSE NULL::text
                END AS oecd_2026_legal_basis_label
           FROM ((crosstax.oecd_2026_observations r
             JOIN crosstax.oecd_country_iso_crosswalk payer ON ((payer.oecd_ref_area = r.reference_area)))
             JOIN crosstax.oecd_country_iso_crosswalk recipient ON ((recipient.oecd_ref_area = r.counterparty_area)))
          WHERE ((r.dataset_id ~~ 'OECD-2026-TREATY-%'::text) AND (payer.jurisdiction_id = c.payer_jurisdiction_id) AND (recipient.jurisdiction_id = c.recipient_jurisdiction_id) AND ((r.dimensions ->> 'MEASURE'::text) =
                CASE c.income_type
                    WHEN 'DIVIDENDS'::text THEN 'WHT_DIV'::text
                    WHEN 'INTEREST'::text THEN 'WHT_INT'::text
                    WHEN 'ROYALTIES'::text THEN 'WHT_ROY'::text
                    ELSE NULL::text
                END))) o ON (true));


--
-- Name: v_global_jurisdiction_practical_methods; Type: VIEW; Schema: crosstax; Owner: -
--

CREATE VIEW crosstax.v_global_jurisdiction_practical_methods AS
 SELECT j.id AS jurisdiction_id,
    j.name_zh,
    j.name_en,
    m.tax_type,
    m.research_topic,
    COALESCE(r.max_year, 0) AS most_recent_research_rate_year,
    COALESCE(r.research_rates, (0)::bigint) AS historical_rate_observations,
    COALESCE(s.guide_count, (0)::bigint) AS chinese_official_secondary_guides,
    COALESCE(s.domestic_law_originals, (0)::bigint) AS foreign_official_domestic_law_snapshots,
    COALESCE(p.reviewed_articles, (0)::bigint) AS professionally_reviewed_provisions,
    COALESCE(m.reviewed_rule_count, 0) AS professionally_reviewed_rules_recorded,
    COALESCE(c.treaty_id, ''::text) AS china_treaty_id,
    COALESCE(c.archived_pdf_documents, (0)::bigint) AS china_treaty_archived_pdfs,
    COALESCE(c.machine_extracted_articles, (0)::bigint) AS china_treaty_machine_articles,
    ((COALESCE(r.research_rates, (0)::bigint) > 0) OR (COALESCE(s.guide_count, (0)::bigint) > 0) OR (COALESCE(s.domestic_law_originals, (0)::bigint) > 0) OR (c.treaty_id IS NOT NULL)) AS has_research_material,
    ((m.reviewed_rule_count > 0) AND (COALESCE(p.reviewed_articles, (0)::bigint) > 0)) AS legal_rule_review_ready,
        CASE
            WHEN ((m.reviewed_rule_count > 0) AND (COALESCE(p.reviewed_articles, (0)::bigint) > 0)) THEN 'legal_evidence_reviewed_case_testing_required'::text
            WHEN (COALESCE(s.domestic_law_originals, (0)::bigint) > 0) THEN 'official_law_original_available_unreviewed'::text
            WHEN ((COALESCE(r.research_rates, (0)::bigint) > 0) OR (COALESCE(s.guide_count, (0)::bigint) > 0) OR (COALESCE(c.archived_pdf_documents, (0)::bigint) > 0)) THEN 'research_available_not_legally_verified'::text
            ELSE 'evidence_missing'::text
        END AS actual_usable_stage,
        CASE
            WHEN ((m.reviewed_rule_count > 0) AND (COALESCE(p.reviewed_articles, (0)::bigint) > 0)) THEN 'Review transaction-specific exceptions and perform independent case testing'::text
            WHEN (COALESCE(s.domestic_law_originals, (0)::bigint) > 0) THEN 'Extract applicable article, confirm temporal law and professionally review'::text
            WHEN (COALESCE(s.guide_count, (0)::bigint) > 0) THEN 'Follow secondary guide references to this jurisdiction official legislation'::text
            WHEN (COALESCE(r.research_rates, (0)::bigint) > 0) THEN 'Locate local official law for this historical tax-rate research candidate'::text
            ELSE 'Find original domestic tax law or verify this topic is not applicable'::text
        END AS next_concrete_step
   FROM (((((crosstax.global_tax_collection_matrix m
     JOIN crosstax.jurisdictions j ON ((j.id = m.jurisdiction_id)))
     LEFT JOIN LATERAL ( SELECT count(*) AS research_rates,
            max(r_1.observation_year) AS max_year
           FROM crosstax.tax_rate_candidates r_1
          WHERE ((r_1.jurisdiction_id = j.id) AND (r_1.tax_type = m.tax_type) AND (m.research_topic = 'statutory_corporate_income_tax'::text))) r ON (true))
     LEFT JOIN LATERAL ( SELECT count(DISTINCT v.version_id) FILTER (WHERE (d.document_kind = 'secondary_country_tax_guide'::text)) AS guide_count,
            count(DISTINCT v.version_id) FILTER (WHERE ((d.document_kind = 'domestic_law'::text) AND (EXISTS ( SELECT 1
                   FROM crosstax.domestic_law_topic_links l
                  WHERE ((l.document_id = d.document_id) AND (l.tax_type = m.tax_type) AND (l.research_topic = m.research_topic)))))) AS domestic_law_originals
           FROM (crosstax.documents d
             JOIN crosstax.document_versions v ON ((v.document_id = d.document_id)))
          WHERE ((d.jurisdiction_id = j.id) AND (v.source_sha256 IS NOT NULL))) s ON (true))
     LEFT JOIN LATERAL ( SELECT count(*) AS reviewed_articles
           FROM ((crosstax.provisions p_1
             JOIN crosstax.document_versions v ON ((v.version_id = p_1.version_id)))
             JOIN crosstax.documents d ON ((d.document_id = v.document_id)))
          WHERE ((d.jurisdiction_id = j.id) AND (d.document_kind = 'domestic_law'::text) AND (p_1.review_status = 'professionally_reviewed'::text))) p ON (true))
     LEFT JOIN crosstax.v_china_treaty_evidence_coverage c ON ((c.partner_id = j.id)));


--
-- Name: v_global_practical_2026; Type: VIEW; Schema: crosstax; Owner: -
--

CREATE VIEW crosstax.v_global_practical_2026 AS
 SELECT v.jurisdiction_id,
    v.name_zh,
    v.name_en,
    v.tax_type,
    v.research_topic,
    v.most_recent_research_rate_year,
    v.historical_rate_observations,
    v.chinese_official_secondary_guides,
    v.foreign_official_domestic_law_snapshots,
    v.professionally_reviewed_provisions,
    v.professionally_reviewed_rules_recorded,
    v.china_treaty_id,
    v.china_treaty_archived_pdfs,
    v.china_treaty_machine_articles,
    v.has_research_material,
    v.legal_rule_review_ready,
    v.actual_usable_stage,
    v.next_concrete_step,
    COALESCE(o.official_oecd_2026_obs, (0)::bigint) AS oecd_cached_2026_observations,
    COALESCE(o.measure_specific_obs, (0)::bigint) AS oecd_2026_measure_specific_obs,
        CASE
            WHEN (COALESCE(o.measure_specific_obs, (0)::bigint) > 0) THEN 'OECD_2026_STATISTICAL_EVIDENCE_CACHED_ORIGIN_COMPARISON_PENDING'::text
            ELSE 'NO_OECD_2026_STATISTICS_FOR_THIS_TAX_TOPIC'::text
        END AS oecd_research_status,
    (v.legal_rule_review_ready AND (COALESCE(v.professionally_reviewed_rules_recorded, 0) > 0)) AS released_tax_legal_rule_eligible,
        CASE
            WHEN ((v.actual_usable_stage = 'evidence_missing'::text) AND (COALESCE(o.measure_specific_obs, (0)::bigint) > 0)) THEN 'oecd_2026_statistical_research_only_not_legally_verified'::text
            ELSE v.actual_usable_stage
        END AS factual_source_stage_2026
   FROM (crosstax.v_global_jurisdiction_practical_methods v
     LEFT JOIN LATERAL ( SELECT count(*) AS official_oecd_2026_obs,
            count(*) FILTER (WHERE (((v.research_topic = 'statutory_corporate_income_tax'::text) AND ((r.dimensions ->> 'MEASURE'::text) = ANY (ARRAY['CIT_C'::text, 'CIT'::text]))) OR ((v.research_topic = 'dividends'::text) AND ((r.dimensions ->> 'MEASURE'::text) = 'WHT_DIV'::text)) OR ((v.research_topic = 'interest'::text) AND ((r.dimensions ->> 'MEASURE'::text) = 'WHT_INT'::text)) OR ((v.research_topic = 'royalties'::text) AND ((r.dimensions ->> 'MEASURE'::text) = 'WHT_ROY'::text)))) AS measure_specific_obs
           FROM (crosstax.oecd_2026_observations r
             JOIN crosstax.oecd_country_iso_crosswalk x ON ((x.oecd_ref_area = r.reference_area)))
          WHERE ((x.jurisdiction_id = v.jurisdiction_id) AND (((v.tax_type = 'CIT'::text) AND (r.dataset_id ~~ 'OECD-2026-CIT-%'::text)) OR ((v.tax_type = 'WHT'::text) AND (r.dataset_id ~~ 'OECD-2026-STANDARD-%'::text))))) o ON (true));


--
-- Name: v_legal_text_l1; Type: VIEW; Schema: crosstax; Owner: -
--

CREATE VIEW crosstax.v_legal_text_l1 AS
 SELECT a.candidate_id,
    a.article_number,
    a.body_text,
    a.body_sha256,
    a.pdf_page_start,
    a.pdf_page_end,
    a.source_file_sha256,
    a.candidate_level,
    a.qa_issues,
    a.signature_or_afterword,
    v.version_id,
    v.content_locator,
    v.audit_status,
    d.document_id,
    d.official_title,
    d.document_kind,
    d.source_id,
    d.signed_at,
    t.treaty_id,
    p.jurisdiction_id AS partner_code,
    i.instrument_class,
    i.version_identity_status,
    i.identified_signed_year,
    i.directory_signed_years
   FROM (((((crosstax.legal_article_candidates a
     JOIN crosstax.document_versions v ON ((v.version_id = a.version_id)))
     JOIN crosstax.documents d ON ((d.document_id = v.document_id)))
     JOIN crosstax.instrument_qa_profiles i ON ((i.version_id = a.version_id)))
     LEFT JOIN crosstax.treaty_instruments t ON ((t.document_id = d.document_id)))
     LEFT JOIN crosstax.treaty_parties p ON (((p.treaty_id = t.treaty_id) AND (p.jurisdiction_id <> 'CN'::text))))
  WHERE (v.source_sha256 = a.source_file_sha256);


--
-- Name: v_legal_citation_l2; Type: VIEW; Schema: crosstax; Owner: -
--

CREATE VIEW crosstax.v_legal_citation_l2 AS
 SELECT x.candidate_id,
    x.article_number,
    x.body_text,
    x.body_sha256,
    x.pdf_page_start,
    x.pdf_page_end,
    x.source_file_sha256,
    x.candidate_level,
    x.qa_issues,
    x.signature_or_afterword,
    x.version_id,
    x.content_locator,
    x.audit_status,
    x.document_id,
    x.official_title,
    x.document_kind,
    x.source_id,
    x.signed_at,
    x.treaty_id,
    x.partner_code,
    x.instrument_class,
    x.version_identity_status,
    x.identified_signed_year,
    x.directory_signed_years,
    r.reviewer AS reviewing_person,
    r.reviewed_at AS legal_review_at
   FROM ((crosstax.v_legal_text_l1 x
     JOIN crosstax.instrument_qa_profiles i ON ((i.version_id = x.version_id)))
     JOIN crosstax.qa_reviews r ON (((r.target_type = 'legal_article_candidate'::text) AND (r.target_id = x.candidate_id) AND (r.review_type = 'legal'::text) AND (r.decision = 'approved'::text) AND (r.evidence_locator = x.body_sha256))))
  WHERE ((i.version_identity_status = 'officially_verified'::text) AND (i.boundary_status = 'expert_verified'::text) AND (NOT (EXISTS ( SELECT 1
           FROM crosstax.qa_findings f
          WHERE ((f.disposition = 'open'::text) AND (f.severity = ANY (ARRAY['high'::text, 'critical'::text])) AND (((f.object_type = 'provision'::text) AND (f.object_id = ( SELECT a.source_provision_id
                   FROM crosstax.legal_article_candidates a
                  WHERE (a.candidate_id = x.candidate_id)))) OR ((f.object_type = 'legal_article_candidate'::text) AND (f.object_id = x.candidate_id))))))));


--
-- Name: verified_tax_rules; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.verified_tax_rules (
    rule_id text NOT NULL,
    candidate_id text NOT NULL,
    jurisdiction_id text NOT NULL,
    tax_type text NOT NULL,
    income_category text,
    rule_type text NOT NULL,
    rate numeric(18,8),
    rate_unit text,
    taxable_base text,
    conditions jsonb DEFAULT '[]'::jsonb NOT NULL,
    exceptions jsonb DEFAULT '[]'::jsonb NOT NULL,
    applies_from date NOT NULL,
    applies_to date,
    proof_source_id text NOT NULL,
    verified_by text NOT NULL,
    verified_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT verified_tax_rules_check CHECK (((applies_to IS NULL) OR (applies_to >= applies_from))),
    CONSTRAINT verified_tax_rules_verified_by_check CHECK ((length(TRIM(BOTH FROM verified_by)) > 0))
);


--
-- Name: v_legal_rule_l3; Type: VIEW; Schema: crosstax; Owner: -
--

CREATE VIEW crosstax.v_legal_rule_l3 AS
 SELECT r.rule_id,
    r.candidate_id,
    r.jurisdiction_id,
    r.tax_type,
    r.income_category,
    r.rule_type,
    r.rate,
    r.rate_unit,
    r.taxable_base,
    r.conditions,
    r.exceptions,
    r.applies_from,
    r.applies_to,
    r.proof_source_id,
    r.verified_by,
    r.verified_at,
    l.article_number,
    l.body_sha256,
    l.official_title,
    l.content_locator,
    l.legal_review_at,
    l.version_id
   FROM (crosstax.verified_tax_rules r
     JOIN crosstax.v_legal_citation_l2 l ON ((l.candidate_id = r.candidate_id)));


--
-- Name: v_oecd_2026_observation_evidence; Type: VIEW; Schema: crosstax; Owner: -
--

CREATE VIEW crosstax.v_oecd_2026_observation_evidence AS
 SELECT o.dataset_id,
    o.record_number,
    o.reference_area,
    o.counterparty_area,
    o.observation_period,
    o.value_number,
    o.value_raw,
    (o.dimensions ->> 'MEASURE'::text) AS statistical_measure,
    (o.dimensions ->> 'UNIT_MEASURE'::text) AS statistical_unit,
    (o.dimensions ->> 'TREATY_DATE'::text) AS treaty_reference_year,
    o.source_row_sha256,
    o.verification_status,
    s.dataset_name,
    s.original_url AS dataset_source_url,
    s.local_locator,
    s.sha256 AS dataset_snapshot_sha256,
    s.provenance_note
   FROM (crosstax.oecd_2026_observations o
     JOIN crosstax.research_dataset_snapshots s ON ((s.dataset_id = o.dataset_id)));


--
-- Name: v_unified_tax_answer_evidence; Type: VIEW; Schema: crosstax; Owner: -
--

CREATE VIEW crosstax.v_unified_tax_answer_evidence AS
 SELECT package_id,
    payer_jurisdiction_id,
    recipient_jurisdiction_id,
    income_type,
    transaction_subtype,
    title,
    effective_from,
    effective_until,
    nominal_rate,
    taxable_fraction,
    rate_basis,
    required_facts,
    exceptions,
    official_evidence,
    legal_change_checks,
    evidence_sha256,
    audit_status,
    treaty_id
   FROM crosstax.unified_tax_answer_packages p
  WHERE (audit_status = ANY (ARRAY['official_crosschecked'::text, 'professionally_approved'::text, 'published'::text]));


--
-- Name: v_unified_tax_answer_review_queue; Type: VIEW; Schema: crosstax; Owner: -
--

CREATE VIEW crosstax.v_unified_tax_answer_review_queue AS
 SELECT package_id,
    payer_jurisdiction_id,
    recipient_jurisdiction_id,
    income_type,
    transaction_subtype,
    effective_from,
    effective_until,
    audit_status,
    evidence_sha256,
    qa_review_id,
    professional_case_id,
    created_at,
    updated_at,
    ( SELECT count(*) AS count
           FROM jsonb_array_elements(p.official_evidence) src(value)
          WHERE (length(COALESCE((src.value ->> 'sha256'::text), ''::text)) <> 64)) AS unarchived_evidence_items,
    (NOT (legal_change_checks @> '{"both_domestic_laws_verified": true, "tax_type_and_period_verified": true, "all_treaty_amendments_verified": true, "withholding_procedure_verified": true, "counterparty_mli_positions_verified": true}'::jsonb)) AS missing_effective_law_checks,
    ( SELECT count(*) AS count
           FROM crosstax.qa_findings f
          WHERE ((f.object_type = 'unified_tax_answer_package'::text) AND (f.object_id = p.package_id) AND (f.disposition = 'open'::text) AND (f.severity = ANY (ARRAY['critical'::text, 'high'::text])))) AS blocking_qa_findings
   FROM crosstax.unified_tax_answer_packages p;


--
-- Name: v_unified_tax_answer_published; Type: VIEW; Schema: crosstax; Owner: -
--

CREATE VIEW crosstax.v_unified_tax_answer_published AS
 SELECT p.package_id,
    p.payer_jurisdiction_id,
    p.recipient_jurisdiction_id,
    p.income_type,
    p.transaction_subtype,
    p.treaty_id,
    p.title,
    p.effective_from,
    p.effective_until,
    p.nominal_rate,
    p.taxable_fraction,
    p.rate_basis,
    p.required_facts,
    p.exceptions,
    p.official_evidence,
    p.evidence_sha256,
    p.legal_change_checks,
    p.audit_status,
    p.qa_review_id,
    p.professional_case_id,
    p.created_at,
    p.updated_at,
    r.reviewer,
    r.reviewed_at AS legal_reviewed_at
   FROM (((crosstax.unified_tax_answer_packages p
     JOIN crosstax.qa_reviews r ON ((r.review_id = p.qa_review_id)))
     JOIN crosstax.crossborder_professional_case_tests c ON ((c.case_id = p.professional_case_id)))
     JOIN crosstax.v_unified_tax_answer_review_queue gate ON ((gate.package_id = p.package_id)))
  WHERE ((p.audit_status = 'published'::text) AND (gate.unarchived_evidence_items = 0) AND (gate.missing_effective_law_checks = false) AND (gate.blocking_qa_findings = 0) AND (r.review_type = 'legal'::text) AND (r.decision = 'approved'::text) AND (r.target_type = 'unified_tax_answer_package'::text) AND (r.target_id = p.package_id) AND (r.evidence_locator = p.evidence_sha256) AND (c.verdict = 'pass'::text) AND (c.reference_review_id = r.review_id) AND (c.payer_jurisdiction_id = p.payer_jurisdiction_id) AND (c.recipient_jurisdiction_id = p.recipient_jurisdiction_id) AND (c.income_type = p.income_type) AND (c.transaction_date >= p.effective_from) AND ((p.effective_until IS NULL) OR (c.transaction_date <= p.effective_until)) AND ((c.fact_pattern ->> 'transaction_subtype'::text) = p.transaction_subtype) AND (jsonb_typeof(c.expert_expected_result) = 'object'::text) AND (c.expert_expected_result @> jsonb_build_object('package_id', p.package_id, 'evidence_sha256', p.evidence_sha256, 'legal_and_tax_review_complete', true)) AND (NOT (EXISTS ( SELECT 1
           FROM jsonb_array_elements_text(p.required_facts) required(value)
          WHERE ((c.fact_pattern ->> required.value) IS DISTINCT FROM 'true'::text)))));


--
-- Name: version_relations; Type: TABLE; Schema: crosstax; Owner: -
--

CREATE TABLE crosstax.version_relations (
    relation_id text NOT NULL,
    predecessor_version_id text,
    successor_version_id text,
    relation_kind text NOT NULL,
    proof_source_id text,
    CONSTRAINT version_relations_relation_kind_check CHECK ((relation_kind = ANY (ARRAY['amends'::text, 'repeals'::text, 'replaces'::text, 'clarifies'::text, 'corrects'::text])))
);


--
-- Name: applicability_windows applicability_windows_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.applicability_windows
    ADD CONSTRAINT applicability_windows_pkey PRIMARY KEY (window_id);


--
-- Name: case_provision_links case_provision_links_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.case_provision_links
    ADD CONSTRAINT case_provision_links_pkey PRIMARY KEY (case_id, provision_id, link_kind);


--
-- Name: case_records case_records_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.case_records
    ADD CONSTRAINT case_records_pkey PRIMARY KEY (case_id);


--
-- Name: claims claims_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.claims
    ADD CONSTRAINT claims_pkey PRIMARY KEY (claim_id);


--
-- Name: confidence_assessments confidence_assessments_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.confidence_assessments
    ADD CONSTRAINT confidence_assessments_pkey PRIMARY KEY (assessment_id);


--
-- Name: country_registry_page_snapshots country_registry_page_snapshots_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.country_registry_page_snapshots
    ADD CONSTRAINT country_registry_page_snapshots_pkey PRIMARY KEY (treaty_id, source_url);


--
-- Name: coverage_register coverage_register_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.coverage_register
    ADD CONSTRAINT coverage_register_pkey PRIMARY KEY (jurisdiction_id, tax_type, income_category, from_year, to_year);


--
-- Name: crossborder_professional_case_tests crossborder_professional_case_tests_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.crossborder_professional_case_tests
    ADD CONSTRAINT crossborder_professional_case_tests_pkey PRIMARY KEY (case_id);


--
-- Name: crossborder_tax_rule_candidates crossborder_tax_rule_candidates_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.crossborder_tax_rule_candidates
    ADD CONSTRAINT crossborder_tax_rule_candidates_pkey PRIMARY KEY (rule_id);


--
-- Name: document_versions document_versions_document_id_version_label_key; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.document_versions
    ADD CONSTRAINT document_versions_document_id_version_label_key UNIQUE (document_id, version_label);


--
-- Name: document_versions document_versions_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.document_versions
    ADD CONSTRAINT document_versions_pkey PRIMARY KEY (version_id);


--
-- Name: documents documents_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.documents
    ADD CONSTRAINT documents_pkey PRIMARY KEY (document_id);


--
-- Name: domestic_law_topic_links domestic_law_topic_links_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.domestic_law_topic_links
    ADD CONSTRAINT domestic_law_topic_links_pkey PRIMARY KEY (document_id, tax_type, research_topic);


--
-- Name: evidence_conflicts evidence_conflicts_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.evidence_conflicts
    ADD CONSTRAINT evidence_conflicts_pkey PRIMARY KEY (conflict_id);


--
-- Name: global_tax_collection_matrix global_tax_collection_matrix_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.global_tax_collection_matrix
    ADD CONSTRAINT global_tax_collection_matrix_pkey PRIMARY KEY (jurisdiction_id, tax_type, research_topic);


--
-- Name: income_categories income_categories_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.income_categories
    ADD CONSTRAINT income_categories_pkey PRIMARY KEY (code);


--
-- Name: ingestion_tasks ingestion_tasks_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.ingestion_tasks
    ADD CONSTRAINT ingestion_tasks_pkey PRIMARY KEY (task_id);


--
-- Name: instrument_qa_profiles instrument_qa_profiles_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.instrument_qa_profiles
    ADD CONSTRAINT instrument_qa_profiles_pkey PRIMARY KEY (document_id);


--
-- Name: instrument_qa_profiles instrument_qa_profiles_version_id_key; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.instrument_qa_profiles
    ADD CONSTRAINT instrument_qa_profiles_version_id_key UNIQUE (version_id);


--
-- Name: international_organizations international_organizations_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.international_organizations
    ADD CONSTRAINT international_organizations_pkey PRIMARY KEY (org_id);


--
-- Name: jurisdictions jurisdictions_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.jurisdictions
    ADD CONSTRAINT jurisdictions_pkey PRIMARY KEY (id);


--
-- Name: legal_article_candidates legal_article_candidates_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.legal_article_candidates
    ADD CONSTRAINT legal_article_candidates_pkey PRIMARY KEY (candidate_id);


--
-- Name: legal_article_candidates legal_article_candidates_version_id_article_number_key; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.legal_article_candidates
    ADD CONSTRAINT legal_article_candidates_version_id_article_number_key UNIQUE (version_id, article_number);


--
-- Name: oecd_2026_observations oecd_2026_observations_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.oecd_2026_observations
    ADD CONSTRAINT oecd_2026_observations_pkey PRIMARY KEY (dataset_id, record_number);


--
-- Name: oecd_country_iso_crosswalk oecd_country_iso_crosswalk_jurisdiction_id_key; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.oecd_country_iso_crosswalk
    ADD CONSTRAINT oecd_country_iso_crosswalk_jurisdiction_id_key UNIQUE (jurisdiction_id);


--
-- Name: oecd_country_iso_crosswalk oecd_country_iso_crosswalk_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.oecd_country_iso_crosswalk
    ADD CONSTRAINT oecd_country_iso_crosswalk_pkey PRIMARY KEY (oecd_ref_area);


--
-- Name: provisions provisions_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.provisions
    ADD CONSTRAINT provisions_pkey PRIMARY KEY (provision_id);


--
-- Name: provisions provisions_version_id_article_path_key; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.provisions
    ADD CONSTRAINT provisions_version_id_article_path_key UNIQUE (version_id, article_path);


--
-- Name: qa_findings qa_findings_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.qa_findings
    ADD CONSTRAINT qa_findings_pkey PRIMARY KEY (finding_id);


--
-- Name: qa_findings qa_findings_run_id_check_code_object_type_object_id_key; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.qa_findings
    ADD CONSTRAINT qa_findings_run_id_check_code_object_type_object_id_key UNIQUE (run_id, check_code, object_type, object_id);


--
-- Name: qa_reviews qa_reviews_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.qa_reviews
    ADD CONSTRAINT qa_reviews_pkey PRIMARY KEY (review_id);


--
-- Name: qa_runs qa_runs_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.qa_runs
    ADD CONSTRAINT qa_runs_pkey PRIMARY KEY (run_id);


--
-- Name: research_dataset_snapshots research_dataset_snapshots_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.research_dataset_snapshots
    ADD CONSTRAINT research_dataset_snapshots_pkey PRIMARY KEY (dataset_id);


--
-- Name: research_document_chunks research_document_chunks_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.research_document_chunks
    ADD CONSTRAINT research_document_chunks_pkey PRIMARY KEY (chunk_id);


--
-- Name: research_document_chunks research_document_chunks_version_id_page_num_part_no_key; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.research_document_chunks
    ADD CONSTRAINT research_document_chunks_version_id_page_num_part_no_key UNIQUE (version_id, page_num, part_no);


--
-- Name: source_organization_links source_organization_links_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.source_organization_links
    ADD CONSTRAINT source_organization_links_pkey PRIMARY KEY (source_id, org_id);


--
-- Name: sources sources_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.sources
    ADD CONSTRAINT sources_pkey PRIMARY KEY (source_id);


--
-- Name: sources sources_source_url_key; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.sources
    ADD CONSTRAINT sources_source_url_key UNIQUE (source_url);


--
-- Name: sta_treaty_registry_entries sta_treaty_registry_entries_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.sta_treaty_registry_entries
    ADD CONSTRAINT sta_treaty_registry_entries_pkey PRIMARY KEY (entry_id);


--
-- Name: tax_rate_candidates tax_rate_candidates_dataset_id_jurisdiction_id_metric_code__key; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.tax_rate_candidates
    ADD CONSTRAINT tax_rate_candidates_dataset_id_jurisdiction_id_metric_code__key UNIQUE (dataset_id, jurisdiction_id, metric_code, observation_year);


--
-- Name: tax_rate_candidates tax_rate_candidates_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.tax_rate_candidates
    ADD CONSTRAINT tax_rate_candidates_pkey PRIMARY KEY (candidate_id);


--
-- Name: tax_types tax_types_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.tax_types
    ADD CONSTRAINT tax_types_pkey PRIMARY KEY (code);


--
-- Name: text_chunks text_chunks_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.text_chunks
    ADD CONSTRAINT text_chunks_pkey PRIMARY KEY (chunk_id);


--
-- Name: text_chunks text_chunks_provision_id_chunk_order_key; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.text_chunks
    ADD CONSTRAINT text_chunks_provision_id_chunk_order_key UNIQUE (provision_id, chunk_order);


--
-- Name: treaties treaties_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.treaties
    ADD CONSTRAINT treaties_pkey PRIMARY KEY (treaty_id);


--
-- Name: treaty_changes treaty_changes_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.treaty_changes
    ADD CONSTRAINT treaty_changes_pkey PRIMARY KEY (change_id);


--
-- Name: treaty_instruments treaty_instruments_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.treaty_instruments
    ADD CONSTRAINT treaty_instruments_pkey PRIMARY KEY (treaty_id, document_id);


--
-- Name: treaty_parties treaty_parties_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.treaty_parties
    ADD CONSTRAINT treaty_parties_pkey PRIMARY KEY (treaty_id, jurisdiction_id);


--
-- Name: unified_tax_answer_packages unified_tax_answer_packages_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.unified_tax_answer_packages
    ADD CONSTRAINT unified_tax_answer_packages_pkey PRIMARY KEY (package_id);


--
-- Name: verified_tax_rules verified_tax_rules_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.verified_tax_rules
    ADD CONSTRAINT verified_tax_rules_pkey PRIMARY KEY (rule_id);


--
-- Name: version_relations version_relations_pkey; Type: CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.version_relations
    ADD CONSTRAINT version_relations_pkey PRIMARY KEY (relation_id);


--
-- Name: idx_legal_article_candidates_ver; Type: INDEX; Schema: crosstax; Owner: -
--

CREATE INDEX idx_legal_article_candidates_ver ON crosstax.legal_article_candidates USING btree (version_id, article_number);


--
-- Name: idx_legal_article_search; Type: INDEX; Schema: crosstax; Owner: -
--

CREATE INDEX idx_legal_article_search ON crosstax.legal_article_candidates USING gin (to_tsvector('simple'::regconfig, body_text));


--
-- Name: ix_applicability; Type: INDEX; Schema: crosstax; Owner: -
--

CREATE INDEX ix_applicability ON crosstax.applicability_windows USING btree (jurisdiction_id, tax_type, applies_from, applies_to);


--
-- Name: ix_case_published; Type: INDEX; Schema: crosstax; Owner: -
--

CREATE INDEX ix_case_published ON crosstax.case_records USING btree (published_at, case_type);


--
-- Name: ix_cases_jurisdiction; Type: INDEX; Schema: crosstax; Owner: -
--

CREATE INDEX ix_cases_jurisdiction ON crosstax.case_records USING btree (jurisdiction_id, published_at);


--
-- Name: ix_chunks_fts; Type: INDEX; Schema: crosstax; Owner: -
--

CREATE INDEX ix_chunks_fts ON crosstax.text_chunks USING gin (to_tsvector('simple'::regconfig, chunk_text));


--
-- Name: ix_crossborder_rule_lookup; Type: INDEX; Schema: crosstax; Owner: -
--

CREATE INDEX ix_crossborder_rule_lookup ON crosstax.crossborder_tax_rule_candidates USING btree (payer_jurisdiction_id, recipient_jurisdiction_id, income_type, applicability_from);


--
-- Name: ix_doc_jurisdiction; Type: INDEX; Schema: crosstax; Owner: -
--

CREATE INDEX ix_doc_jurisdiction ON crosstax.documents USING btree (jurisdiction_id, document_kind);


--
-- Name: ix_global_matrix_status; Type: INDEX; Schema: crosstax; Owner: -
--

CREATE INDEX ix_global_matrix_status ON crosstax.global_tax_collection_matrix USING btree (collection_status, tax_type);


--
-- Name: ix_oecd_observation_ref; Type: INDEX; Schema: crosstax; Owner: -
--

CREATE INDEX ix_oecd_observation_ref ON crosstax.oecd_2026_observations USING btree (reference_area, observation_period);


--
-- Name: ix_provisions_article_path; Type: INDEX; Schema: crosstax; Owner: -
--

CREATE INDEX ix_provisions_article_path ON crosstax.provisions USING btree (article_path);


--
-- Name: ix_qa_findings_open; Type: INDEX; Schema: crosstax; Owner: -
--

CREATE INDEX ix_qa_findings_open ON crosstax.qa_findings USING btree (disposition, severity, object_type);


--
-- Name: ix_qa_reviews_target; Type: INDEX; Schema: crosstax; Owner: -
--

CREATE INDEX ix_qa_reviews_target ON crosstax.qa_reviews USING btree (target_type, target_id);


--
-- Name: ix_research_chunk_fulltext; Type: INDEX; Schema: crosstax; Owner: -
--

CREATE INDEX ix_research_chunk_fulltext ON crosstax.research_document_chunks USING gin (to_tsvector('simple'::regconfig, chunk_text));


--
-- Name: ix_research_chunk_version; Type: INDEX; Schema: crosstax; Owner: -
--

CREATE INDEX ix_research_chunk_version ON crosstax.research_document_chunks USING btree (version_id, page_num);


--
-- Name: ix_sta_registry_relation; Type: INDEX; Schema: crosstax; Owner: -
--

CREATE INDEX ix_sta_registry_relation ON crosstax.sta_treaty_registry_entries USING btree (treaty_id, signed_at);


--
-- Name: ix_tax_rate_candidate_lookup; Type: INDEX; Schema: crosstax; Owner: -
--

CREATE INDEX ix_tax_rate_candidate_lookup ON crosstax.tax_rate_candidates USING btree (jurisdiction_id, tax_type, observation_year DESC);


--
-- Name: ix_treaty_instruments_doc; Type: INDEX; Schema: crosstax; Owner: -
--

CREATE INDEX ix_treaty_instruments_doc ON crosstax.treaty_instruments USING btree (document_id);


--
-- Name: ix_treaty_party; Type: INDEX; Schema: crosstax; Owner: -
--

CREATE INDEX ix_treaty_party ON crosstax.treaty_parties USING btree (jurisdiction_id, treaty_id);


--
-- Name: ix_unified_tax_answer_lookup; Type: INDEX; Schema: crosstax; Owner: -
--

CREATE INDEX ix_unified_tax_answer_lookup ON crosstax.unified_tax_answer_packages USING btree (payer_jurisdiction_id, recipient_jurisdiction_id, income_type, transaction_subtype, effective_from);


--
-- Name: ix_versions_temporal; Type: INDEX; Schema: crosstax; Owner: -
--

CREATE INDEX ix_versions_temporal ON crosstax.document_versions USING btree (document_id, applies_from, applies_to);


--
-- Name: applicability_windows applicability_windows_document_version_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.applicability_windows
    ADD CONSTRAINT applicability_windows_document_version_id_fkey FOREIGN KEY (document_version_id) REFERENCES crosstax.document_versions(version_id);


--
-- Name: applicability_windows applicability_windows_income_category_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.applicability_windows
    ADD CONSTRAINT applicability_windows_income_category_fkey FOREIGN KEY (income_category) REFERENCES crosstax.income_categories(code);


--
-- Name: applicability_windows applicability_windows_jurisdiction_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.applicability_windows
    ADD CONSTRAINT applicability_windows_jurisdiction_id_fkey FOREIGN KEY (jurisdiction_id) REFERENCES crosstax.jurisdictions(id);


--
-- Name: applicability_windows applicability_windows_proof_source_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.applicability_windows
    ADD CONSTRAINT applicability_windows_proof_source_id_fkey FOREIGN KEY (proof_source_id) REFERENCES crosstax.sources(source_id);


--
-- Name: applicability_windows applicability_windows_tax_type_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.applicability_windows
    ADD CONSTRAINT applicability_windows_tax_type_fkey FOREIGN KEY (tax_type) REFERENCES crosstax.tax_types(code);


--
-- Name: case_provision_links case_provision_links_case_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.case_provision_links
    ADD CONSTRAINT case_provision_links_case_id_fkey FOREIGN KEY (case_id) REFERENCES crosstax.case_records(case_id);


--
-- Name: case_provision_links case_provision_links_provision_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.case_provision_links
    ADD CONSTRAINT case_provision_links_provision_id_fkey FOREIGN KEY (provision_id) REFERENCES crosstax.provisions(provision_id);


--
-- Name: case_records case_records_jurisdiction_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.case_records
    ADD CONSTRAINT case_records_jurisdiction_id_fkey FOREIGN KEY (jurisdiction_id) REFERENCES crosstax.jurisdictions(id);


--
-- Name: case_records case_records_source_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.case_records
    ADD CONSTRAINT case_records_source_id_fkey FOREIGN KEY (source_id) REFERENCES crosstax.sources(source_id);


--
-- Name: claim_evidence claim_evidence_claim_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.claim_evidence
    ADD CONSTRAINT claim_evidence_claim_id_fkey FOREIGN KEY (claim_id) REFERENCES crosstax.claims(claim_id);


--
-- Name: claim_evidence claim_evidence_provision_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.claim_evidence
    ADD CONSTRAINT claim_evidence_provision_id_fkey FOREIGN KEY (provision_id) REFERENCES crosstax.provisions(provision_id);


--
-- Name: claim_evidence claim_evidence_source_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.claim_evidence
    ADD CONSTRAINT claim_evidence_source_id_fkey FOREIGN KEY (source_id) REFERENCES crosstax.sources(source_id);


--
-- Name: claims claims_jurisdiction_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.claims
    ADD CONSTRAINT claims_jurisdiction_id_fkey FOREIGN KEY (jurisdiction_id) REFERENCES crosstax.jurisdictions(id);


--
-- Name: confidence_assessments confidence_assessments_claim_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.confidence_assessments
    ADD CONSTRAINT confidence_assessments_claim_id_fkey FOREIGN KEY (claim_id) REFERENCES crosstax.claims(claim_id);


--
-- Name: country_registry_page_snapshots country_registry_page_snapshots_treaty_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.country_registry_page_snapshots
    ADD CONSTRAINT country_registry_page_snapshots_treaty_id_fkey FOREIGN KEY (treaty_id) REFERENCES crosstax.treaties(treaty_id);


--
-- Name: coverage_register coverage_register_jurisdiction_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.coverage_register
    ADD CONSTRAINT coverage_register_jurisdiction_id_fkey FOREIGN KEY (jurisdiction_id) REFERENCES crosstax.jurisdictions(id);


--
-- Name: coverage_register coverage_register_tax_type_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.coverage_register
    ADD CONSTRAINT coverage_register_tax_type_fkey FOREIGN KEY (tax_type) REFERENCES crosstax.tax_types(code);


--
-- Name: crossborder_professional_case_tests crossborder_professional_case_te_recipient_jurisdiction_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.crossborder_professional_case_tests
    ADD CONSTRAINT crossborder_professional_case_te_recipient_jurisdiction_id_fkey FOREIGN KEY (recipient_jurisdiction_id) REFERENCES crosstax.jurisdictions(id);


--
-- Name: crossborder_professional_case_tests crossborder_professional_case_tests_payer_jurisdiction_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.crossborder_professional_case_tests
    ADD CONSTRAINT crossborder_professional_case_tests_payer_jurisdiction_id_fkey FOREIGN KEY (payer_jurisdiction_id) REFERENCES crosstax.jurisdictions(id);


--
-- Name: crossborder_professional_case_tests crossborder_professional_case_tests_reference_review_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.crossborder_professional_case_tests
    ADD CONSTRAINT crossborder_professional_case_tests_reference_review_id_fkey FOREIGN KEY (reference_review_id) REFERENCES crosstax.qa_reviews(review_id);


--
-- Name: crossborder_tax_rule_candidates crossborder_tax_rule_candidates_payer_jurisdiction_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.crossborder_tax_rule_candidates
    ADD CONSTRAINT crossborder_tax_rule_candidates_payer_jurisdiction_id_fkey FOREIGN KEY (payer_jurisdiction_id) REFERENCES crosstax.jurisdictions(id);


--
-- Name: crossborder_tax_rule_candidates crossborder_tax_rule_candidates_professional_review_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.crossborder_tax_rule_candidates
    ADD CONSTRAINT crossborder_tax_rule_candidates_professional_review_id_fkey FOREIGN KEY (professional_review_id) REFERENCES crosstax.qa_reviews(review_id);


--
-- Name: crossborder_tax_rule_candidates crossborder_tax_rule_candidates_recipient_jurisdiction_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.crossborder_tax_rule_candidates
    ADD CONSTRAINT crossborder_tax_rule_candidates_recipient_jurisdiction_id_fkey FOREIGN KEY (recipient_jurisdiction_id) REFERENCES crosstax.jurisdictions(id);


--
-- Name: crossborder_tax_rule_candidates crossborder_tax_rule_candidates_source_provision_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.crossborder_tax_rule_candidates
    ADD CONSTRAINT crossborder_tax_rule_candidates_source_provision_id_fkey FOREIGN KEY (source_provision_id) REFERENCES crosstax.provisions(provision_id);


--
-- Name: crossborder_tax_rule_candidates crossborder_tax_rule_candidates_version_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.crossborder_tax_rule_candidates
    ADD CONSTRAINT crossborder_tax_rule_candidates_version_id_fkey FOREIGN KEY (version_id) REFERENCES crosstax.document_versions(version_id);


--
-- Name: document_versions document_versions_document_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.document_versions
    ADD CONSTRAINT document_versions_document_id_fkey FOREIGN KEY (document_id) REFERENCES crosstax.documents(document_id);


--
-- Name: documents documents_jurisdiction_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.documents
    ADD CONSTRAINT documents_jurisdiction_id_fkey FOREIGN KEY (jurisdiction_id) REFERENCES crosstax.jurisdictions(id);


--
-- Name: documents documents_source_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.documents
    ADD CONSTRAINT documents_source_id_fkey FOREIGN KEY (source_id) REFERENCES crosstax.sources(source_id);


--
-- Name: domestic_law_topic_links domestic_law_topic_links_document_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.domestic_law_topic_links
    ADD CONSTRAINT domestic_law_topic_links_document_id_fkey FOREIGN KEY (document_id) REFERENCES crosstax.documents(document_id);


--
-- Name: domestic_law_topic_links domestic_law_topic_links_tax_type_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.domestic_law_topic_links
    ADD CONSTRAINT domestic_law_topic_links_tax_type_fkey FOREIGN KEY (tax_type) REFERENCES crosstax.tax_types(code);


--
-- Name: evidence_conflicts evidence_conflicts_claim_a_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.evidence_conflicts
    ADD CONSTRAINT evidence_conflicts_claim_a_id_fkey FOREIGN KEY (claim_a_id) REFERENCES crosstax.claims(claim_id);


--
-- Name: evidence_conflicts evidence_conflicts_claim_b_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.evidence_conflicts
    ADD CONSTRAINT evidence_conflicts_claim_b_id_fkey FOREIGN KEY (claim_b_id) REFERENCES crosstax.claims(claim_id);


--
-- Name: evidence_conflicts evidence_conflicts_jurisdiction_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.evidence_conflicts
    ADD CONSTRAINT evidence_conflicts_jurisdiction_id_fkey FOREIGN KEY (jurisdiction_id) REFERENCES crosstax.jurisdictions(id);


--
-- Name: global_tax_collection_matrix global_tax_collection_matrix_jurisdiction_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.global_tax_collection_matrix
    ADD CONSTRAINT global_tax_collection_matrix_jurisdiction_id_fkey FOREIGN KEY (jurisdiction_id) REFERENCES crosstax.jurisdictions(id);


--
-- Name: global_tax_collection_matrix global_tax_collection_matrix_official_law_document_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.global_tax_collection_matrix
    ADD CONSTRAINT global_tax_collection_matrix_official_law_document_id_fkey FOREIGN KEY (official_law_document_id) REFERENCES crosstax.documents(document_id);


--
-- Name: global_tax_collection_matrix global_tax_collection_matrix_tax_type_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.global_tax_collection_matrix
    ADD CONSTRAINT global_tax_collection_matrix_tax_type_fkey FOREIGN KEY (tax_type) REFERENCES crosstax.tax_types(code);


--
-- Name: ingestion_tasks ingestion_tasks_document_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.ingestion_tasks
    ADD CONSTRAINT ingestion_tasks_document_id_fkey FOREIGN KEY (document_id) REFERENCES crosstax.documents(document_id);


--
-- Name: ingestion_tasks ingestion_tasks_source_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.ingestion_tasks
    ADD CONSTRAINT ingestion_tasks_source_id_fkey FOREIGN KEY (source_id) REFERENCES crosstax.sources(source_id);


--
-- Name: instrument_qa_profiles instrument_qa_profiles_document_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.instrument_qa_profiles
    ADD CONSTRAINT instrument_qa_profiles_document_id_fkey FOREIGN KEY (document_id) REFERENCES crosstax.documents(document_id);


--
-- Name: instrument_qa_profiles instrument_qa_profiles_version_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.instrument_qa_profiles
    ADD CONSTRAINT instrument_qa_profiles_version_id_fkey FOREIGN KEY (version_id) REFERENCES crosstax.document_versions(version_id);


--
-- Name: international_organizations international_organizations_parent_org_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.international_organizations
    ADD CONSTRAINT international_organizations_parent_org_id_fkey FOREIGN KEY (parent_org_id) REFERENCES crosstax.international_organizations(org_id);


--
-- Name: jurisdictions jurisdictions_parent_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.jurisdictions
    ADD CONSTRAINT jurisdictions_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES crosstax.jurisdictions(id);


--
-- Name: legal_article_candidates legal_article_candidates_source_provision_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.legal_article_candidates
    ADD CONSTRAINT legal_article_candidates_source_provision_id_fkey FOREIGN KEY (source_provision_id) REFERENCES crosstax.provisions(provision_id);


--
-- Name: legal_article_candidates legal_article_candidates_version_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.legal_article_candidates
    ADD CONSTRAINT legal_article_candidates_version_id_fkey FOREIGN KEY (version_id) REFERENCES crosstax.document_versions(version_id);


--
-- Name: oecd_2026_observations oecd_2026_observations_dataset_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.oecd_2026_observations
    ADD CONSTRAINT oecd_2026_observations_dataset_id_fkey FOREIGN KEY (dataset_id) REFERENCES crosstax.research_dataset_snapshots(dataset_id);


--
-- Name: oecd_country_iso_crosswalk oecd_country_iso_crosswalk_jurisdiction_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.oecd_country_iso_crosswalk
    ADD CONSTRAINT oecd_country_iso_crosswalk_jurisdiction_id_fkey FOREIGN KEY (jurisdiction_id) REFERENCES crosstax.jurisdictions(id);


--
-- Name: provisions provisions_version_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.provisions
    ADD CONSTRAINT provisions_version_id_fkey FOREIGN KEY (version_id) REFERENCES crosstax.document_versions(version_id);


--
-- Name: qa_findings qa_findings_run_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.qa_findings
    ADD CONSTRAINT qa_findings_run_id_fkey FOREIGN KEY (run_id) REFERENCES crosstax.qa_runs(run_id);


--
-- Name: qa_reviews qa_reviews_run_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.qa_reviews
    ADD CONSTRAINT qa_reviews_run_id_fkey FOREIGN KEY (run_id) REFERENCES crosstax.qa_runs(run_id);


--
-- Name: research_document_chunks research_document_chunks_version_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.research_document_chunks
    ADD CONSTRAINT research_document_chunks_version_id_fkey FOREIGN KEY (version_id) REFERENCES crosstax.document_versions(version_id);


--
-- Name: source_organization_links source_organization_links_org_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.source_organization_links
    ADD CONSTRAINT source_organization_links_org_id_fkey FOREIGN KEY (org_id) REFERENCES crosstax.international_organizations(org_id);


--
-- Name: source_organization_links source_organization_links_source_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.source_organization_links
    ADD CONSTRAINT source_organization_links_source_id_fkey FOREIGN KEY (source_id) REFERENCES crosstax.sources(source_id);


--
-- Name: sources sources_country_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.sources
    ADD CONSTRAINT sources_country_id_fkey FOREIGN KEY (country_id) REFERENCES crosstax.jurisdictions(id);


--
-- Name: sta_treaty_registry_entries sta_treaty_registry_entries_treaty_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.sta_treaty_registry_entries
    ADD CONSTRAINT sta_treaty_registry_entries_treaty_id_fkey FOREIGN KEY (treaty_id) REFERENCES crosstax.treaties(treaty_id);


--
-- Name: tax_rate_candidates tax_rate_candidates_dataset_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.tax_rate_candidates
    ADD CONSTRAINT tax_rate_candidates_dataset_id_fkey FOREIGN KEY (dataset_id) REFERENCES crosstax.research_dataset_snapshots(dataset_id);


--
-- Name: tax_rate_candidates tax_rate_candidates_jurisdiction_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.tax_rate_candidates
    ADD CONSTRAINT tax_rate_candidates_jurisdiction_id_fkey FOREIGN KEY (jurisdiction_id) REFERENCES crosstax.jurisdictions(id);


--
-- Name: tax_rate_candidates tax_rate_candidates_official_provision_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.tax_rate_candidates
    ADD CONSTRAINT tax_rate_candidates_official_provision_id_fkey FOREIGN KEY (official_provision_id) REFERENCES crosstax.provisions(provision_id);


--
-- Name: tax_rate_candidates tax_rate_candidates_tax_type_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.tax_rate_candidates
    ADD CONSTRAINT tax_rate_candidates_tax_type_fkey FOREIGN KEY (tax_type) REFERENCES crosstax.tax_types(code);


--
-- Name: text_chunks text_chunks_provision_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.text_chunks
    ADD CONSTRAINT text_chunks_provision_id_fkey FOREIGN KEY (provision_id) REFERENCES crosstax.provisions(provision_id);


--
-- Name: treaties treaties_source_document_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.treaties
    ADD CONSTRAINT treaties_source_document_id_fkey FOREIGN KEY (source_document_id) REFERENCES crosstax.documents(document_id);


--
-- Name: treaty_changes treaty_changes_instrument_document_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.treaty_changes
    ADD CONSTRAINT treaty_changes_instrument_document_id_fkey FOREIGN KEY (instrument_document_id) REFERENCES crosstax.documents(document_id);


--
-- Name: treaty_changes treaty_changes_treaty_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.treaty_changes
    ADD CONSTRAINT treaty_changes_treaty_id_fkey FOREIGN KEY (treaty_id) REFERENCES crosstax.treaties(treaty_id);


--
-- Name: treaty_instruments treaty_instruments_document_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.treaty_instruments
    ADD CONSTRAINT treaty_instruments_document_id_fkey FOREIGN KEY (document_id) REFERENCES crosstax.documents(document_id);


--
-- Name: treaty_instruments treaty_instruments_treaty_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.treaty_instruments
    ADD CONSTRAINT treaty_instruments_treaty_id_fkey FOREIGN KEY (treaty_id) REFERENCES crosstax.treaties(treaty_id);


--
-- Name: treaty_parties treaty_parties_jurisdiction_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.treaty_parties
    ADD CONSTRAINT treaty_parties_jurisdiction_id_fkey FOREIGN KEY (jurisdiction_id) REFERENCES crosstax.jurisdictions(id);


--
-- Name: treaty_parties treaty_parties_treaty_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.treaty_parties
    ADD CONSTRAINT treaty_parties_treaty_id_fkey FOREIGN KEY (treaty_id) REFERENCES crosstax.treaties(treaty_id);


--
-- Name: unified_tax_answer_packages unified_tax_answer_packages_payer_jurisdiction_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.unified_tax_answer_packages
    ADD CONSTRAINT unified_tax_answer_packages_payer_jurisdiction_id_fkey FOREIGN KEY (payer_jurisdiction_id) REFERENCES crosstax.jurisdictions(id);


--
-- Name: unified_tax_answer_packages unified_tax_answer_packages_professional_case_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.unified_tax_answer_packages
    ADD CONSTRAINT unified_tax_answer_packages_professional_case_id_fkey FOREIGN KEY (professional_case_id) REFERENCES crosstax.crossborder_professional_case_tests(case_id);


--
-- Name: unified_tax_answer_packages unified_tax_answer_packages_qa_review_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.unified_tax_answer_packages
    ADD CONSTRAINT unified_tax_answer_packages_qa_review_id_fkey FOREIGN KEY (qa_review_id) REFERENCES crosstax.qa_reviews(review_id);


--
-- Name: unified_tax_answer_packages unified_tax_answer_packages_recipient_jurisdiction_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.unified_tax_answer_packages
    ADD CONSTRAINT unified_tax_answer_packages_recipient_jurisdiction_id_fkey FOREIGN KEY (recipient_jurisdiction_id) REFERENCES crosstax.jurisdictions(id);


--
-- Name: unified_tax_answer_packages unified_tax_answer_packages_treaty_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.unified_tax_answer_packages
    ADD CONSTRAINT unified_tax_answer_packages_treaty_id_fkey FOREIGN KEY (treaty_id) REFERENCES crosstax.treaties(treaty_id);


--
-- Name: verified_tax_rules verified_tax_rules_candidate_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.verified_tax_rules
    ADD CONSTRAINT verified_tax_rules_candidate_id_fkey FOREIGN KEY (candidate_id) REFERENCES crosstax.legal_article_candidates(candidate_id);


--
-- Name: verified_tax_rules verified_tax_rules_income_category_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.verified_tax_rules
    ADD CONSTRAINT verified_tax_rules_income_category_fkey FOREIGN KEY (income_category) REFERENCES crosstax.income_categories(code);


--
-- Name: verified_tax_rules verified_tax_rules_jurisdiction_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.verified_tax_rules
    ADD CONSTRAINT verified_tax_rules_jurisdiction_id_fkey FOREIGN KEY (jurisdiction_id) REFERENCES crosstax.jurisdictions(id);


--
-- Name: verified_tax_rules verified_tax_rules_proof_source_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.verified_tax_rules
    ADD CONSTRAINT verified_tax_rules_proof_source_id_fkey FOREIGN KEY (proof_source_id) REFERENCES crosstax.sources(source_id);


--
-- Name: verified_tax_rules verified_tax_rules_tax_type_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.verified_tax_rules
    ADD CONSTRAINT verified_tax_rules_tax_type_fkey FOREIGN KEY (tax_type) REFERENCES crosstax.tax_types(code);


--
-- Name: version_relations version_relations_predecessor_version_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.version_relations
    ADD CONSTRAINT version_relations_predecessor_version_id_fkey FOREIGN KEY (predecessor_version_id) REFERENCES crosstax.document_versions(version_id);


--
-- Name: version_relations version_relations_proof_source_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.version_relations
    ADD CONSTRAINT version_relations_proof_source_id_fkey FOREIGN KEY (proof_source_id) REFERENCES crosstax.sources(source_id);


--
-- Name: version_relations version_relations_successor_version_id_fkey; Type: FK CONSTRAINT; Schema: crosstax; Owner: -
--

ALTER TABLE ONLY crosstax.version_relations
    ADD CONSTRAINT version_relations_successor_version_id_fkey FOREIGN KEY (successor_version_id) REFERENCES crosstax.document_versions(version_id);


--
-- PostgreSQL database dump complete
--

\unrestrict bKgAB1tZ6eSYILck9zwLdtPfOzqOmebk82fms7M12pTHOx4JH334Sz1lQyPs7sl

