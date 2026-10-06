"""Build ten clearly identified constructed cases and record actual program runs.

Never updates professional case verdicts, legal review identities or rules.
Official raw responses are private; public copies contain URLs/SHA and short quotes.
"""
from __future__ import annotations
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import httpx

ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT/'web'))
import legal_service

SOURCES={
 'sg_dta_list':('https://www.iras.gov.sg/taxes/international-tax/international-tax-agreements-concluded-by-singapore/list-of-dtas-limited-dtas-and-eoi-arrangements','官方协定目录；需逐一核对协议、议定书与 MLI'),
 'cn_sg_explanation':('https://fgk.chinatax.gov.cn/zcfgk/c100012/c5194181/content.html','国税发〔2010〕75号中新协定条文解释；含后续废止提示'),
 'sg_payments':('https://www.iras.gov.sg/taxes/withholding-tax/payments-to-non-resident-company/payments-that-are-subject-to-withholding-tax','官方扣缴及软件权利分类问答；新加坡付款侧说明'),
 'sg_dividends':('https://www.iras.gov.sg/taxes/withholding-tax/payments-to-non-resident-company/payments-that-are-not-subject-to-withholding-tax','新加坡股息扣缴说明；国内法与协定上限须分开'),
 'hk_arrangement':('https://www.ird.gov.hk/eng/pdf/Consolidated_Text_Mainland_HKSAR.pdf','内地香港安排综合文本；仍须逐一核对议定书及程序'),
 'hk_explanation':('https://www.ird.gov.hk/eng/pdf/dipn44.pdf','香港税务局 DIPN44；解释性资料，不能替代安排原文')
}


def save(path,obj):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(obj,ensure_ascii=False,indent=2,default=str)+'\n','utf-8')


def main():
    base=ROOT/'research/benchmarks';raw=base/'_sources';raw.mkdir(parents=True,exist_ok=True)
    fetched={}
    for name,(url,note) in SOURCES.items():
        now=datetime.now(timezone.utc).isoformat()
        try:
            r=httpx.get(url,follow_redirects=True,trust_env=False,timeout=30,headers={'User-Agent':'CrossTax Research/1.0'})
            r.raise_for_status();body=r.content;sha=hashlib.sha256(body).hexdigest()
            suffix='.pdf' if body[:5]==b'%PDF-' else '.html'
            path=raw/(sha+suffix)
            if not path.exists():path.write_bytes(body)
            fetched[name]={'url':url,'final_url':str(r.url),'retrieved_at':now,'sha256':sha,'bytes':len(body),'path':str(path.relative_to(ROOT)).replace('\\','/'),'http_status':r.status_code,'note':note}
        except Exception as exc:
            fetched[name]={'url':url,'retrieved_at':now,'sha256':None,'http_status':getattr(getattr(exc,'response',None),'status_code',None),'error':type(exc).__name__,'note':note}
    version=subprocess.check_output(['D:/git/Git/cmd/git.exe','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    definitions=[
      ('CN-SG-EQUIP','中国向新加坡支付设备使用费','CN','SG','ROYALTIES','industrial_commercial_scientific_equipment','特许权','SG',['cn_sg_explanation','sg_dta_list']),
      ('CN-SG-SOFTWARE','中国向新加坡支付软件许可费','CN','SG','ROYALTIES','copyright_software_license','软件','SG',['cn_sg_explanation','sg_payments']),
      ('SG-CN-DIVIDEND','新加坡向中国支付股息','SG','CN','DIVIDENDS','corporate_dividend','股息','SG',['sg_dividends','sg_dta_list']),
      ('SG-CN-INTEREST','新加坡向中国支付利息','SG','CN','INTEREST','debt_interest','利息','SG',['sg_payments','sg_dta_list']),
      ('CN-HK-DIVIDEND','中国向香港支付股息','CN','HK','DIVIDENDS','corporate_dividend','股息','HK',['hk_arrangement','hk_explanation'])]
    report=[]
    for prefix,title,payer,recipient,income,subtype,term,partner,source_ids in definitions:
        for n in [1,2]:
            id=f'{prefix}-{n:02}';folder=base/id
            facts={'payer':payer,'recipient':recipient,'income_type':income,'transaction_subtype':subtype,'date':'2026-10-07',
              'classification_confirmed':True,'beneficial_owner':True,'recipient_tax_resident':True,'eligibility_documents':True,
              'principal_purpose_test_passed':True,'pe_effective_connection':False,'no_cn_pe_effective_connection':True,
              'recipient_tax_resident_SG':recipient=='SG','china_source':payer=='CN','shareholding_conditions_met':True}
            boundary='完整事实测试，所有资格均为设定事实，未冒充实际纳税人证明'
            target=None
            if n==2:
                if prefix=='CN-SG-EQUIP':
                    facts['transaction_subtype']='intellectual_property_license';facts['classification_confirmed']=None;target='classification_confirmed';boundary='合同实际转让知识产权使用权，不能套设备税基；需要重新分类'
                elif prefix=='CN-SG-SOFTWARE':
                    facts['classification_confirmed']=None;facts['rights_transferred']=None;target='classification_confirmed';boundary='合同只写软件费，复制/分发/服务与出售权利不明'
                elif prefix=='SG-CN-DIVIDEND':
                    facts['recipient_tax_resident']=None;facts['eligibility_documents']=None;target='recipient_tax_resident';boundary='居民与资格证明不足；影响协定资格，不反向创造国内法股息扣缴'
                elif prefix=='SG-CN-INTEREST':
                    facts['pe_effective_connection']=True;facts['no_cn_pe_effective_connection']=False;target='PE';boundary='债权所得与新加坡常设机构有效关联，不能沿用普通源泉扣缴情景'
                else:
                    facts['shareholding_conditions_met']=False;facts['beneficial_owner']=None;facts['eligibility_documents']=None;target='shareholding_conditions_met';boundary='持股、受益身份与材料不足，不能直接取协定优惠档'
            input={'facts':facts,'amount':'1000000.00','currency':'CNY'}
            expected={'tax_estimate':None,'reason':'当前正式发布规则为零；完整事实也不能绕过发布闸门','required_missing_fact':None if target=='PE' else target,'expected_pe_exception':target=='PE','professional_verdict':'not_performed'}
            found=legal_service.search({'query':term,'partner':partner,'limit':4})
            result=legal_service.assess(input)
            assertions={'no_unpublished_tax_amount':result['tax_estimate'] is None,'real_legal_query_has_hits':bool(found['results']),
              'expected_missing_fact':not target or target=='PE' or target in result['missing_facts'],
              'pe_exception':target!='PE' or result['status']=='exception_requires_analysis'}
            evidence=[]
            for hit in found['results']:
                evidence.append({k:v for k,v in hit.items() if k!='excerpt'}|{'excerpt':hit['excerpt'][:300]})
            sources=[fetched[s] for s in source_ids]
            source_complete=all(x.get('sha256') for x in sources)
            acceptance={'case_id':id,'case_type':'constructed_test','program_checks':assertions,'program_pass':all(assertions.values()),
              'sources_archived':source_complete,'legal_applicability_review':'pending','independent_model_checks':'pending',
              'professional_verdict':'not_performed','recorded_at':datetime.now(timezone.utc).isoformat()}
            save(folder/'facts.json',facts);save(folder/'sources.json',sources);save(folder/'evidence.json',evidence);save(folder/'expected.json',expected)
            save(folder/'actual.json',{'code_base_commit':version,'new_code_sha256':hashlib.sha256((ROOT/'web/legal_service.py').read_bytes()).hexdigest(),
              'recorded_at':datetime.now(timezone.utc).isoformat(),'input':input,'legal_search':found,'assessment':result,'model_run':None})
            save(folder/'acceptance.json',acceptance)
            (folder/'case.md').write_text(f'# {id}｜{title}\n\n类型：明确构造的程序测试；官方案号：无。\n\n{boundary}。金额 1,000,000 CNY、日期 2026-10-07 是构造事实。\n\n依据官方原件及项目历史条文研究，未完成对该日期的全部修订、双方国内法、MLI 和程序适用检查。\n\n资料详见 facts/sources/evidence/expected/actual/acceptance JSON。\n\nAI 可能会说错，请注意甄别。\n','utf-8')
            notes='''1. 区分付款方向与所得权利，先检查国内法再比较协定。
2. 当前检索命中是历史候选或研究指南，不能自动选作现行法。
3. 逐条核对源泉、主体、居民、受益身份、PE、资格和程序；未完成项目保留缺口。
4. 公式为金额 × 税基比例 × 税率；本例不预填无法证明的税率。
5. 本次实际调用只读法律检索和确定性计算接口底层服务，记录在 actual.json。
6. 正式规则为零，预期 tax_estimate=null；反例必须识别分类、资格或 PE 问题。
7. 后续独立模型检查和全部法律适用核查分别记录，程序通过不能替代专业通过。
'''
            if prefix=='SG-CN-DIVIDEND':
                notes+='8. IRAS 股息说明要求区分国内法不扣税与协定上限；资料不足不应自动生成源泉税。\n'
            (folder/'analysis.md').write_text('# 分析与产品运用\n\n'+notes+'\n产品用于演示提问、缺失事实追问、检索定位和边界回归。\n\nAI 可能会说错，请注意甄别。\n','utf-8')
            report.append(acceptance)
    save(base/'first_ten_acceptance.json',{'cases':report,'program_pass':sum(x['program_pass'] for x in report),
      'count':10,'professional_pass':0,'model_checks_complete':0,'official_sources':fetched})
    print(json.dumps({'count':10,'program_pass':sum(x['program_pass'] for x in report),'sources_archived':sum(bool(x.get('sha256')) for x in fetched.values()),'professional_pass':0},ensure_ascii=False))


if __name__=='__main__':main()
