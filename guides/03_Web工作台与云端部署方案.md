# Web 工作台与云端部署方案

代码沿用原生深绿色三栏，新增 `web/workbench.py` FastAPI 入口；`web/server.py` 保留旧网关供兼容测试。启动云端入口才能使用本期工作台接口。

## 功能与接口

| 功能 | 实际接口 | 保存与行为 |
|---|---|---|
| 聊天 | POST `/api/research` | NDJSON；后台执行与浏览器连接分离；每秒保存部分回答；断流后重新读取 |
| 项目 | GET/POST `/api/projects`，PATCH/DELETE `/api/projects/{id}` | 单项目归属，删除文件夹保留对话 |
| 多选移动 | POST `/api/projects/move` | `case_ids`、`project_id`；全部校验后同一事务移动 |
| 消息 | POST `/api/cases/{id}/branch`，DELETE `/api/cases/{id}/messages/{mid}` | UUID、parent_id、active_leaf；编辑/重生成保留分支 |
| 停止 | POST `/api/cases/{id}/stop` | 取消真实模型任务，持久保存部分内容 |
| 文件 | POST/GET `/api/files`，GET/DELETE `/api/files/{id}`，GET `/download` | 私有原件、SHA、文字与定位；25 MiB；账号初期 100 MiB |
| 网页搜索 | POST `/api/web/search` | Tavily basic、官方优先；查询/时间/结果持久记录及短缓存 |
| 法律 RAG | POST `/api/legal/search`、GET `/api/legal/evidence/{id}` | 实际全文/关键词检索；L1 与指南注明来源边界 |
| 证据快照 | GET `/api/evidence/{id}` | 答复引用的快照按账号隔离，文件删除后快照仍在 |
| 计算 | POST `/api/tax/assess` | Decimal、事实、公式、版本、来源、缺口与假设；仅现有正式视图放行 |
| 任务 | GET `/api/tasks`、GET `/api/tasks/{id}` | 状态 running/complete/interrupted/failed；重启后识别中断 |
| 汇总 | POST/GET `/api/projects/{id}/summaries` | 手动选择对话、资料和目标；不可覆盖的版本及输入快照 |
| 追问 | `/api/recommendations/settings`、`/generate`、GET `/api/recommendations` | 独立模型、默认关闭、最多四条、输入指纹缓存 |

普通聊天不强制填写税务事实。涉及税务时提供法律工具，让模型依据实际命中来源追问必要条件；网页搜索由使用人开启。文件内容及网页是资料，不能成为执行系统指令。

消息保存由服务器负责，浏览器只更新标题和事实；revision 防止不同设备覆盖。parent_id 决定当前上下文，旧分支仍存；模型上下文有容量预算，完整历史仍在存储中。删除消息使当前分支回到前驱，后代不进入新上下文。

汇总绑定当时的消息、事实、文件和工具来源。新消息或资料变化会标记旧报告可重新生成，使用人手动生成新版本。结果和导出末尾只附加一次约定提示。

## 云端数据

`crosstax` 保留法律 schema，原有发布规则不变。迁移 `033_app_workbench.sql` 增量创建 `crosstax_app.records` 和迁移版本表；kind 区分项目/对话/文件/作品/工具证据/任务/推荐/内部记录，owner_id 来自服务器验证身份，不接受客户端指定。

云端用专属 Neon PostgreSQL，附件和原件使用私有 S3 兼容对象存储。对象 key 不直接给浏览器，下载前查 owner。平台密钥放在秘密配置，Git 不保存。法律连接设只读事务和超时，应用写入仅在应用 schema。

本地 SQLite 和私有文件目录只用于本地验证，不能在 Render 免费实例上当持久存储。生产模式启动检查数据库、私有对象存储、认证及 HTTPS 来源，缺失配置拒绝启动。

## 免费平台配置与部署

1. Neon 新建专属 CrossTax Free 项目，确认仍是免费计划；不要选择自动升级。获取 PostgreSQL、Auth 和私有 bucket 的参数，保存到平台秘密变量。
2. 对现有本机专库执行只读 custom dump；先在新云库恢复 `crosstax` schema，核对每表行数、关键视图和备份 SHA。禁止恢复其他项目角色、用户聊天或 `.secrets`。原始法律文件迁移到私有 bucket，保持 SHA 与逻辑定位。
3. 在平台配置 Auth 邮箱密码、验证及找回密码，添加实际 HTTPS 为可信来源；验证邮件服务及已购域名 DNS。没有域名时先用平台 HTTPS，邮件发送能力单独实测。
4. Render 使用私有完整仓库，按根目录 `render.yaml` 创建 Free Web Service。构建 `pip install -r requirements.txt`；启动 `uvicorn workbench:app --app-dir web --host 0.0.0.0 --port $PORT --workers 1`。
5. 设置 `CROSSTAX_ENV=production`、`CROSSTAX_DATABASE_CONFIRM=crosstax`、`CROSSTAX_PUBLIC_ORIGIN`、`CROSSTAX_APP_DATABASE_URL`、`CROSSTAX_LEGAL_DATABASE_URL`、`NEON_AUTH_URL`、`AWS_ENDPOINT_URL_S3`、`AWS_ACCESS_KEY_ID`、`AWS_SECRET_ACCESS_KEY`、`CROSSTAX_FILE_BUCKET`、`DEEPSEEK_API_KEY`、`TAVILY_API_KEY`。
6. `NEON_AUTH_URL` 必须填写完整认证根路径（以实际 Console URL 为准，含 `/auth` 时不要重复拼接）；上传需 bucket 私有设置。数据库只允许本项目本机 55433/crosstax 或经确认的 Neon 官方端点。
7. 平台地址能实际访问后测试邮箱注册、验证、找回、跨浏览器及游客迁移，记录所用账号类型，不在报告中泄露邮箱或密码。

Render 免费服务闲置后休眠且本地文件系统临时；状态必须保存到 Neon。[Render Free](https://render.com/docs/free)。Neon 当前免费规模和认证说明可查 [官方计划](https://neon.com/blog/neon-free-plan-1-gb-per-project)，实施时复核容量和对象存储可用区域。法律库约 117 MiB 和原始资料约 1.3 GiB 是当前体积，不是长期无限容量保证。

Tavily 当前免费额度参见 [官方价格](https://www.tavily.com/pricing)。本应用默认每月最多预留 900 次 basic 搜索，避开自动 advanced；缓存一小时，实际引用快照持久保存。模型调用可能消耗已有 API 余额，设置每账号/全站小时限制并保留使用量。

## 账号和游客

邮箱操作经同源后端转发到 Neon 官方认证；身份通过 get-session 返回验证，不能靠前端传 user_id。服务器只返回必要用户信息，认证 Cookie 为 HttpOnly/Secure。游客使用高熵 Cookie；首次成功登录后在事务内迁移自己的游客记录，已有账号记录不覆盖。不同账号与不同游客不能获取对方文件、消息、报告或快照。

GitHub/Google 本期按钮明确为演示跳转，到官方登录页后仍保持游客，不伪造登录成功或 OAuth 用户。后续真正 OAuth 另行接回调。

## 施工与验收清单

先部署配置和持久聊天，再项目/附件/消息/搜索，最后汇总/追问/十例。每项区分“代码测试”“真实服务调用”“云端访问”。

必须测试：匿名读包；新游客不填 Key 聊天；邮箱跨设备；两个账号隔离；多选事务及项目删除；六格式/超限/扫描件；编辑和重生成旧分支；真 SQL 命中和定位；真实搜索；Decimal 边界及未发布阻断；汇总两版本与 stale；追问关闭、失败和缓存；停止及断流；重启后的历史/原件/作品；真实浏览器以及至少两种大陆网络。

当前平台凭据和域名尚未确认时，只能交付已准备的代码与配置指引，不能写虚构 HTTPS 或声明完成线上验收。最终报告写明实际冷启动、容量、已调用供应商和未完成项。

AI 可能会说错，请注意甄别。
