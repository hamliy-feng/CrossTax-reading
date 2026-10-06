(function(){
"use strict";
const APP_VERSION="2026.10.06-conversations-v2";
const $=id=>document.getElementById(id);
const providers=[
  {id:"deepseek",name:"DeepSeek 官方",url:"https://api.deepseek.com",model:"deepseek-flash"},
  {id:"qwen",name:"阿里云百炼 · 千问",url:"https://dashscope.aliyuncs.com/compatible-mode/v1",model:"qwen-plus"},
  {id:"doubao",name:"火山方舟 · 豆包",url:"https://ark.cn-beijing.volces.com/api/v3",model:"doubao-seed-2-1-pro-260628"},
  {id:"kimi",name:"Kimi · Moonshot",url:"https://api.moonshot.cn/v1",model:"kimi-k3"},
  {id:"zhipu",name:"智谱 · GLM",url:"https://open.bigmodel.cn/api/paas/v4",model:"glm-5.2"}
];
const sampleFacts=()=>({payer:"",payee:"",income:"",date:"",place:""});
const exampleQuestions={
  quick:["哪些信息能决定一笔跨境支付的税务分类？","什么是税收居民身份？","税收协定与国内法是什么关系？","如何查找有效的双边协定？"],
  deep:["中国企业向新加坡企业支付服务费，需要分别核查哪些法律？","中国居民取得境外股息，如何建立跨境税务研究证据链？","如何核对一份税收协定的有效版本和议定书？","跨境经营如何研究常设机构认定条件？"],
  audit:["审查跨境服务合同，需要提取哪些税务事实？","审核一份国际税务研究报告，有哪些关键核查项？","交易方案涉及不同司法辖区，如何识别信息缺口？","如何核对一项税负计算的事实、税基和依据？"]
};
let nextId=2;
const state={
  view:"research",mode:"deep",lang:"zh",activeId:1,busy:false,controller:null,
  connected:false,configured:false,networkChecked:false,networkError:"",model:"",provider:"deepseek",base:"",
  cases:[{id:1,title:"跨境服务费研究",messages:[],facts:{payer:"中国",payee:"新加坡",income:"服务费",date:"",place:""}}]
};
function e(tag,cls,text){const el=document.createElement(tag);if(cls)el.className=cls;if(text!==undefined)el.textContent=translate(String(text));return el;}

const translations = {
 "把复杂税务问题研究清楚。":"Research cross-border tax with clarity.",
 "先确认事实，再审查税务风险。":"Confirm facts before reviewing tax issues.",
 "从一个具体问题开始。":"Start with a tax question.",
 "围绕事实、法规版本和完整证据链展开研究。没有足够依据时明确保留待核实事项。":"Organize facts, legal versions and evidence before drawing conclusions.",
 "审查合同、交易方案与既有税务报告。实际法规结论以可核验来源为准。":"Review contracts, business structures and existing reports against supporting evidence.",
 "快速了解国际税务概念和核查路径，不把一般介绍当作正式税务意见。":"Explore international tax concepts and verification steps.",
 "执行记录 · ":"Execution log · ",
 "进行中":"Running","失败":"Failed","已结束":"Finished","展开":"Expand","收起":"Collapse",
 "我的问题":"My question","AI 研究结果":"AI research","系统提示":"System",
 "我的案例":"My cases","全球税法检索":"Tax law search","国际税收协定对照":"Treaty comparison","税收协定对照":"Treaty comparison",
 "出海税务清单":"Outbound tax checklist","合同审查":"Contract review","法规变更提醒":"Regulatory alerts",
 "税额计算":"Tax calculation","方案比较":"Scenario comparison","交易事实":"Transaction facts",
 "合同税务审查工作台":"Contract tax review","税额计算器":"Tax calculator",
 "合法业务方案比较":"Business scenario comparison","合规清单":"Compliance checklist",
 "返回研究会话":"Back to research","带条件发起研究 ↗":"Start research ↗",
 "研究对象":"Research scope","协定双方":"Treaty parties","更新":"Update","模型输出结束":"Response finished",
 "交易事实校验":"Transaction fact check","专业法规检索":"Legal source lookup","模型请求":"Model request",
 "研究中断":"Research interrupted","用户已停止此次输出":"Stopped by user",
 "功能入口已预留。相关法源、正式规则和计算器未接通；不会伪造结果。":"This workspace is being developed.",
 "尚无已验证的法规证据":"No verified legal evidence",
 "当前案例尚无可显示的法规引用。":"No verified citations available for this case.",
 "未找到": "Not found",
 "快速咨询":"Quick consult","深度研究":"Deep research","业务审查":"Business review",
 "中国企业向境外支付服务费，需要核查什么？":"What tax issues arise when a Chinese company pays overseas service fees?",
 "中国税收居民取得境外股息，如何研究？":"How should a Chinese tax resident research foreign dividends?",
 "两国税收协定应如何确定适用版本？":"How can I verify which treaty version applies?",
 "如何检查跨境交易是否涉及常设机构？":"How do I assess permanent establishment risks?",
 "中国企业向新加坡企业支付服务费，需要分别核查哪些法律？":"Which tax laws apply when a Chinese company pays a Singapore company for services?",
 "中国居民取得境外股息，如何建立跨境税务研究证据链？":"How to build an evidence trail for foreign dividends?",
 "如何核对一份税收协定的有效版本和议定书？":"How can I verify a tax treaty and its protocols?",
 "跨境经营如何研究常设机构认定条件？":"How to research permanent establishment conditions?",
 "哪些信息能决定一笔跨境支付的税务分类？":"What facts determine a cross-border payment's tax classification?",
 "什么是税收居民身份？":"What is tax residency?",
 "税收协定与国内法是什么关系？":"How do tax treaties interact with domestic laws?",
 "如何查找有效的双边协定？":"How do I find applicable bilateral tax treaties?",
 "审查跨境服务合同，需要提取哪些税务事实？":"Which tax facts should be extracted from a cross-border contract?",
 "审核一份国际税务研究报告，有哪些关键核查项？":"How to audit an international tax research report?",
 "交易方案涉及不同司法辖区，如何识别信息缺口？":"How to identify information gaps in a cross-border transaction?",
 "如何核对一项税负计算的事实、税基和依据？":"How to verify facts, tax base and evidence in a tax calculation?",
 "服务费":"Service fees","股息":"Dividends","利息":"Interest","特许权使用费":"Royalties",
 "雇佣所得":"Employment income","资本利得":"Capital gains","其他 / 待分类":"Other / Unclassified",
 "请选择":"Please select"
};
const staticI18n = {
  newCase:"＋ New research",showMyCases:"My cases",showLawSearch:"Tax law search",
  showTreatyCompare:"Treaty comparison",openOutboundChecklist:"Outbound tax checklist · Coming soon",
  openContractWorkbench:"Contract review · Coming soon",openRuleWatch:"Regulatory alerts · Coming soon",
  openSettings:"⚙ API settings",headerSettings:"⚙ Settings",exportCase:"Export research record ↗",
  saveFacts:"Save case facts",taskPlaceholder:"About this module",
  tabFacts:"Facts",tabEvidence:"Evidence",tabTasks:"Tasks",
  attachFile:"＋ Attach file",
  rightHeading:"Facts & evidence",rightBasic:"Basic details",rightSubheading:"Completeness",
  settingsTitle:"API settings",closeSettings:"Cancel",saveSettings:"Save & switch",
  settingsProviderLabel:"Model provider",settingsBaseLabel:"Official API base URL",
  settingsModelLabel:"Model ID",settingsKeyLabel:"API key",
  leftRecent:"Recent research",leftExtensions:"Extensions",caseSearchPlaceholder:"Search cases",
  payerLabel:"Payer jurisdiction",payeeLabel:"Recipient jurisdiction",incomeLabel:"Income / transaction type",
  eventDateLabel:"Transaction date",placeLabel:"Place of performance",
  factsNote:"Please confirm all relevant facts before final tax treatment.",
  evidenceTitle:"No verified legal evidence",
  evidenceNote:"No verified citations available for this case."
};
const originalText={};
function translate(s){return state.lang==="en"?(translations[s]||s):s;}
function applyLocale(){
  document.documentElement.lang=state.lang==="en"?"en":"zh-CN";
  Object.entries(staticI18n).forEach(([id,en])=>{
    const el=$(id);if(!el)return;
    if(!(id in originalText))originalText[id]=el.textContent;
    el.textContent=state.lang==="en"?en:originalText[id];
  });
  const modeTitles={quick:"Quick consult",deep:"Deep research",audit:"Business review"};
  document.querySelectorAll("[data-mode]").forEach(btn=>{
    if(!btn.dataset.originalZh)btn.dataset.originalZh=btn.textContent;
    btn.textContent=state.lang==="en"?modeTitles[btn.dataset.mode]:btn.dataset.originalZh;
  });
  document.querySelectorAll("#income option").forEach(opt=>{
    if(!opt.dataset.zh)opt.dataset.zh=opt.textContent;
    opt.textContent=state.lang==="en"?(translations[opt.dataset.zh]||opt.dataset.zh):opt.dataset.zh;
  });
  $("langToggle").textContent=state.lang==="en"?"中":"EN";
  $("langToggle").setAttribute("aria-label",state.lang==="en"?"切换为中文":"Switch to English");
  const labels={
    caseSearch:["搜索案例","Search cases"],
    prompt:[state.mode==="deep"?"描述跨境交易、司法辖区、时间及需要研究的问题……":state.mode==="audit"?"粘贴合同条款、业务方案或报告摘要，开始业务审查……":"输入一个国际税务问题……",state.mode==="deep"?"Describe transaction, jurisdictions, tax period and question…":state.mode==="audit"?"Paste contract clauses or report extracts for review…":"Ask a tax question…"],
    payer:["如：中国","e.g. China"],payee:["如：新加坡","e.g. Singapore"],
    place:["未确定可留空","Leave blank if unknown"],
    providerKey:["仅本机输入，不会写入项目文件","Local input only; not written to project files"]
  };
  Object.entries(labels).forEach(([id,arr])=>{if($(id))$(id).placeholder=arr[state.lang==="en"?1:0]});
}
function switchLocale(){state.lang=state.lang==="zh"?"en":"zh";render();updateNetwork(state.connected,state.configured,state.provider,state.model);}

function cur(){return state.cases.find(x=>x.id===state.activeId)}
function words(text){return String(text||"").trim()}
function renderNav(){
  const list=$("caseList");list.replaceChildren();
  const term=words($("caseSearch").value).toLowerCase();
  const sorted=[...state.cases].sort((a,b)=>(b.updated_at||0)-(a.updated_at||0));
  sorted.filter(c=>c.title.toLowerCase().includes(term)||
    (c.messages||[]).some(m=>(m.text||"").toLowerCase().includes(term))).forEach(c=>{
    const row=e("div","conversation-row");
    const b=e("button","case-item",c.title);
    b.type="button";b.title=c.title;
    b.setAttribute("aria-current",String(c.id===state.activeId&&state.view==="research"));
    b.addEventListener("click",()=>{if(state.busy&&state.activeId!==c.id)return;state.activeId=c.id;state.view="research";render();$("sidebar").classList.remove("show")});
    const more=e("button","conversation-more","⋯");
    more.type="button";more.title=state.lang==="en"?"Conversation actions":"会话操作";
    more.setAttribute("aria-label",(state.lang==="en"?"Manage: ":"管理：")+c.title);
    more.addEventListener("click",()=>{
      const open=row.querySelector(".conversation-menu");
      if(open){open.remove();return}
      document.querySelectorAll(".conversation-menu").forEach(n=>n.remove());
      const menu=e("div","conversation-menu");
      const rename=e("button","",state.lang==="en"?"Rename":"重命名");
      const del=e("button","delete","删除");
      rename.addEventListener("click",()=>{menu.remove();renameConversation(c.id)});
      del.addEventListener("click",()=>{menu.remove();deleteConversation(c.id)});
      menu.append(rename,del);row.append(menu);
    });
    row.append(b,more);list.append(row);
  });
  [["showMyCases","cases"],["showLawSearch","law"],["showTreatyCompare","treaty"]].forEach(pair=>{
    $(pair[0]).classList.toggle("active",state.view===pair[1]);
  });
}
async function renameConversation(id){
  const c=state.cases.find(x=>x.id===id);if(!c)return;
  const next=window.prompt(state.lang==="en"?"Conversation title":"修改会话名称",c.title);
  if(next===null||!words(next))return;
  c.title=words(next).slice(0,140);c.updated_at=Date.now()/1000;
  await saveCase(c);render();
}
async function deleteConversation(id){
  const c=state.cases.find(x=>x.id===id);if(!c)return;
  if(!window.confirm(state.lang==="en"?"Delete this conversation and its history?":"确定删除此会话及其聊天记录？"))return;
  try{
    const rsp=await fetch("/api/cases/delete",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({id})});
    if(!rsp.ok)throw Error("HTTP "+rsp.status);
    state.cases=state.cases.filter(x=>x.id!==id);
    if(state.cases.length===0){newCase();return}
    if(state.activeId===id)state.activeId=state.cases[0].id;
    state.view="research";render();
  }catch(err){notice("删除失败："+err.message)}
}
function setView(view){if(state.busy){notice("当前研究仍在输出，请等待完成或点击停止。");return}saveFacts(false);state.view=view;render();$("sidebar").classList.remove("show");$("prompt").focus()}
function renderMode(){
  document.querySelectorAll("[data-mode]").forEach(x=>x.setAttribute("aria-pressed",String(x.dataset.mode===state.mode)));
  $("prompt").placeholder=state.lang==="en"?(state.mode==="deep"?"Describe transaction, jurisdictions, tax period and question…":state.mode==="audit"?"Paste contract clauses or report extracts for review…":"Ask a tax question…"):(state.mode==="deep"?"描述跨境交易、司法辖区、时间及需要研究的问题……":state.mode==="audit"?"粘贴合同条款、业务方案或报告摘要，开始业务审查……":"输入一个国际税务问题……");
}
function toolCards(){
  const wrap=e("div","workspace-tools");
  [
   {label:"合同审查",action:()=>showFeature("合同税务审查工作台")},
   {label:"税额计算",action:()=>showFeature("税额计算器")},
   {label:"方案比较",action:()=>showFeature("合法方案比较")},
   {label:"合规清单",action:()=>{setTab("tasks");if(innerWidth<931)$("inspector").classList.add("show")}}
  ].forEach(x=>{const b=e("button","tool-card",x.label+" ↗");b.type="button";b.addEventListener("click",x.action);wrap.appendChild(b)});
  return wrap;
}
function renderWelcome(){
  const intro=e("div","intro"),h=e("h2","",state.mode==="deep"?"把复杂税务问题研究清楚。":state.mode==="audit"?"先确认事实，再审查税务风险。":"从一个具体问题开始。");
  const p=e("p","",state.mode==="deep"?"围绕事实、法规版本和完整证据链展开研究。没有足够依据时明确保留待核实事项。":state.mode==="audit"?"审查合同、交易方案与既有税务报告。实际法规结论以可核验来源为准。":"快速了解国际税务概念和核查路径，不把一般介绍当作正式税务意见。");
  intro.append(h,p);
  const grid=e("div","suggestions");
  exampleQuestions[state.mode].forEach(q=>{
    const b=e("button","",q);b.type="button";b.addEventListener("click",()=>{$("prompt").value=q;$("prompt").focus()});grid.appendChild(b);
  });
  intro.append(grid,toolCards());
  if(location.protocol==="file:" || (!state.connected && state.networkChecked)){
    const tip=e("div","connection-help");
    const a=document.createElement("a");
    a.href="http://127.0.0.1:8765/";
    a.textContent=state.lang==="en"?"Open CrossTax app":"打开 CrossTax 应用";
    a.target="_self";
    tip.append(document.createTextNode(state.networkError||(state.lang==="en"?"The local app service is not connected. Start web/start_frontend.bat, then ":"网页尚未连接本地服务。先双击 web/start_frontend.bat，再")),a);
    intro.append(tip);
  }
  return intro;
}
function drawTrace(m){
  const box=e("div","flow-trace");
  const head=e("div","flow-head");
  head.append(e("span","", "执行记录 · "+(m.running?"进行中":m.error?"失败":"已结束")));
  const t=e("button","flow-reveal",m.expanded===false?"展开":"收起");
  t.addEventListener("click",()=>{m.expanded=m.expanded===false?true:false;renderMessages()});
  head.append(t);box.append(head);
  if(m.expanded===false)return box;
  const lines=e("div","flow-lines");
  (m.events||[]).forEach(ev=>{
    const r=e("div","flow-line");r.append(e("span","flow-time",ev.time||""));
    r.append(e("span","",ev.label||""));
    if(ev.detail)r.append(e("span","flow-status "+(ev.type==="error"?"error":ev.type==="warning"?"warn":"")," · "+ev.detail));
    lines.append(r);
  });
  box.append(lines);return box;
}
function renderCalculation(tool){
  const card=e("div","sensitivity");
  if(tool.type!=="turnover_margin_examples")return card;
  card.append(e("div","sensitivity-title",state.lang==="en"?"Executed: turnover sensitivity":"实际执行：营业额情景计算"));
  const cells=e("div","sensitivity-rows");
  tool.margin_assumptions.forEach((margin,i)=>{
    const cell=e("div","sensitivity-cell");
    cell.append(e("span","",margin+"%"+(state.lang==="en"?" gross margin":" 假设毛利率")));
    cell.append(e("strong","",Number(tool.gross_profit_examples[i]).toLocaleString(state.lang==="en"?"en-US":"zh-CN")));
    cells.append(cell);
  });
  card.append(cells,e("div","sensitivity-note",state.lang==="en"?"Amounts use the same, unspecified currency as turnover. These are NOT tax liabilities.":"与营业额同币种（当前未明确）。假设毛利≠应税所得≠应纳税额。"));
  return card;
}

let renderQueued=false;
function scheduleRender(){if(renderQueued)return;renderQueued=true;requestAnimationFrame(()=>{renderQueued=false;renderMessages()})}

function escapeHtml(text){
  return String(text??"").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;").replace(/'/g,"&#39;");
}
function inlineMarkdown(text){
  return escapeHtml(text)
    .replace(/\x60([^\x60]+)\x60/g,"<code>$1</code>")
    .replace(/\*\*([^*\n]+)\*\*/g,"<strong>$1</strong>")
    .replace(/\[([^\]]{1,120})\]\((https?:\/\/[^\s)<>"']{1,1200})\)/g,function(_m,label,url){
      return '<a href="'+url.replace(/&amp;/g,"&")+'" target="_blank" rel="noopener noreferrer">'+label+"</a>";
    });
}
function markdownToSafeHtml(markdown){
  const lines=String(markdown||"").replace(/\r\n/g,"\n").split("\n");
  let out=[], list="", code=false, table=false;
  const endList=()=>{if(list){out.push("</"+list+">");list=""}};
  const endTable=()=>{if(table){out.push("</tbody></table>");table=false}};
  for(let i=0;i<lines.length;i++){
    const line=lines[i], trim=line.trim();
    if(/^\x60{3}/.test(trim)){
      endList();endTable();
      out.push(code?"</code></pre>":"<pre><code>");code=!code;continue;
    }
    if(code){out.push(escapeHtml(line)+"\n");continue}
    if(!trim){endList();endTable();continue}
    const mdTable=trim.startsWith("|")&&trim.endsWith("|");
    if(mdTable){
      const current=trim.split("|").slice(1,-1).map(x=>x.trim());
      const rule=current.every(x=>/^:?-{3,}:?$/.test(x));
      if(rule)continue;
      endList();
      if(!table){out.push('<table class="md-table"><tbody>');table=true}
      out.push("<tr>"+current.map(cell=>"<td>"+inlineMarkdown(cell)+"</td>").join("")+"</tr>");
      continue;
    }
    endTable();
    const h=trim.match(/^(#{1,4})\s+(.+)$/);
    if(h){endList();const level=Math.min(4,h[1].length+1);out.push("<h"+level+">"+inlineMarkdown(h[2])+"</h"+level+">");continue}
    const ul=trim.match(/^[-*]\s+(.+)$/),ol=trim.match(/^\d+\.\s+(.+)$/);
    if(ul||ol){
      const tag=ul?"ul":"ol";
      if(list!==tag){endList();out.push("<"+tag+">");list=tag}
      out.push("<li>"+inlineMarkdown((ul||ol)[1])+"</li>");continue;
    }
    endList();out.push("<p>"+inlineMarkdown(trim)+"</p>");
  }
  endList();endTable();if(code)out.push("</code></pre>");
  return out.join("\n");
}

function renderMessages(){
  const inner=$("streamInner");inner.replaceChildren();
  if(state.view!=="research"){renderToolView(inner);return}
  const c=cur();
  if(!c.messages.length){inner.append(renderWelcome());return}
  c.messages.forEach(m=>{
    const row=e("div","message "+m.role);
    row.append(e("div","msg-label",m.role==="user"?"我的问题":m.role==="assistant"?"AI 研究结果":"系统提示"));
    if(m.role==="assistant"&&m.events)row.append(drawTrace(m));
    if(m.role==="assistant"&&Array.isArray(m.tools))m.tools.forEach(tool=>row.append(renderCalculation(tool)));
    if(m.text){
      if(m.role==="assistant"){const body=e("div","markdown-output");body.innerHTML=markdownToSafeHtml(m.text);row.append(body)}
      else row.append(e("div","msg-body",m.text));
    }
    inner.append(row);
  });
  $("stream").scrollTop=$("stream").scrollHeight;
}
function viewShell(title,desc){
  const c=e("div","screen-view");c.append(e("h2","",title),e("p","",desc));return c;
}
function makePanel(title,desc){
  const card=e("div","panel-line");card.append(e("h3","",title),e("p","",desc));return card;
}
function renderToolView(root){
  const c=state.view;
  if(c==="cases"){
    const wrap=viewShell("我的案例","所有案例均保留在当前页面会话中。正式项目持久化尚待与 CrossTax Case API 联调。");
    state.cases.forEach(x=>{
      const b=e("button","case-item",x.title+" ↗");b.addEventListener("click",()=>{state.activeId=x.id;state.view="research";render()});wrap.appendChild(b);
    });root.appendChild(wrap);return;
  }
  if(c==="law"||c==="treaty"){
    const isLaw=c==="law";
    const wrap=viewShell(isLaw?"全球税法检索":"国际税收协定对照",
     isLaw?"输入法域、税种、法律问题，组织成带时间条件的检索请求；真实法律检索 API 尚未接通。":"指定两方司法辖区与纳税期间，形成协定研究任务。尚未连接协定版本/MLI 核验接口。");
    const p=e("div","panel-line");p.append(e("h3","",isLaw?"研究对象":"协定双方"));
    const pair=e("div","pair");
    const a=e("input","field-like");a.placeholder=isLaw?"国家或司法辖区，如中国":"司法辖区 A，如中国";
    const b=e("input","field-like");b.placeholder=isLaw?"税种，如企业所得税":"司法辖区 B，如新加坡";
    pair.append(a,b);p.append(pair);
    const date=e("input","field-like");date.type="date";date.style.marginTop="10px";date.setAttribute("aria-label","研究日期");p.append(date);
    const btn=e("button","simple-action","带条件发起研究 ↗");
    btn.addEventListener("click",()=>{
      if(!words(a.value)||!words(b.value)){notice("请先填写需要研究的司法辖区和税种/另一方司法辖区。");return}
      const query=isLaw?"研究"+a.value+"关于"+b.value+"的适用法律和官方原文，交易/税期参考日期："+(date.value||"待确认")+"。请列明证据缺口。":"对照"+a.value+"与"+b.value+"之间的税收协定，检查版本、所得类别、生效与执行日期、议定书和MLI修改，研究日期："+(date.value||"待确认");
      state.view="research";$("prompt").value=query;render();$("prompt").focus();
    });
    p.append(btn);wrap.append(p,makePanel("证据接口", "真实文献检索尚未连接。发起研究只能请求已配置 AI 给出待核查事项，不会自动获得已核验法条。"));root.appendChild(wrap);return;
  }
  if(c==="calculator"){
    const wrap=viewShell(state.lang==="en"?"Turnover sensitivity":"营业额与毛利情景测算",
      state.lang==="en"?"These calculations use hypothetical gross margins. They are not tax calculations.":"仅计算营业额与假设毛利率，不涉及任何国家的应纳税额。");
    const panel=e("div","panel-line");const form=e("div","field");
    const label=e("label","",state.lang==="en"?"Turnover (same currency throughout)":"营业额（单位与币种保持一致）");
    const turnover=e("input","field-like");turnover.type="number";turnover.min="0";turnover.step="1000";
    turnover.value=String(cur().extra?.turnover||10000000);form.append(label,turnover);
    const note=e("div","small-desc",state.lang==="en"?"Enter a revenue amount; 10%, 20%, 30% are illustrative gross margins.":"输入营业额；使用10%、20%、30%三档假设毛利率进行示意。");
    const output=e("div","sensitivity");
    function recompute(){
      output.replaceChildren();
      const value=Number(turnover.value);
      if(!Number.isFinite(value)||value<0||value>1e15){output.textContent=state.lang==="en"?"Enter a valid turnover.":"请输入有效的营业额。";return}
      output.append(e("div","sensitivity-title",state.lang==="en"?"Gross profit scenarios":"假设毛利测算"));
      const cells=e("div","sensitivity-rows");
      [10,20,30].forEach(pct=>{
        const cell=e("div","sensitivity-cell");
        cell.append(e("span","",pct+"%"+(state.lang==="en"?" margin":" 毛利率")));
        cell.append(e("strong","", (value*pct/100).toLocaleString(state.lang==="en"?"en-US":"zh-CN",{maximumFractionDigits:2})));
        cells.append(cell);
      });
      output.append(cells,e("div","sensitivity-note",state.lang==="en"?"Hypotheses only. Actual costs, taxable profit and applicable laws remain unverified.":"仅为情景假设；实际成本、应税利润和各地适用法律尚未核验。"));
    }
    turnover.addEventListener("input",recompute);recompute();panel.append(form,note,output);
    wrap.append(panel);
    const back=e("button","secondary-action",state.lang==="en"?"Back to research":"返回研究会话");
    back.addEventListener("click",()=>setView("research"));wrap.append(back);root.appendChild(wrap);return;
  }
  const explanations={
    checklist:["出海税务任务清单","暂未完善：未来根据实际经营法域和经审定规则，生成可执行的税务任务、责任人和证明资料。"],
    contracts:["合同税务审查工作台","暂未完善：未来提取合同主体、付款条件、所得性质和履行地点，关联合同段落与法规证据。"],
    watch:["法规变更与案例提醒","暂未完善：未来关联已保存案例和有效法律版本，在法规变化时提示需要重新核查。"],
    calculator:["税额计算器","暂未完善：需要经过专业审核和发布的计算规则。本页面绝不根据通用模型回答直接计算最终税额。"],
    scenario:["合法业务方案比较","暂未完善：未来可以建立多个真实合法方案，以相同税基和清楚的假设进行横向研究。"]
  };
  const info=explanations[c]||["研究功能","尚未完善"];
  const wrap=viewShell(info[0],info[1]);wrap.append(makePanel("当前状态","功能入口已预留。相关法源、正式规则和计算器未接通；不会伪造结果。"));
  const back=e("button","secondary-action","返回研究会话");back.addEventListener("click",()=>setView("research"));wrap.append(back);root.append(wrap);
}
function renderFacts(){
  const f=cur().facts;const keys=["payer","payee","income","date","place"];
  const ids=["payer","payee","income","eventDate","place"];ids.forEach((id,i)=>$(id).value=f[keys[i]]||"");
  const missing=[];[["payer","付款方辖区"],["payee","收款方辖区"],["income","所得类别"],["date","交易日期"],["place","履行地点"]].forEach(([k,n])=>{if(!f[k])missing.push(n)});
  const extra=cur().extra||{};
  const box=$("caseExtra");
  if(extra.turnover){
    box.classList.remove("hidden");box.replaceChildren();
    box.append(e("strong","",state.lang==="en"?"Case overview":"案例摘要"));
    box.append(e("div","",state.lang==="en"?"China parent · Hong Kong subsidiary · Singapore sales":"中国母公司 · 香港子公司 · 新加坡销售"));
    box.append(e("div","", (state.lang==="en"?"Turnover: ":"营业额：")+Number(extra.turnover).toLocaleString(state.lang==="en"?"en-US":"zh-CN")+(state.lang==="en"?" (currency unspecified)":"（币种待确认）")));
  }else{box.classList.add("hidden")}
  $("factsHint").textContent=state.lang==="en"?(missing.length?"Missing fields: "+missing.map(x=>({付款方辖区:"Payer",收款方辖区:"Recipient",所得类别:"Income type",交易日期:"Transaction date",履行地点:"Performance location"}[x]||x)).join(", ")+". User facts remain unverified.":"Basic fields entered; legal and residency facts still require verification."):(missing.length?"待补充："+missing.join("、")+"。填写并不代表法律事实得到核验。":"基础事实已填写，税收居民身份、合同细节等仍需独立核实。");
}
function saveFacts(feedback){
  const f=cur().facts;["payer","payee","income","eventDate","place"].forEach((id,i)=>{f[["payer","payee","income","date","place"][i]]=words($(id).value)});
  renderFacts();saveCase(cur());
  if(feedback){$("saveFacts").textContent="已保存";setTimeout(()=>$("saveFacts").textContent="保存当前事实",1500)}
}
function render(){
  renderNav();renderMode();renderFacts();renderMessages();
  const headers={cases:"我的案例",law:"全球税法检索",treaty:"税收协定对照",checklist:"出海税务清单",contracts:"合同审查",watch:"法规变更提醒",calculator:"税额计算",scenario:"方案比较"};
  $("currentTitle").textContent=state.view==="research"?cur().title:translate(headers[state.view]||"跨境税务研究");
  $("send").disabled=state.busy;$("send").textContent=state.busy?(state.lang==="en"?"Stop":"停止"):(state.lang==="en"?"Send ↗":"发送 ↗");
  applyLocale();
  const counter=$("contextIndicator");
  if(counter){
    const n=cur().messages.filter(x=>x.role==="user"||x.role==="assistant").length;
    counter.textContent=state.lang==="en"?"History "+n+" messages":"上下文 "+n+" 条消息";
  }
}
function newCase(){if(state.busy){notice("请等待当前研究结束后再新建案例。");return}
  const id=nextId++;state.cases.unshift({id,title:"新研究 "+id,messages:[],facts:sampleFacts()});
  state.activeId=id;state.view="research";$("prompt").value="";saveCase(cur());render();$("prompt").focus();$("sidebar").classList.remove("show");
}
function setTab(which){
  [["facts","tabFacts","factsPanel"],["evidence","tabEvidence","evidencePanel"],["tasks","tabTasks","tasksPanel"]].forEach(([x,tab,panel])=>{
    $(tab).setAttribute("aria-selected",String(which===x));$(panel).classList.toggle("hidden",which!==x);
  });
}
function notice(message){if(state.view!=="research")setView("research");cur().messages.push({role:"notice",text:message});renderMessages()}
function showFeature(view){const labels={ "合同税务审查工作台":"contracts","税额计算器":"calculator","合法方案比较":"scenario"};
  setView(labels[view]||view);
}
function updateNetwork(online,configured,p,m){
  state.connected=Boolean(online);state.configured=Boolean(configured);
  state.provider=p||"deepseek";state.model=m||state.model;
  const ready=state.connected&&state.configured;
  $("headerSettings").dataset.connected=String(ready);
  $("headerSettings").title=ready?(state.provider+" · "+state.model):(state.connected?"请在设置里检查密钥":"未连接 CrossTax 后端");
  $("providerSettingsForm").classList.remove("hidden");
  $("saveSettings").classList.remove("hidden");
  $("judgeStatus").classList.add("hidden");
  $("settingsFooterNote").classList.add("hidden");
  $("settingsTitle").textContent=state.lang==="en"?"API settings":"API 服务设置";
  $("settingsInfo").textContent=state.lang==="en"?"Default DeepSeek is configured on the CrossTax server. You may switch to another provider.":"默认使用 CrossTax 的 DeepSeek；也可切换服务商或填写其他 Key。";
  $("settingsState").textContent=state.lang==="en"?(ready?"Connected · "+state.model:state.connected?"The selected provider needs an API key.":"Cannot reach the local app backend."):
    (ready?"已连接 · "+state.model:state.connected?"当前服务商尚未配置有效密钥。":"无法连接 CrossTax 后端。");
  const count=$("contextIndicator");
  if(count&&state.view==="research"){
    const n=cur().messages.filter(x=>x.role==="user"||x.role==="assistant").length;
    count.textContent=state.lang==="en"?"Context: "+n+" messages":"已保留 "+n+" 条对话";
  }
}
async function refreshStatus(){
  if(location.protocol==="file:"){state.networkChecked=true;updateNetwork(false,false);renderMessages();return null}
  try{const rsp=await fetch("/api/status",{cache:"no-store"});if(!rsp.ok)throw Error("api unreachable");
    const obj=await rsp.json();if(!obj||!Array.isArray(obj.providers))throw Error("服务端响应不正确");
    if(obj.app_version!==APP_VERSION&&!(obj.workbench_enabled&&obj.app_version==="2026.10.07-workbench-v1"))throw Error("检测到旧版 CrossTax 服务。请关闭原来的 CrossTax Backend 窗口，再双击 start_frontend.bat。");
    state.networkChecked=true;state.networkError="";
    updateNetwork(true,obj.configured,obj.provider,obj.model);
    return obj;
  }catch(err){state.networkChecked=true;state.networkError=err.message||"服务连接失败";updateNetwork(false,false);if(cur().messages.length===0)renderMessages();return null}
}
function setupProviders(){
  const select=$("providerSelect");providers.forEach(p=>{const opt=e("option","",p.name);opt.value=p.id;select.append(opt)});
  select.addEventListener("change",fillProvider);fillProvider();
}
function fillProvider(){
  const p=providers.find(x=>x.id===$("providerSelect").value)||providers[0];
  $("providerBase").value=p.url;$("providerModel").value=p.model;$("providerKey").value="";
}
function openSettings(){
  $("settingsModal").classList.remove("hidden");
  updateNetwork(state.connected,state.configured,state.provider,state.model);
  $("providerSelect").value=state.provider;
  fillProvider();
  if(state.model)$("providerModel").value=state.model;
  $("providerKey").value="";
  $("providerSelect").focus();
}
async function saveSettings(){
  if(!state.connected){$("settingsState").textContent=state.lang==="en"?"Start python web/server.py first.":"未启动本地网关，无法保存 API Key。请先启动 python web/server.py。";return}
  const payload={provider:$("providerSelect").value,model:words($("providerModel").value)};
  const key=$("providerKey").value;if(key)payload.api_key=key;
  if(!payload.model){$("settingsState").textContent="请填写模型 ID。";return}
  try{
    const rsp=await fetch("/api/settings",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(payload)});
    const json=await rsp.json();
    if(!rsp.ok||json.error)throw Error(json.error||"保存失败");
    $("providerKey").value="";
    updateNetwork(true,json.configured,json.provider,json.model);
    $("settingsModal").classList.add("hidden");
  }catch(err){$("settingsState").textContent="设置失败："+err.message}
}
function nowTime(){return new Date().toLocaleTimeString("zh-CN",{hour:"2-digit",minute:"2-digit",second:"2-digit",hour12:false})}
function addEvent(m,evt){
  m.events.push({time:nowTime(),label:evt.message||evt.stage||evt.type||"更新",detail:evt.detail||"",type:evt.type});
  if(m.events.length>70)m.events.shift();
}
async function send(){
  if(state.busy)return;
  const prompt=words($("prompt").value);if(!prompt)return;
  if(state.view!=="research")state.view="research";saveFacts(false);
  const c=cur(),previous=c.messages.filter(m=>m.role==="user"||m.role==="assistant").slice(-30).map(m=>({role:m.role,content:m.text})).filter(x=>x.content);
  if(!c.messages.length&&c.title.startsWith("新研究 "))c.title=prompt.slice(0,23)+(prompt.length>23?"…":"");
  c.messages.push({role:"user",text:prompt});$("prompt").value="";c.updated_at=Date.now()/1000;saveCase(c);
  if(!state.connected||!state.configured){
    await refreshStatus();
    if(!state.connected||!state.configured){
      const fromFile=location.protocol==="file:";
      const hint=fromFile?"当前打开的是本地 HTML 文件，未连接后端。请双击 web/start_frontend.bat，再打开 http://127.0.0.1:8765/":
        state.connected?"当前服务商未配置可用 API Key。请点击右上角设置，选择 DeepSeek 或填写其他服务商 Key。":
        "无法连接本机 CrossTax 服务。请运行 web/start_frontend.bat 并使用 http://127.0.0.1:8765/ ，不要直接打开 index.html。";
      c.messages.push({role:"notice",text:state.lang==="en"?"CrossTax backend unavailable. Launch start_frontend.bat and open http://127.0.0.1:8765/":hint});
      await saveCase(c);render();return;
    }
  }
  const assistant={role:"assistant",text:"",events:[],tools:[],running:true,expanded:true};c.messages.push(assistant);
  state.busy=true;render();
  const control=new AbortController();state.controller=control;
  $("send").disabled=false;$("send").textContent="停止";
  let finished=false;
  try{
    const rsp=await fetch("/api/research",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({case_id:c.id,prompt,mode:state.mode,language:state.lang,facts:c.facts,history:previous}),signal:control.signal});
    if(!rsp.ok||!rsp.body){
      let detail="";
      try{const response=await rsp.json();detail=response.error||""}catch(_){}
      throw Error(detail||"研究请求失败（HTTP "+rsp.status+"）");
    }
    const reader=rsp.body.getReader(),decoder=new TextDecoder();let pending="";
    while(true){
      const next=await reader.read();if(next.done)break;pending+=decoder.decode(next.value,{stream:true});
      let index;while((index=pending.indexOf("\n"))>=0){
        const line=pending.slice(0,index);pending=pending.slice(index+1);if(!line.trim())continue;
        let evt;try{evt=JSON.parse(line)}catch(_){continue}
        if(evt.type==="delta"){assistant.text+=evt.text||""}
        else if(evt.type==="tool_result"){if(evt.result)assistant.tools.push(evt.result);addEvent(assistant,{type:"ok",message:evt.message||"工具已执行",detail:"确定性计算完成"});}
        else if(evt.type==="finish"){finished=true;addEvent(assistant,{type:"ok",message:"模型输出结束",detail:evt.usage?"Token "+evt.usage:""});}
        else if(evt.type==="error"){assistant.error=true;addEvent(assistant,{type:"error",message:"执行失败",detail:evt.message||"请检查服务设置"});if(!assistant.text)assistant.text=evt.message||"模型调用失败，请检查模型与网络设置。";}
        else if(evt.type==="step"){addEvent(assistant,{type:evt.level==="warning"?"warning":"ok",message:evt.message||"执行节点",detail:evt.detail||""})}
      }
      scheduleRender();
    }
    if(!finished&&!assistant.error)addEvent(assistant,{type:"warning",message:"连接已结束",detail:"未收到完成标记"});
    if(!assistant.text&&!assistant.error)assistant.text="未获得可展示的模型输出。可查看执行记录确认错误或未接入项目。";
  }catch(err){
    assistant.error=true;addEvent(assistant,{type:"error",message:"连接中断",detail:err.name==="AbortError"?"用户已停止此次输出":err.message});
    if(!assistant.text)assistant.text=err.name==="AbortError"?"已停止生成。":"请求失败："+err.message;
  }finally{assistant.running=false;state.busy=false;state.controller=null;c.updated_at=Date.now()/1000;await saveCase(c);render()}
}
function exportCase(){
  saveFacts(false);const c=cur();
  const rows=["# "+c.title,"","CrossTax 前端工作记录。模型输出不代表经审定的法律意见；法规证据请以实际接通的法律工具和专业核验为准。","","## 事实"];
  Object.entries(c.facts).forEach(([k,v])=>rows.push("- "+k+"："+(v||"未填写")));
  c.messages.forEach(m=>{rows.push("","## "+(m.role==="user"?"用户问题":m.role==="assistant"?"模型答复":"系统提示"),m.text||"");if(m.events){rows.push("### 实际执行事件");m.events.forEach(evt=>rows.push("- "+evt.time+" "+evt.label+" "+(evt.detail||"")))}});
  const url=URL.createObjectURL(new Blob([rows.join("\n")],{type:"text/markdown;charset=utf-8"}));
  const a=e("a");a.href=url;a.download="CrossTax_研究记录_"+c.id+".md";document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
$("newCase").addEventListener("click",newCase);
$("showMyCases").addEventListener("click",()=>setView("cases"));
$("showLawSearch").addEventListener("click",()=>setView("law"));
$("showTreatyCompare").addEventListener("click",()=>setView("treaty"));
$("openOutboundChecklist").addEventListener("click",()=>setView("checklist"));
$("openContractWorkbench").addEventListener("click",()=>setView("contracts"));
$("openRuleWatch").addEventListener("click",()=>setView("watch"));

$("headerSettings").addEventListener("click",openSettings);
$("langToggle").addEventListener("click",switchLocale);
$("closeSettings").addEventListener("click",()=>$("settingsModal").classList.add("hidden"));
$("saveSettings").addEventListener("click",saveSettings);
$("settingsModal").addEventListener("click",ev=>{if(ev.target===$("settingsModal"))$("settingsModal").classList.add("hidden")});
$("caseSearch").addEventListener("input",renderNav);
document.querySelectorAll("[data-mode]").forEach(b=>b.addEventListener("click",()=>{if(!state.busy){state.mode=b.dataset.mode;state.view="research";render()}}));
$("send").addEventListener("click",()=>{if(state.busy&&state.controller)state.controller.abort();else send()});
$("prompt").addEventListener("keydown",ev=>{if(ev.key==="Enter"&&!ev.shiftKey&&!ev.isComposing){ev.preventDefault();send()}});
$("saveFacts").addEventListener("click",()=>saveFacts(true));
$("tabFacts").addEventListener("click",()=>{saveFacts(false);setTab("facts")});
$("tabEvidence").addEventListener("click",()=>{saveFacts(false);setTab("evidence")});
$("tabTasks").addEventListener("click",()=>{saveFacts(false);setTab("tasks")});
$("taskPlaceholder").addEventListener("click",()=>setView("checklist"));
$("showInspector").addEventListener("click",()=>{$("inspector").classList.toggle("show");$("sidebar").classList.remove("show")});
$("showCases").addEventListener("click",()=>{$("sidebar").classList.toggle("show");$("inspector").classList.remove("show")});
$("exportCase").addEventListener("click",exportCase);
$("attachFile").addEventListener("click",()=>$("filePicker").click());
$("filePicker").addEventListener("change",ev=>{$("fileLabel").textContent=ev.target.files.length?ev.target.files[0].name+"（本地选择，尚未上传）":""});
async function loadSavedCases(){
  if(location.protocol==="file:")return;
  try{
    const rsp=await fetch("/api/cases",{cache:"no-store"});if(!rsp.ok)throw Error("HTTP "+rsp.status);
    const result=await rsp.json();if(!Array.isArray(result.cases))throw Error("Invalid case list");
    const rows=result.cases.filter(c=>Number.isInteger(c.id)&&c.id>=1&&typeof c.title==="string"&&c.facts&&Array.isArray(c.messages));
    if(!rows.length){
      await saveCase(cur());
      render();return;
    }
    state.cases=rows.map(c=>({...c,messages:c.messages.map(m=>({...m,running:false})),facts:{...sampleFacts(),...c.facts}}));
    nextId=Math.max(2,...rows.map(c=>c.id+1));
    state.activeId=state.cases[0].id;state.view="research";render();
  }catch(err){
    console.warn("CrossTax history loading failed:",err.message);
    const status=$("contextIndicator");
    if(status)status.textContent="历史记录暂未同步";
  }
}
const saveQueues=new Map();
function saveCase(c){
  if(location.protocol==="file:"||!state.connected||!c)return Promise.resolve(false);
  const id=c.id;
  const payload=JSON.stringify(c);
  const previous=saveQueues.get(id)||Promise.resolve();
  const next=previous.catch(()=>{}).then(async()=>{
    const rsp=await fetch("/api/cases",{method:"POST",headers:{"Content-Type":"application/json"},body:payload});
    if(!rsp.ok)throw Error("HTTP "+rsp.status);
    return true;
  }).catch(err=>{
    console.warn("CrossTax history save failed:",err.message);
    const hint=$("contextIndicator");if(hint)hint.textContent="本地保存失败";
    return false;
  });
  saveQueues.set(id,next);
  return next;
}
if(typeof window!=="undefined"&&window.installCrossTaxWorkbench){
  const handlers=window.installCrossTaxWorkbench({$,state,e,cur,providers,sampleFacts,markdownToSafeHtml,renderWelcome,
    originalRender:render,originalNav:renderNav,originalMessages:renderMessages,originalToolView:renderToolView,
    originalSend:send,originalSave:saveCase,originalLoad:loadSavedCases,originalExport:exportCase,setNextId:id=>{nextId=id}});
  send=handlers.send;saveCase=handlers.saveCase;renderNav=handlers.renderNav;renderMessages=handlers.renderMessages;
  renderToolView=handlers.renderToolView;render=handlers.render;exportCase=handlers.exportCase;loadSavedCases=handlers.loadSavedCases;
}
setupProviders();render();refreshStatus().then(loadSavedCases).catch(err=>{const hint=$("contextIndicator");if(hint)hint.textContent=err.message});
})();
