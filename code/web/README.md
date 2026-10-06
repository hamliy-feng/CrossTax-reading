# CrossTax｜应用前端与 AI API

## 当前工作台（2026-10-07）

有效入口 `web/workbench.py`，版本 `2026.10.07-workbench-v1`。Windows 脚本优先使用项目 `.venv`；项目根目录也可运行：

```powershell
python -m pip install -r requirements.txt
python -m uvicorn workbench:app --app-dir web --host 127.0.0.1 --port 8765 --workers 1
```

默认 DeepSeek Key 从环境变量或本项目私有凭据文件读取；不写入网页和聊天。普通聊天不要求税务事实。本期增加项目、多选移动、UUID 消息分支、编辑重发、重生成、停止、六格式私有附件、实际专库检索、Decimal 条件计算、版本汇总及独立智能追问（默认关闭）。文件上限 25 MiB；扫描件与损坏文档保留真实解析状态。

本地保存到忽略的 `web/state/workbench.sqlite3` 和 `web/state/files/`。同一原 Cookie 的旧游客记录可一次性迁入，不覆盖新记录；云端不读取本机私人聊天。云端配置必须使用专属 PostgreSQL、私有对象存储和 Neon Auth，不能把 Render 临时磁盘当持久化。配置见[本期部署指引](../research/handoffs/2026-10-07_delivery/03_Web工作台与云端部署方案.md)与根目录 `render.yaml`。

本次 48 项 Python、JS 模拟及 14 项法律发布安全回归通过；实际浏览器/DeepSeek 聊天、法律工具、附件读取、项目汇总及追问缓存成功。真实服务重启后已完成记录、原件 SHA 不变，未完成回答保留部分正文并标记中断。

尚未完成：云端上线、真实邮箱验证/找回/跨设备、Tavily 调用、云端对象存储及大陆不同网络验收；平台账号未连接。十个构造案例和 30 次独立研究请求完成，专业通过为 0。最终答案、汇总和导出末尾只附加一次约定提示。

详细证据见 `research/acceptance/workbench_delivery_2026-10-07.json`。下列旧版本说明是历史记录；旧 `server.py` 单独启动不提供新工作台全部功能。

项目：D:\APP\CrossTax
入口：D:\APP\CrossTax\web\start_frontend.bat
浏览器：http://127.0.0.1:8765/
应用版本：2026.10.06-conversations-v2

## 用户体验

CrossTax 是面向出海企业的国际税务研究应用，桌面端为极简三栏：
- 左：新建研究、我的案例、税法检索、协定对照、会话历史；历史可全文检索、重命名、删除。
- 中：研究对话、深度研究与业务审查流程、实时执行记录、Markdown 回答、算术情景工具。
- 右：用户录入的交易事实、法规证据与待办。尚未对接的专业法规检索不得被当作已核验数据。
- 右上：中文/English、API 设置（支持服务商和模型切换）。
- 出海税务清单、合同税务审查、法规变更提醒仍标记为“暂未完善”。

本应用没有单独的“评委版”“普通版”或强制“评委模式”。使用者一进入应用就有 DeepSeek 默认服务；可在右上角设置里切换其他厂商、模型和自带 Key。

## 本地正常启动（避免双击 HTML）

**只双击 D:\APP\CrossTax\web\start_frontend.bat**。

启动程序自动：
1. 检查本机 127.0.0.1:8765 是否运行当前版本的 CrossTax；
2. 未运行则调用 run_backend.bat 启动服务并等待就绪；
3. 启动成功后才自动打开浏览器；
4. 检测到旧版/其他程序占用端口时明确提示先关闭旧窗口，不会把旧版伪装为已启动；
5. 启动失败时查看 web/state/gateway.log 中真实 Python 错误。

**不要双击 web/index.html 作为运行入口**。纯 file:// 静态文件无法直接连接受保护的后端。前端若检测到 file:// 或无法连通服务，会提示正确的启动方法和 http://127.0.0.1:8765/ 地址。地址是本机入口，不是云端公网链接。

Windows 需要 Python 3 可用，启动脚本优先使用 py -3，其次 python。不要求 Node.js、Docker 或 VSCode。

## 模型 API

默认路由：DeepSeek 官方 https://api.deepseek.com ，模型 deepseek-flash。

本机服务器启动时从现有的 .secrets/deepseek_api_key.txt 读取默认密钥；服务器环境变量 DEEPSEEK_API_KEY 优先。不要在网页源码、用户聊天或 README 中写入明文 Key。

设置仍保留五家官方接入：
- DeepSeek
- 阿里云百炼 / 千问
- 火山方舟 / 豆包
- Moonshot / Kimi
- 智谱 GLM

选择其他提供商时在右上 API 设置填写自己的 Key。所选服务商和 Key 仅对当前浏览器会话生效，Key 保留在后端进程内存，不向前端状态接口回显；重启后台后非默认服务商需要重新配置。再次选择 DeepSeek 时可直接使用服务器预设密钥。

## 对话历史与上下文

不再使用各访客共用的 web/state/cases.json 作为主存储。新会话写入 web/state/conversations.sqlite3，按随机 HttpOnly、SameSite 浏览器 Cookie 中的会话标识隔离。浏览器正常刷新或关闭后重新打开，同一浏览器的 Cookie 仍可找到聊天记录。旧版 web/state/cases.json 在本机由第一个访问会话**一次性迁入**，保留以前的案例与模型答复；旧文件不被删除。

服务端会保存：
- 每个案例的名称、事实、消息、执行事件、算术工具结果
- 最多 150 个案例、每案例最新 120 条消息
- 查询当前用户案例，按更新时间排序、搜索标题及聊天全文
- 通过操作菜单重命名或删除会话
- 实际请求模型时从已存储案例还原历史，并限制模型上下文为最近约 30 条有效消息、最多约 36,000 字符

这是基于浏览器身份的本地聊天历史，并非多终端账户云同步。清理 Cookie 会导致已有案例与新浏览器身份分离；若未来提供账号，需要升级到用户账户鉴权与跨设备会话关联。SQLite 存储包含用户税务事实，正式上线需相应的权限/备份/加密策略。

## HTTP 接口

- GET /api/status：当前用户的服务商、模型与是否已配置；绝不返回 API Key。含 app_version 字段。
- GET /api/health：服务是否就绪，可供启动脚本/监测验证。
- POST /api/settings：可以切换服务商/模型/Key，按浏览器会话隔离，不再锁定 DeepSeek。
- GET /api/cases：读取当前浏览器的历史研究。
- POST /api/cases：保存或更新当前会话。
- POST /api/cases/delete：删除当前浏览器持有的案例。
- POST /api/research：携带 case_id、问题、事实和可选历史；服务端优先取该案例的已保存上下文，返回真实 NDJSON step/tool_result/delta/finish/error。

只有已经真实调用的工具与服务才在执行记录中显示为完成。当前正式法律证据库与经审定规则仍需单独联调。

## 运行与测试状态（2026-10-06）

- 31 项 Python 自动化测试通过：会话持久化/隔离/删改、模型上下文恢复、API 设置、静态资源、默认路由和事实算术。
- V8 前端交互检查：能恢复历史、显示上下文数量、接受问题、发起 /api/research 并保存结果。
- 当前改造后的真实后端已使用项目现有 DeepSeek 默认 Key 完成续聊，响应约 4.53 秒，按历史中国—香港—新加坡电子仪器业务生成内容，未产生 API 错误。
- 实际用户 Windows 的 Edge 图形窗口仍无法由当前 Local1 WSL2 容器直接操控；启动脚本已建立健康检查与旧版本冲突提示，但**不应将本机浏览器实际启动/视觉截图列为已验收**。

相关部署要求详见 web/DEPLOYMENT.md。
