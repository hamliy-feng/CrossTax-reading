/* Workbench controls reuse the original green three-column shell. */
window.installCrossTaxWorkbench=function(ctx){
  const {$,state,e,cur,markdownToSafeHtml,originalRender,originalNav,originalToolView}=ctx;
  const wb={enabled:false,projects:[],selected:new Set(),projectFilter:"all",files:[],attached:[],recommendations:[],operation:null};
  const disclaimer="AI 可能会说错，请注意甄别。";
  let restoreTimer=null,restoreWaiting=false;
  function restoreRunning(){clearTimeout(restoreTimer);if(!wb.enabled||state.busy||restoreWaiting||!cur()?.messages?.some(m=>m.status==="running"))return;
    restoreTimer=setTimeout(async()=>{restoreWaiting=true;try{await refreshCases()}catch(err){feedback(err.message)}finally{restoreWaiting=false;restoreRunning()}},2500)}
  async function api(path,body,method){
    const opts={method:method||(body?"POST":"GET"),cache:"no-store"};
    if(body){opts.headers={"Content-Type":"application/json"};opts.body=JSON.stringify(body)}
    const rsp=await fetch(path,opts);let data;
    if(!rsp.ok){try{data=await rsp.json()}catch(_){}throw Error(data?.error||"请求失败（"+rsp.status+"）")}
    return rsp.json();
  }
  function feedback(text){$("contextIndicator").textContent=text}
  function run(fn){return async()=>{try{await fn()}catch(err){feedback(err.message)}}}
  function button(text,fn,cls="secondary-action"){const b=e("button",cls,text);b.type="button";b.addEventListener("click",async()=>{if(b.disabled)return;b.disabled=true;try{await fn()}catch(err){feedback(err.message)}finally{b.disabled=false}});return b}
  function dialog(title){
    document.querySelectorAll("dialog.wb-dialog").forEach(d=>d.remove());
    const d=e("dialog","wb-dialog"),h=e("h2","",title),body=e("div","wb-dialog-body"),status=e("p","small-desc"),close=button("关闭",()=>d.close());
    d.append(h,body,status,close);document.body.append(d);d.addEventListener("close",()=>d.remove());d.showModal();
    return {d,body,status};
  }
  function path(c){const map=new Map(c.messages.map(m=>[m.id,m]));let leaf=c.active_leaf,out=[],seen=new Set();
    while(leaf&&!seen.has(leaf)){seen.add(leaf);const m=map.get(leaf);if(!m)break;if(!m.deleted)out.push(m);leaf=m.parent_id}return out.reverse()}
  async function refreshCases(){const result=await api("/api/cases");
    state.cases=result.cases.map(c=>({...c,facts:{...ctx.sampleFacts(),...c.facts}}));
    if(!state.cases.length){const c={id:Math.floor(Math.random()*800000000)+100000000,title:"新研究",messages:[],facts:ctx.sampleFacts()};const r=await api("/api/cases",c);state.cases=[r.case]}
    if(!state.cases.some(c=>c.id===state.activeId))state.activeId=state.cases[0].id;
    ctx.setNextId(Math.max(...state.cases.map(c=>c.id))+1);render();
  }
  const queues=new Map();
  function saveCase(c){if(!wb.enabled)return ctx.originalSave(c);if(!c)return Promise.resolve(false);
    const pending=queues.get(c.id)||Promise.resolve();
    const next=pending.catch(()=>{}).then(async()=>{
      const r=await api("/api/cases",{id:c.id,title:c.title,facts:c.facts,extra:c.extra,revision:c.revision||0});
      c.revision=r.revision;return true;
    }).catch(err=>{feedback(err.message);return false});queues.set(c.id,next);return next;
  }
  function renderNav(){if(!wb.enabled)return originalNav();
    const root=$("caseList");root.replaceChildren();
    const bar=e("div","wb-projects");bar.append(button("＋ 项目",async()=>{const d=dialog("创建项目"),input=e("input","search");input.placeholder="项目名称";d.body.append(input,button("创建",async()=>{await api("/api/projects",{title:input.value});d.d.close();await refreshProjects()}))}));
    [["all","全部对话"],["none","未分类"],...wb.projects.map(p=>[p.id,p.title])].forEach(([id,title])=>{
      const b=button(title,()=>{wb.projectFilter=id;renderNav()},"navbtn nav-mini"+(wb.projectFilter===id?" active":""));bar.append(b);
    });root.append(bar);
    const project=wb.projects.find(p=>p.id===wb.projectFilter);
    if(project){const actions=e("div","wb-toolbar");
      actions.append(button("汇总",()=>openSummaries(project)),button("改名",()=>{const d=dialog("项目名称"),i=e("input","search");i.value=project.title;d.body.append(i,button("保存",async()=>{await api("/api/projects/"+project.id,{title:i.value},"PATCH");d.d.close();await refreshProjects()}))}),
        button("删除",()=>{const d=dialog("删除项目"),note=e("p","","对话会移回未分类。已生成报告仍保留在存储中。");d.body.append(note,button("删除文件夹",async()=>{await api("/api/projects/"+project.id,null,"DELETE");wb.projectFilter="all";d.d.close();await refreshProjects();await refreshCases()}))}));root.append(actions)}
    if(wb.selected.size){const move=e("select","search"),opt=e("option","","移动到…");opt.value="";move.append(opt);
      [["none","未分类"],...wb.projects.map(p=>[p.id,p.title])].forEach(([id,t])=>{const o=e("option","",t);o.value=id;move.append(o)});
      move.addEventListener("change",run(async()=>{if(!move.value)return;await api("/api/projects/move",{case_ids:[...wb.selected],project_id:move.value==="none"?null:move.value});wb.selected.clear();await refreshCases()}));root.append(e("p","small-desc","已选 "+wb.selected.size+" 段对话"),move)}
    const term=$("caseSearch").value.toLowerCase();
    state.cases.filter(c=>(wb.projectFilter==="all"||(wb.projectFilter==="none"?!c.project_id:c.project_id===wb.projectFilter))&&
      (c.title.toLowerCase().includes(term)||c.messages.some(m=>(m.text||"").toLowerCase().includes(term)))).forEach(c=>{
        const row=e("div","conversation-row"),check=e("input","wb-check");check.type="checkbox";check.checked=wb.selected.has(c.id);check.setAttribute("aria-label","选择 "+c.title);
        check.addEventListener("change",()=>{check.checked?wb.selected.add(c.id):wb.selected.delete(c.id);renderNav()});
        const b=button(c.title,()=>{if(state.busy&&state.activeId!==c.id)return;state.activeId=c.id;state.view="research";wb.recommendations=[];render()},"case-item"+(c.id===state.activeId?" active":""));
        const more=button("…",()=>{const d=dialog("对话操作"),i=e("input","search");i.value=c.title;d.body.append(i,button("保存名称",async()=>{c.title=i.value;if(await saveCase(c))d.d.close();render()}),button("删除对话",async()=>{await api("/api/cases/delete",{id:c.id});wb.selected.delete(c.id);d.d.close();await refreshCases()}))},"conversation-more");row.append(check,b,more);root.append(row)
      });
  }
  function renderMessages(){if(!wb.enabled)return ctx.originalMessages();
    const inner=$("streamInner");inner.replaceChildren();if(state.view!=="research"){renderToolView(inner);return}
    const c=cur(),messages=path(c);
    if(!messages.length){inner.append(ctx.renderWelcome());return}
    messages.forEach(m=>{
      const row=e("div","message "+m.role);row.append(e("div","msg-label",m.role==="user"?"我的问题":"答复"));
      if(m.text){const body=e("div",m.role==="assistant"?"markdown-output":"msg-body");
        if(m.role==="assistant")body.innerHTML=markdownToSafeHtml(m.text);else body.textContent=m.text;row.append(body)}
      if(m.status&&m.status!=="complete")row.append(e("p","small-desc",{running:"正在生成…",failed:"执行未完成，可以重试",interrupted:"输出中断，当前内容已保存",legacy_imported:"已导入原有记录"}[m.status]||m.status));
      if(m.tools?.length){const details=e("details","wb-tools"),summary=e("summary","","工具与来源（"+m.tools.length+"）");details.append(summary);
        m.tools.forEach(t=>{details.append(e("h4","",t.name+" · "+(t.status==="complete"?"已执行":"未完成")));
          const result=t.output||{};(result.results||[]).forEach(x=>{const item=e("div","wb-source");
            item.append(e("strong","",x.official_title||x.title||x.id));
            const url=x.original_url||x.url;if(url&&/^https?:\/\//.test(url)){const a=e("a","","原文 ↗");a.href=url;a.target="_blank";a.rel="noopener noreferrer";item.append(a)}
            item.append(e("p","small-desc",(x.article_number?"条款 "+x.article_number+" · ":"")+(x.pdf_page_start?"页 "+x.pdf_page_start:x.page_num?"页 "+x.page_num:"")+" · "+(x.version_id||"")),e("p","",x.excerpt||x.content||""));details.append(item)});
          if(result.chunks)result.chunks.forEach(x=>details.append(e("p","small-desc",x.locator+" · "+x.text.slice(0,400))));
          if(result.status||result.error)details.append(e("p","small-desc",result.status||result.error));
          if(result.evidence_id)details.append(e("p","small-desc","证据快照："+result.evidence_id));
        });row.append(details)
      }
      const actions=e("div","wb-toolbar");actions.append(button("复制",()=>navigator.clipboard.writeText(m.text||"")));
      if(m.role==="user")actions.append(button("编辑重发",()=>{if(state.busy)return;const d=dialog("编辑问题"),i=e("textarea","search");i.value=m.text;d.body.append(i,button("发送新分支",async()=>{wb.operation={operation:"edit",message_id:m.id};$("prompt").value=i.value;d.d.close();await send()}))}));
      else if(m.status==="running")actions.append(button("停止输出",async()=>{await api(`/api/cases/${c.id}/stop`,{});await refreshCases()}));
      else actions.append(button("重新生成",async()=>{if(state.busy)return;wb.operation={operation:"regenerate",message_id:m.id};await send()}));
      actions.append(button("删除",async()=>{if(state.busy)return;await api(`/api/cases/${c.id}/messages/${m.id}`,null,"DELETE");await refreshCases()}));
      const siblings=c.messages.filter(x=>x.role===m.role&&x.parent_id===m.parent_id&&!x.deleted);
      if(siblings.length>1){const s=e("select","wb-branch");siblings.forEach((x,i)=>{const o=e("option","","版本 "+(i+1));o.value=x.id;o.selected=x.id===m.id;s.append(o)});
        s.addEventListener("change",run(async()=>{await api(`/api/cases/${c.id}/branch`,{message_id:s.value});await refreshCases()}));actions.append(s)}
      row.append(actions);inner.append(row);
    });
    if(wb.recommendations.length){const box=e("div","wb-recommendations");box.append(e("p","small-desc","接着讨论"));wb.recommendations.forEach(q=>box.append(button(q,async()=>{if(state.busy)return;$("prompt").value=q;wb.recommendations=[];await send()})));inner.append(box)}
    $("stream").scrollTop=$("stream").scrollHeight;
  }
  function renderToolView(root){if(!wb.enabled||!["law","treaty","calculator"].includes(state.view))return originalToolView(root);
    root.append(e("h2","",state.view==="calculator"?"税务计算":state.view==="treaty"?"协定资料检索":"法律资料检索"));
    if(state.view==="calculator"){
      root.append(e("p","small-desc","输入交易事实和金额。通过发布条件的规则可返回税额，其余列出缺口；使用人输入的税率仅用于条件算例。"));
      const form=e("div","wb-tax-form"),conditions=e("details","wb-tax-conditions"),out=e("div","wb-result"),fields={},labels={
        payer:"付款方法域",recipient:"收款方法域",income_type:"所得类型",transaction_subtype:"交易性质",date:"交易日期",
        classification_confirmed:"交易性质已确认",beneficial_owner:"收款方符合受益所有人条件",recipient_tax_resident:"收款方具有所选法域税收居民身份",
        eligibility_documents:"优惠申请所需证明齐全",principal_purpose_test_passed:"符合主要目的测试",pe_effective_connection:"所得是否与常设机构存在有效关联",
        shareholding_conditions_met:"股息持股比例及期限满足条件",china_source:"所得来源于中国",no_cn_pe_effective_connection:"所得与中国常设机构无有效关联",recipient_tax_resident_SG:"收款方为新加坡税收居民"};
      function field(key,label,control,container=form){control.id="wbTax_"+key;fields[key]=control;const wrap=e("label","wb-tax-field");wrap.htmlFor=control.id;wrap.append(e("span","",label),control);container.append(wrap);return control}
      function input(key,label,type,value,container=form){const x=e("input","search");x.type=type;x.value=value;return field(key,label,x,container)}
      function select(key,label,options,container=form){const x=e("select","search");options.forEach(([value,text])=>{const option=e("option","",text);option.value=value;x.append(option)});return field(key,label,x,container)}
      input("payer",labels.payer,"text","中国");input("recipient",labels.recipient,"text","新加坡");
      fields.payer.placeholder=fields.recipient.placeholder="国家或地区，如中国、新加坡、香港，或两位代码";
      select("scenario","交易性质",[["ROYALTIES|industrial_commercial_scientific_equipment","设备使用费"],["ROYALTIES|copyright_software_license","软件许可费"],["ROYALTIES|other_royalty","其他特许权使用费"],["DIVIDENDS|corporate_dividend","公司股息"],["INTEREST|debt_interest","债务利息"]]);
      const today=new Date();input("date",labels.date,"date",today.getFullYear()+"-"+String(today.getMonth()+1).padStart(2,"0")+"-"+String(today.getDate()).padStart(2,"0"));
      input("amount","支付金额","number","").min="0";select("currency","币种",[["CNY","人民币 CNY"],["USD","美元 USD"],["SGD","新加坡元 SGD"],["HKD","港元 HKD"],["EUR","欧元 EUR"]]);
      conditions.append(e("summary","","交易条件（不确定时保留“尚不清楚”）"));
      ["classification_confirmed","beneficial_owner","recipient_tax_resident","eligibility_documents","principal_purpose_test_passed","pe_effective_connection","shareholding_conditions_met","china_source"].forEach(key=>select(key,labels[key],[["","尚不清楚"],["true","是"],["false","否"]],conditions));
      const examples=e("details","wb-tax-conditions");examples.append(e("summary","","可选：按自己输入的假设做算例"));
      input("assumed_rate","假设税率（%）","number","",examples).min="0";fields.assumed_rate.max="100";fields.assumed_rate.step="0.0001";
      input("assumed_portion","计入税基的比例（%）","number","100",examples).min="0";fields.assumed_portion.max="100";fields.assumed_portion.step="0.0001";
      examples.append(e("p","small-desc","只有主动填写税率才生成算例；该税率不会被当作已确认的法定税率。"));
      const aliases={中国:"CN",中国大陆:"CN",新加坡:"SG",香港:"HK",中国香港:"HK",英国:"GB",美国:"US",日本:"JP",德国:"DE",法国:"FR",澳大利亚:"AU",韩国:"KR",马来西亚:"MY",泰国:"TH",越南:"VN",印度尼西亚:"ID"};
      function jurisdiction(value){const key=value.trim(),code=aliases[key]||key.toUpperCase();if(!/^[A-Z]{2}$/.test(code))throw Error("请选择国家或填写两位法域代码");return code}
      // Send exact decimal strings. Floating point is used only for display.
      function percentDecimal(value){if(!/^\d{1,3}(?:\.\d{1,4})?$/.test(value)||Number(value)>100)throw Error("比例应为 0–100，最多四位小数");const [whole,part=""]=value.split(".");if(Number(value)===100)return "1";return "0."+String(Number(whole)).padStart(2,"0")+part}
      root.append(form,conditions,examples,button("计算",async()=>{
        if(!fields.amount.value)throw Error("请填写支付金额");
        const [income_type,transaction_subtype]=fields.scenario.value.split("|"),facts={payer:jurisdiction(fields.payer.value),recipient:jurisdiction(fields.recipient.value),income_type,transaction_subtype,date:fields.date.value};
        Object.keys(labels).forEach(key=>{if(fields[key]&&["true","false"].includes(fields[key].value))facts[key]=fields[key].value==="true"});
        if(facts.pe_effective_connection!==undefined)facts.no_cn_pe_effective_connection=facts.pe_effective_connection===false;
        if(facts.recipient_tax_resident!==undefined)facts["recipient_tax_resident_"+facts.recipient]=facts.recipient_tax_resident;
        const payload={facts,amount:fields.amount.value,currency:fields.currency.value};
        if(fields.assumed_rate.value!="")payload.assumptions={nominal_rate:percentDecimal(fields.assumed_rate.value),taxable_fraction:percentDecimal(fields.assumed_portion.value)};
        out.replaceChildren(e("p","","正在检查交易条件…"));const result=(await api("/api/tax/assess",payload)).result;
        const statuses={facts_missing:"还需要补充交易事实",rule_not_published:"尚无匹配的正式规则",approved:"按匹配规则计算",version_conflict:"适用版本存在冲突",exception_requires_analysis:"需要分析常设机构及当地税制"};
        out.replaceChildren(e("h3","",statuses[result.status]||"交易评估"));
        if(result.tax_estimate!==null)out.append(e("p","","税额："+result.tax_estimate+" "+result.currency));
        if(result.conditional_example){const x=result.conditional_example;out.append(e("p","","假设算例："+x.amount+" "+x.currency),e("p","small-desc",result.amount+" × "+String(Number(x.taxable_fraction)*100)+"% × "+String(Number(x.nominal_rate)*100)+"%"),e("p","small-desc",x.basis))}
        if(result.missing_facts.length){out.append(e("h4","","需要补充"));const list=e("ul");result.missing_facts.forEach(key=>list.append(e("li","",labels[key]||"匹配规则所需条件："+key)));out.append(list)}
        result.conflicts.forEach(text=>out.append(e("p","",text)));
        if(result.rule_version)out.append(e("p","small-desc","规则版本："+result.rule_version.id+"；适用起日："+result.rule_version.effective_from));
        (result.sources||[]).forEach(source=>{const url=source.original_url||source.url;if(url&&/^https?:\/\//.test(url)){const a=e("a","",source.official_title||source.title||"查看来源原文");a.href=url;a.target="_blank";a.rel="noopener";out.append(a)}});
        out.append(e("p","small-desc","AI 可能会说错，请注意甄别。"));
      }),out);return
    }
    const query=e("input","search"),partner=e("input","search"),out=e("div","wb-search-results");query.placeholder="关键词，如特许权、股息";partner.placeholder="法域代码（可留空），如 SG、HK";
    root.append(query,partner,button("检索法律库",async()=>{const r=await api("/api/legal/search",{query:query.value,partner:partner.value||null});out.replaceChildren();
      if(!r.results.length)out.append(e("p","","没有命中，尝试修改关键词。"));r.results.forEach(x=>{const card=e("div","wb-source");card.append(e("h3","",x.official_title),e("p","small-desc",x.applicability_note),e("p","",x.excerpt));if(x.original_url){const a=e("a","","原文 ↗");a.href=x.original_url;a.target="_blank";a.rel="noopener noreferrer";card.append(a)}card.append(e("p","small-desc","证据快照："+r.evidence_id+" · "+(x.version_id||"")+" · 页 "+(x.pdf_page_start||x.page_num||"")));out.append(card)})}),out)
  }
  function render(){originalRender();if(wb.enabled){$("send").disabled=false;$("attachFile").textContent="＋ 上传文件";$("prompt").placeholder="输入问题，或描述你想完成的工作……";$("fileLabel").textContent=wb.attached.length?"已选 "+wb.attached.length+" 个附件":"";restoreRunning()}}
  async function send(){if(!wb.enabled)return ctx.originalSend();if(state.busy)return;
    const op=wb.operation||{},prompt=$("prompt").value.trim();if(!prompt&&op.operation!=="regenerate")return;
    const c=cur();state.view="research";
    if(!await saveCase(c))return;
    state.busy=true;wb.recommendations=[];wb.operation=null;$("prompt").value="";render();
    const control=new AbortController();let stopping=false;
    state.controller={abort:async()=>{if(stopping)return;stopping=true;try{await api(`/api/cases/${c.id}/stop`,{});control.abort()}catch(err){feedback(err.message);stopping=false}}};
    try{
      const rsp=await fetch("/api/research",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({case_id:c.id,prompt,mode:state.mode,language:state.lang,file_ids:wb.attached,web_search:$("wbWebSearch").checked,...op}),signal:control.signal});
      if(!rsp.ok){const x=await rsp.json();throw Error(x.error||"请求未完成")}
      const reader=rsp.body.getReader(),decoder=new TextDecoder();let pending="",assistant=null,finished=null;
      while(true){const x=await reader.read();if(x.done)break;pending+=decoder.decode(x.value,{stream:true});let pos;
        while((pos=pending.indexOf("\n"))>=0){const line=pending.slice(0,pos);pending=pending.slice(pos+1);if(!line)continue;const evt=JSON.parse(line);
          if(evt.type==="started"){Object.assign(c,evt.case);assistant=c.messages.find(m=>m.id===evt.message_id)}
          else if(evt.type==="delta"&&assistant)assistant.text+=evt.text||"";
          else if(evt.type==="tool_result"&&assistant)assistant.tools.push(evt.result);
          else if(evt.type==="finish"){Object.assign(c,evt.case);finished=evt.message_id}
          else if(evt.type==="error")feedback(evt.message);
        }renderMessages();
      }
      if(finished){try{const r=await api("/api/recommendations/generate",{case_id:c.id,message_id:finished});if(cur().id===c.id&&c.active_leaf===finished)wb.recommendations=r.questions||[]}catch(_){} }
    }catch(err){if(err.name!=="AbortError")feedback(err.message)}
    finally{state.busy=false;state.controller=null;wb.attached=[];await refreshCases();render()}
  }
  function exportCase(){if(!wb.enabled)return ctx.originalExport();const a=e("a");a.href=`/api/cases/${cur().id}/export`;a.download="CrossTax.md";a.click()}
  async function refreshProjects(){wb.projects=(await api("/api/projects")).projects;renderNav()}
  async function openFiles(){const d=dialog("资料库");const r=await api("/api/files");wb.files=r.files;
    if(!r.files.length)d.body.append(e("p","","点击输入区的上传按钮添加资料。"));
    r.files.forEach(f=>{const row=e("div","wb-file-row"),check=e("input");check.type="checkbox";check.checked=wb.attached.includes(f.id);check.setAttribute("aria-label","选择 "+f.name);check.addEventListener("change",()=>{wb.attached=check.checked?[...new Set([...wb.attached,f.id])]:wb.attached.filter(x=>x!==f.id);render()});
      row.append(check,e("span","",f.name+" · "+f.status));const a=e("a","","下载");a.href=`/api/files/${f.id}/download`;row.append(a,button("删除",async()=>{await api("/api/files/"+f.id,null,"DELETE");wb.attached=wb.attached.filter(x=>x!==f.id);row.remove();render()}));d.body.append(row)})
  }
  async function openSummaries(project){const d=dialog(project.title+" · 汇总作品"),selected=new Set(),fileSelected=new Set();
    state.cases.filter(c=>c.project_id===project.id).forEach(c=>{const l=e("label","wb-file-row"),i=e("input");i.type="checkbox";i.checked=wb.selected.has(c.id);if(i.checked)selected.add(c.id);i.addEventListener("change",()=>i.checked?selected.add(c.id):selected.delete(c.id));l.append(i,e("span","",c.title));d.body.append(l)});
    const files=(await api("/api/files")).files;
    files.forEach(f=>{const l=e("label","wb-file-row"),i=e("input");i.type="checkbox";i.addEventListener("change",()=>i.checked?fileSelected.add(f.id):fileSelected.delete(f.id));l.append(i,e("span","","资料："+f.name));d.body.append(l)});
    const goal=e("textarea","search");goal.placeholder="汇总目标：例如整理市场进入方案，标明证据、分歧和待办";d.body.append(goal);
    const list=e("div");async function show(){const r=await api(`/api/projects/${project.id}/summaries`);list.replaceChildren();r.summaries.forEach(s=>{const item=e("details","wb-summary"),h=e("summary","","版本 "+s.version+" · "+s.goal+(s.stale?" · 内容有变化，可重新生成":"")),text=e("div","markdown-output");text.innerHTML=markdownToSafeHtml(s.text);const a=e("a","","导出 Markdown");a.href=`/api/summaries/${s.id}/export`;item.append(h,text,a);list.append(item)})}
    d.body.append(button("生成新版本",async()=>{d.status.textContent="正在汇总…";try{await api(`/api/projects/${project.id}/summaries`,{case_ids:[...selected],file_ids:[...fileSelected],goal:goal.value});d.status.textContent="已保存新版本";await show()}catch(err){d.status.textContent=err.message}}),list);await show()
  }
  async function account(){const session=await api("/api/auth/session"),d=dialog(session.user?"账号":"登录 / 注册");
    if(session.user){d.body.append(e("p","",session.user.email),button("退出登录",async()=>{await api("/api/auth/sign-out",{});d.d.close();location.reload()}));return}
    const email=e("input","search"),password=e("input","search"),name=e("input","search"),token=e("input","search");email.type="email";email.placeholder="邮箱";email.autocomplete="email";password.type="password";password.placeholder="密码";password.autocomplete="current-password";name.placeholder="称呼（注册时填写）";token.placeholder="密码重置令牌（收到邮件后填写）";
    d.body.append(email,password,name,token);if(!session.email_configured)d.status.textContent="邮箱服务待配置；游客可以使用当前工作台。";
    async function action(path,body){try{const r=await api("/api/auth/"+path,body);d.status.textContent=r.message;if(path==="sign-in/email"){d.d.close();await refreshCases();await refreshProjects();await identity()}}catch(err){d.status.textContent=err.message}}
    d.body.append(button("登录",()=>action("sign-in/email",{email:email.value,password:password.value})),button("注册",()=>action("sign-up/email",{email:email.value,password:password.value,name:name.value})),button("发送验证邮件",()=>action("send-verification-email",{email:email.value})),button("找回密码",()=>action("request-password-reset",{email:email.value})),button("设置新密码",()=>action("reset-password",{token:token.value,newPassword:password.value})));
    [["github","GitHub · 演示跳转"],["google","Google · 演示跳转"]].forEach(([provider,t])=>{const a=e("a","secondary-action",t);a.href="/api/auth/"+provider;a.target="_blank";a.rel="noopener";d.body.append(a)});d.body.append(e("p","small-desc","演示入口返回后继续使用游客身份。"))
  }
  async function identity(){const s=await api("/api/auth/session");$("wbAccount").textContent=s.user?s.user.email:"游客 / 登录"}
  async function openRecommendations(){const d=dialog("智能追问设置"),p=await api("/api/recommendations/settings"),on=e("input"),label=e("label","wb-file-row");on.type="checkbox";on.checked=p.enabled;label.append(on,e("span","","回答后推荐追问"));const provider=e("select","search"),model=e("input","search"),key=e("input","search"),count=e("input","search");key.type="password";key.placeholder="独立 Key（留空使用服务端配置）";count.type="number";count.min="0";count.max="4";count.value=p.count;ctx.providers.forEach(x=>{const o=e("option","",x.name);o.value=x.id;provider.append(o)});provider.value=p.provider;model.value=p.model;
    provider.addEventListener("change",()=>model.value=ctx.providers.find(x=>x.id===provider.value).model);
    d.body.append(label,e("label","","独立推荐服务商"),provider,e("label","","推荐模型"),model,key,e("label","","问题数量（0–4）"),count,button("保存",async()=>{await api("/api/recommendations/settings",{enabled:on.checked,provider:provider.value,model:model.value,api_key:key.value,count:Number(count.value)});key.value="";d.d.close()}))
  }
  async function loadSavedCases(){const status=await api("/api/status");wb.enabled=!!status.workbench_enabled;if(!wb.enabled)return ctx.originalLoad();
    $("attachFile").textContent="＋ 上传文件";$("filePicker").accept=".pdf,.docx,.txt,.md,.csv,.xlsx";$("filePicker").multiple=true;
    $("filePicker").addEventListener("change",run(async()=>{for(const file of $("filePicker").files){if(file.size>25*1024*1024){feedback("单文件上限为 25 MiB");continue}const form=new FormData();form.append("file",file);feedback("正在解析 "+file.name);const rsp=await fetch("/api/files",{method:"POST",body:form});const r=await rsp.json();if(!rsp.ok)throw Error(r.error);wb.attached.push(r.id)}$("filePicker").value="";render()}));
    const header=$("headerSettings").parentElement;const accountBtn=button("游客 / 登录",account,"top-action");accountBtn.id="wbAccount";header.insertBefore(accountBtn,$("headerSettings"));
    const tools=e("div","wb-toolbar"),webLabel=e("label","wb-file-row"),web=e("input");web.type="checkbox";web.id="wbWebSearch";webLabel.append(web,e("span","","网页搜索"));tools.append(webLabel,button("资料库",openFiles),button("智能追问",openRecommendations));$("modeBar").append(tools);
    $("evidenceTitle").textContent="证据与来源";$("evidenceNote").textContent="每条答复中的“工具与来源”可展开实际检索结果、原文定位和证据快照。";document.querySelectorAll("#evidencePanel .check-row").forEach(x=>x.remove());
    await refreshCases();await refreshProjects();await identity();
    const url=new URL(location.href);if(url.searchParams.get("reset")){const t=url.searchParams.get("token");await account();if(t){const input=document.querySelector("dialog input[placeholder^='密码重置令牌']");if(input)input.value=t}history.replaceState(null,"",location.pathname)}
  }
  return {send,saveCase,renderNav,renderMessages,renderToolView,render,exportCase,loadSavedCases};
};
