"""Read-only, parameterized access to CrossTax legal evidence and release views."""
from __future__ import annotations
from datetime import date
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
import os
from pathlib import Path
import psycopg
from psycopg.rows import dict_row
from workspace_store import validate_dsn


def connection():
    dsn=os.getenv('CROSSTAX_LEGAL_DATABASE_URL','') or os.getenv('CROSSTAX_APP_DATABASE_URL','')
    if dsn:
        validate_dsn(dsn)
        db=psycopg.connect(dsn,row_factory=dict_row,connect_timeout=10)
    else:
        if os.getenv('CROSSTAX_ENV')=='production':
            raise RuntimeError('法律库未配置')
        env=Path(__file__).resolve().parent.parent/'.secrets/postgres.env'
        values=dict(line.split('=',1) for line in env.read_text('utf-8-sig').splitlines() if '=' in line and not line.startswith('#'))
        if values.get('POSTGRES_DB')!='crosstax' or values.get('POSTGRES_USER')!='crosstax':
            raise RuntimeError('专库身份不匹配')
        db=psycopg.connect(host='127.0.0.1',port=55433,dbname='crosstax',user='crosstax',password=values['POSTGRES_PASSWORD'],row_factory=dict_row,connect_timeout=5)
    db.execute('SET TRANSACTION READ ONLY')
    db.execute('SET LOCAL statement_timeout=10000')
    return db


def rows(query, params=()):
    with connection() as db:
        return db.execute(query,params).fetchall()


def search(payload):
    query=str(payload.get('query','')).strip()
    if not query or len(query)>200:
        raise ValueError('检索关键词需要 1–200 字符')
    partner=payload.get('partner') or None
    level=payload.get('level','L1')
    if level not in {'L1','L2'}:
        raise ValueError('检索层级需为 L1 或 L2')
    limit=max(1,min(int(payload.get('limit',8)),20))
    view='crosstax.v_legal_text_l1' if level=='L1' else 'crosstax.v_legal_citation_l2'
    # FTS handles words; ILIKE retains Chinese substring coverage.
    hit=rows(f'''SELECT DISTINCT ON(x.candidate_id) x.candidate_id AS id,
        x.partner_code,x.article_number,x.body_text,x.body_sha256,x.source_file_sha256,
        x.pdf_page_start,x.pdf_page_end,x.version_id,x.official_title,
        x.version_identity_status,x.identified_signed_year,d.original_url,
        v.entered_into_force_at,v.applies_from,v.applies_to
        FROM {view} x JOIN crosstax.documents d ON d.document_id=x.document_id
        JOIN crosstax.document_versions v ON v.version_id=x.version_id
        WHERE (%s::text IS NULL OR x.partner_code=%s)
          AND (to_tsvector('simple',x.body_text) @@ plainto_tsquery('simple',%s)
            OR x.body_text ILIKE %s OR x.official_title ILIKE %s)
        ORDER BY x.candidate_id LIMIT %s''',(partner,partner,query,'%'+query+'%','%'+query+'%',limit))
    for x in hit:
        x['level']=level;x['excerpt']=x.pop('body_text')[:1800]
        x['applicability_note']='历史条文候选，需核对适用日期、修订及交易条件' if level=='L1' else '引用通过现有 L2 视图；仍须匹配交易事实和时点'
    guides=rows('''SELECT c.chunk_id AS id,d.official_title,d.original_url,c.page_num,
        c.source_locator,c.original_sha256,c.chunk_sha256,left(c.chunk_text,1400) AS excerpt
        FROM crosstax.research_document_chunks c
        JOIN crosstax.document_versions v ON v.version_id=c.version_id
        JOIN crosstax.documents d ON d.document_id=v.document_id
        WHERE c.chunk_text ILIKE %s AND (%s::text IS NULL OR d.jurisdiction_id=%s)
        ORDER BY c.page_num LIMIT %s''',('%'+query+'%',partner,partner,min(4,limit))) if payload.get('include_guides',True) else []
    for x in guides:
        x['level']='research_guide';x['applicability_note']='国别研究指南，不能代替当地正式法律'
    return {'query':query,'results':hit+guides,'source':'CrossTax PostgreSQL','retrieved_at':date.today().isoformat()}


def evidence(id):
    hit=rows('''SELECT DISTINCT ON(x.candidate_id) x.*,d.original_url
        FROM crosstax.v_legal_text_l1 x JOIN crosstax.documents d ON d.document_id=x.document_id
        WHERE x.candidate_id=%s ORDER BY x.candidate_id''',(id,))
    if hit:
        return {**hit[0],'level':'L1','applicability_note':'历史条文候选，非自动适用规则'}
    hit=rows('''SELECT c.*,d.original_url,d.official_title FROM crosstax.research_document_chunks c
        JOIN crosstax.document_versions v ON v.version_id=c.version_id
        JOIN crosstax.documents d ON d.document_id=v.document_id WHERE c.chunk_id=%s''',(id,))
    return {**hit[0],'level':'research_guide'} if hit else None


def decimal_value(value, name, maximum=None):
    try:
        x=Decimal(str(value))
    except (InvalidOperation,ValueError):
        raise ValueError(name+'必须是数字')
    if not x.is_finite() or x<0 or (maximum is not None and x>maximum):
        raise ValueError(name+'超出允许范围')
    return x


def assess(payload):
    facts=payload.get('facts') or {}
    if not isinstance(facts,dict):
        raise ValueError('facts 需要对象')
    if facts.get('date'):
        date.fromisoformat(facts['date'])
    amount=decimal_value(payload.get('amount','0'),'金额',Decimal('1e18'))
    missing=[k for k in ['payer','recipient','income_type','transaction_subtype','date'] if not facts.get(k)]
    blocked=[]
    if facts.get('classification_confirmed') is not True:
        missing.append('classification_confirmed')
    if facts.get('pe_effective_connection') is True:
        blocked.append('所得与常设机构有效关联，需转入营业利润及当地税制分析')
    elif facts.get('pe_effective_connection') is not False:
        missing.append('pe_effective_connection')
    requirements=['beneficial_owner','recipient_tax_resident','eligibility_documents','principal_purpose_test_passed']
    for k in requirements:
        if facts.get(k) is not True:
            missing.append(k)
    if facts.get('income_type')=='DIVIDENDS' and facts.get('shareholding_conditions_met') is not True:
        missing.append('shareholding_conditions_met')
    result={'facts':facts,'amount':str(amount),'currency':payload.get('currency','CNY'),
        'tax_estimate':None,'conditional_example':None,'status':'facts_missing' if missing else 'rule_not_published',
        'missing_facts':list(dict.fromkeys(missing)),'conflicts':blocked,'formula':'amount × taxable_fraction × nominal_rate',
        'sources':[],'rule_version':None,'confidence_explanation':{'facts_complete':not missing,'period_checked':False,'conflicts':blocked,'basis':'来源、适用日期、事实完整性与冲突；无模型正确概率'}}
    if not missing and not blocked:
        packets=rows('''SELECT * FROM crosstax.v_unified_tax_answer_published
          WHERE payer_jurisdiction_id=%s AND recipient_jurisdiction_id=%s AND income_type=%s
            AND transaction_subtype=%s AND effective_from<=%s::date
            AND (effective_until IS NULL OR effective_until>=%s::date)
          ORDER BY effective_from DESC LIMIT 2''',(facts['payer'],facts['recipient'],facts['income_type'],facts['transaction_subtype'],facts['date'],facts['date']))
        if len(packets)>1:
            result['conflicts'].append('有重叠发布规则，需要确定版本');result['status']='version_conflict'
        elif packets:
            p=packets[0]
            more=[k for k in p['required_facts'] if facts.get(k) is not True]
            result['sources']=p['official_evidence'];result['rule_version']={'id':p['package_id'],'sha256':p['evidence_sha256'],'effective_from':p['effective_from'],'effective_until':p['effective_until']}
            result['missing_facts'].extend(more)
            result['confidence_explanation']['facts_complete']=not more
            if more:
                result['status']='facts_missing'
            if not more:
                result['tax_estimate']=str((amount*p['taxable_fraction']*p['nominal_rate']).quantize(Decimal('.01'),rounding=ROUND_HALF_UP))
                result['status']='approved';result['confidence_explanation']['period_checked']=True
    if blocked:
        result['status']='exception_requires_analysis'
    # Explicit user assumptions only; never substitute historical/statistical rates.
    assumptions=payload.get('assumptions')
    if assumptions and not blocked:
        rate=decimal_value(assumptions.get('nominal_rate'),'假设税率',Decimal(1))
        portion=decimal_value(assumptions.get('taxable_fraction',1),'假设税基比例',Decimal(1))
        result['conditional_example']={'amount':str((amount*rate*portion).quantize(Decimal('.01'),rounding=ROUND_HALF_UP)),
            'nominal_rate':str(rate),'taxable_fraction':str(portion),'basis':'使用人明确输入的假设；未证明为该交易法定税率','currency':result['currency']}
    return result
