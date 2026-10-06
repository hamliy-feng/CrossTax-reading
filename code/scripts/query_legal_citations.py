#!/usr/bin/env python3
"""CrossTax safe read-only L1/L2/L3 treaty evidence search.

Do not confuse an L1 machine candidate with a verified legal citation or rule.
Examples:
 python scripts/query_legal_citations.py --partner SG --article 12 --level L1
 python scripts/query_legal_citations.py --partner GB --article 5 --level L2
 python scripts/query_legal_citations.py --partner SG --level L3 --tax WHT
"""
import argparse,csv,io,json,re
from import_official_firstwave import cmd_psql,q

def find(a):
    limit=max(1,min(a.limit,100))
    if a.level in ("L1","L2"):
        view="crosstax.v_legal_text_l1" if a.level=="L1" else "crosstax.v_legal_citation_l2"
        parts=["TRUE"]
        if a.partner:
            if not re.fullmatch("[A-Z]{2,3}",a.partner):raise ValueError("Invalid country/region code")
            parts.append("partner_code="+q(a.partner))
        if a.article:parts.append("article_number="+q(str(a.article)))
        if a.term:parts.append("body_text ILIKE "+q("%"+a.term+"%"))
        sql="""SELECT DISTINCT ON (candidate_id) candidate_id,partner_code,article_number,
          official_title,version_id,identified_signed_year,directory_signed_years,
          version_identity_status,content_locator,pdf_page_start,pdf_page_end,
          body_sha256,substring(body_text,1,450) AS excerpt
          FROM """+view+" WHERE "+" AND ".join(parts)+" ORDER BY candidate_id LIMIT "+str(limit)
    else:
        parts=["TRUE"]
        if a.partner:
            if not re.fullmatch("[A-Z]{2,3}",a.partner):raise ValueError("Invalid partner code")
            parts.append("jurisdiction_id="+q(a.partner))
        if a.article:parts.append("article_number="+q(str(a.article)))
        if a.tax:parts.append("tax_type="+q(a.tax))
        sql="""SELECT rule_id,jurisdiction_id,tax_type,income_category,rate,
               rate_unit,taxable_base,applies_from,applies_to,
               article_number,official_title,content_locator,body_sha256,
               conditions::text AS conditions,exceptions::text AS exceptions
               FROM crosstax.v_legal_rule_l3 WHERE """+" AND ".join(parts)+" ORDER BY rule_id LIMIT "+str(limit)
    result=cmd_psql(query="COPY ("+sql+") TO STDOUT WITH CSV HEADER")
    return list(csv.DictReader(io.StringIO(result)))
def main():
    p=argparse.ArgumentParser()
    p.add_argument("--partner",default=None)
    p.add_argument("--article",default=None)
    p.add_argument("--term",default=None)
    p.add_argument("--tax",default=None)
    p.add_argument("--level",choices=("L1","L2","L3"),default="L1")
    p.add_argument("--limit",type=int,default=5)
    a=p.parse_args()
    rows=find(a)
    print(json.dumps({"level":a.level,"count":len(rows),
        "warning":"L1 machine-extracted historical text is not a present-day applicable tax rule." if a.level=="L1" else
                  ("L2 requires documented verified identity/boundary and legal review." if a.level=="L2" else
                   "L3 only includes verified dated tax rules with applicable conditions."),
        "results":rows},ensure_ascii=False,indent=2))
if __name__=="__main__":main()
