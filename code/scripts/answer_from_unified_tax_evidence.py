#!/usr/bin/env python3
"""CrossTax single-step legal-and-tax evidence answering interface.

Provides actual conditional tax computations only when a dated official-source
unified package exactly matches the fact pattern. All other countries can query
the 21,525 searchable OECD-2026 observations with complete source provenance.
No old treaty machine paragraph is auto-selected as a currently valid treaty.
"""
from __future__ import annotations
import argparse,csv,io,json,re
from datetime import date
from decimal import Decimal,ROUND_HALF_UP
from import_official_firstwave import cmd_psql,q

MAP={"DIVIDENDS":"WHT_DIV","INTEREST":"WHT_INT","ROYALTIES":"WHT_ROY","TECHNICAL_FEES":"WHT_TEC","CIT":"CIT"}
def db(sql):return list(csv.DictReader(io.StringIO(cmd_psql(query="COPY ("+sql+") TO STDOUT WITH CSV HEADER"))))
def std_code(country):
    if not re.fullmatch("[A-Z]{2,3}",country):raise ValueError("use a 2/3-letter jurisdiction code")
    x=db("SELECT oecd_ref_area FROM crosstax.oecd_country_iso_crosswalk WHERE jurisdiction_id="+q(country)+" ORDER BY oecd_ref_area LIMIT 1")
    return x[0]["oecd_ref_area"] if x else country
def to_bool(s):
    if s is None or s=="unknown":return None
    return s=="yes"
def money(value,rate,portion):
    return str((Decimal(value)*Decimal(str(rate))*Decimal(str(portion))).quantize(Decimal("0.01"),rounding=ROUND_HALF_UP))
def observations(payer,recipient,topic,limit=12):
    measure=MAP[topic]
    payer3=std_code(payer)
    recipient3=std_code(recipient) if recipient else None
    key="AND o.reference_area="+q(payer3)
    if topic!="CIT" and recipient3:
        key+=" AND o.counterparty_area="+q(recipient3)+" AND o.dataset_id LIKE "+q("%TREATY%")
    elif topic=="CIT":
        key+=" AND o.dataset_id LIKE "+q("%CIT%")
    else:key+=" AND o.dataset_id LIKE "+q("%STANDARD%")
    key+=" AND o.statistical_measure="+q(measure)
    qry="""SELECT o.dataset_id,o.record_number,o.reference_area,o.counterparty_area,
      o.statistical_measure,o.value_number,o.statistical_unit,o.treaty_reference_year,
      o.source_row_sha256,o.dataset_source_url,o.dataset_snapshot_sha256,o.provenance_note
      FROM crosstax.v_oecd_2026_observation_evidence o
      WHERE TRUE """+key+" ORDER BY o.record_number LIMIT "+str(min(25,limit))
    return db(qry)

def supporting_guide_snippets(country,term,limit=4):
    if not term:return []
    if len(term)>80:raise ValueError("search term too long")
    qry="""SELECT d.official_title,d.original_url,d.document_kind,
       c.page_num,c.source_locator,c.original_sha256,c.chunk_sha256,
       left(c.chunk_text,600) AS excerpt
       FROM crosstax.research_document_chunks c
       JOIN crosstax.document_versions v ON v.version_id=c.version_id
       JOIN crosstax.documents d ON d.document_id=v.document_id
       WHERE d.jurisdiction_id="""+q(country)+""" AND d.document_kind='secondary_country_tax_guide'
       AND c.chunk_text ILIKE """+q("%"+term+"%")+" ORDER BY c.page_num LIMIT "+str(limit)
    return db(qry)

def historical_treaty_evidence(payer,recipient,topic,limit=4):
    if not recipient or "CN" not in (payer,recipient):return {"historical_registry":[],"machine_article_candidates":[]}
    partner=recipient if payer=="CN" else payer
    treaty_id="CN-"+partner+"-DTA"
    history=db("""SELECT registry_name,signed_at,force_at_original,applicability_original,official_listing_url
       FROM crosstax.sta_treaty_registry_entries WHERE treaty_id="""+q(treaty_id)+"""
       ORDER BY signed_at DESC LIMIT 8""")
    article={"DIVIDENDS":"10","INTEREST":"11","ROYALTIES":"12"}.get(topic)
    candidates=[]
    if article:
        candidates=db("""SELECT DISTINCT candidate_id,article_number,official_title,
             identified_signed_year,version_identity_status,pdf_page_start,
             source_file_sha256,content_locator,
             left(body_text,360) AS historical_excerpt
             FROM crosstax.v_legal_text_l1
             WHERE partner_code="""+q(partner)+" AND article_number="+q(article)+
             " ORDER BY candidate_id LIMIT "+str(limit))
    return {"historical_registry":history,"machine_article_candidates":candidates,
            "warning":"Article numbers are retrieval hints only. Historical texts are not auto-selected as current law."}

def run(payer,recipient,topic,transaction_subtype,amount,tax_date,beneficial_owner,
        recipient_tax_resident,cn_source,no_cn_pe,ppt_passed,currency="CNY",term=None):
    p=payer.upper();r=recipient.upper() if recipient else None;kind=topic.upper()
    if kind not in MAP:raise ValueError("income type must be one of "+", ".join(MAP))
    date.fromisoformat(tax_date)
    amt=Decimal(str(amount))
    if not amt.is_finite() or amt<0:raise ValueError("amount must be >=0 and finite")
    evidence=observations(p,r,kind)
    result={"question":{"payer":p,"recipient":r,"income_type":kind,
                       "transaction_subtype":transaction_subtype,
                       "transaction_date":tax_date,"payment_amount":str(amt),"currency":currency},
           "dataset_observations_2026":evidence,
           "data_class":"OECD SDMX-format preserved comparative tax research observations",
           "answer_source":"CrossTax live PostgreSQL 2026 records",
           "legal_evidence_package":None,"tax_estimate":None,
           "legal_release_status":"not_approved_for_tax_determination",
           "required_facts":[],
           "supporting_guide_snippets":supporting_guide_snippets(r if r else p,term),
           "historical_treaty_evidence":historical_treaty_evidence(p,r,kind),
           "next_evidence_to_collect":[]}
    if p=="CN" and r=="SG" and kind=="ROYALTIES" and transaction_subtype=="industrial_commercial_scientific_equipment":
        matches=db("""SELECT package_id,title,nominal_rate,taxable_fraction,effective_from,effective_until,
             official_evidence::text AS official_evidence,required_facts::text AS required_facts,
             exceptions::text AS exceptions,legal_change_checks::text AS legal_change_checks,
             audit_status FROM crosstax.v_unified_tax_answer_evidence
             WHERE payer_jurisdiction_id='CN' AND recipient_jurisdiction_id='SG'
               AND income_type='ROYALTIES'
               AND transaction_subtype='industrial_commercial_scientific_equipment'
               AND effective_from<="""+q(tax_date)+"""::date
               AND (effective_until IS NULL OR effective_until>="""+q(tax_date)+"""::date)
             ORDER BY effective_from DESC LIMIT 1""")
        if matches:
            x=matches[0]
            facts={"beneficial_owner":beneficial_owner,
                   "recipient_tax_resident_SG":recipient_tax_resident,
                   "china_source":cn_source,
                   "no_cn_pe_effective_connection":no_cn_pe,
                   "principal_purpose_test_passed":ppt_passed}
            missing=[name for name,value in facts.items() if value is not True]
            result["legal_evidence_package"]={
               "id":x["package_id"],"audit_status":x["audit_status"],"title":x["title"],
               "nominal_rate":x["nominal_rate"],"taxable_fraction":x["taxable_fraction"],
               "official_evidence":json.loads(x["official_evidence"]),
               "required_facts":json.loads(x["required_facts"]),
               "exceptions":json.loads(x["exceptions"]),
               "legal_change_checks":json.loads(x["legal_change_checks"])}
            result["required_facts"]=missing
            # An archived treaty and an official article crosscheck are not a
            # legally published, version-current tax determination. Query the
            # stringent joint evidence+human review+case acceptance gate.
            released=db("""SELECT package_id FROM crosstax.v_unified_tax_answer_published
                WHERE package_id="""+q(x["package_id"])+"""
                  AND effective_from<="""+q(tax_date)+"""::date
                  AND (effective_until IS NULL OR effective_until>="""+q(tax_date)+"""::date)
                LIMIT 1""")
            if not missing and released:
                result["legal_release_status"]="approved_for_tax_determination"
                result["tax_estimate"]={
                  "tax_category":"PRC non-resident enterprise income tax on equipment royalty",
                  "formula":"gross_royalty * taxable_fraction * nominal_rate",
                  "amount":money(amt,x["nominal_rate"],x["taxable_fraction"]),
                  "currency":currency,
                  "basis":"2007 China–Singapore Article 12(2) + protocol, as jointly reviewed for this transaction",
                  "scope":"Only the case facts and tax period actually approved by the professional review"}
            else:
                result["tax_estimate"]=None
                result["next_evidence_to_collect"]=[
                  "The official source excerpts are research evidence, not an approved tax determination.",
                  "A current legal version and all protocol/MLI changes require a completed joint legal-and-tax review.",
                  "Review the actual taxpayer's residence, beneficial ownership, income classification, source, PE, PPT and filing conditions.",
                  "Only a matching published rule and passed professional case can produce an amount."]
                if missing:
                    result["next_evidence_to_collect"].append(
                      "Missing or unestablished facts: "+", ".join(missing))
            return result
    result["next_evidence_to_collect"]=[
      "Locate official domestic tax statute for both payer and recipient as of transaction date",
      "Find applicable bilateral treaty and every amendment/MLI effective for this tax and year",
      "Verify beneficial ownership, permanent establishment, tax base, anti-abuse, compliance procedure",
      "Do not apply a comparable OECD statistical value before resolving the case's exact statutory conditions"]
    return result

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--payer",required=True)
    p.add_argument("--recipient")
    p.add_argument("--income",default="CIT",choices=list(MAP))
    p.add_argument("--type",default="general",dest="subtype")
    p.add_argument("--amount",default="1000000")
    p.add_argument("--date",default="2026-09-01")
    p.add_argument("--currency",default="CNY")
    p.add_argument("--term",default=None,help="Search country tax guide text and show page-level provenance")
    p.add_argument("--beneficial-owner",choices=("yes","no","unknown"),default="unknown")
    p.add_argument("--recipient-tax-resident",choices=("yes","no","unknown"),default="unknown")
    p.add_argument("--china-source",choices=("yes","no","unknown"),default="unknown")
    p.add_argument("--no-cn-pe",choices=("yes","no","unknown"),default="unknown")
    p.add_argument("--ppt-passed",choices=("yes","no","unknown"),default="unknown")
    a=p.parse_args()
    result=run(a.payer,a.recipient,a.income,a.subtype,a.amount,a.date,
               to_bool(a.beneficial_owner),to_bool(a.recipient_tax_resident),
               to_bool(a.china_source),to_bool(a.no_cn_pe),to_bool(a.ppt_passed),
               a.currency,a.term)
    print(json.dumps(result,ensure_ascii=False,indent=2,default=str))
if __name__=="__main__":main()
