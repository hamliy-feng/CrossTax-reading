#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CrossTax loopback-only model gateway. Standard library only; no legal DB writes.

Run from project root: python web/server.py
Open http://127.0.0.1:8765/
Keys are in process memory only; never served to clients or written to files.
"""
from __future__ import annotations

import json
import os
import re
import secrets
import threading
import time
from http.cookies import SimpleCookie
from urllib.parse import urlparse
import chat_store
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

BASE = Path(__file__).resolve().parent
PRIVATE_DEEPSEEK_KEY = BASE.parent / ".secrets" / "deepseek_api_key.txt"
APP_VERSION = "2026.10.06-conversations-v2"
HOST = "127.0.0.1"
PORT = int(os.environ.get("CROSSTAX_WEB_PORT", "8765"))
# For HTTPS deployment put the service behind a reverse proxy and set this value.
PUBLIC_ORIGIN = os.environ.get("CROSSTAX_PUBLIC_ORIGIN", "").strip().rstrip("/")
MAX_RESEARCH_PER_HOUR = max(0, min(1000, int(os.environ.get("CROSSTAX_RESEARCH_HOURLY_LIMIT", "60"))))
RESEARCH_LOCK = threading.Lock()
RESEARCH_TIMES: list[float] = []
SESSION_SETTINGS: dict[str, dict[str, Any]] = {}
SESSION_ID_RE = re.compile(r"^[a-zA-Z0-9_-]{30,120}$")

MAX_BYTES = 4_000_000
PROVIDERS = {
    "deepseek": {"name": "DeepSeek 官方", "base": "https://api.deepseek.com", "default_model": "deepseek-flash", "env": "DEEPSEEK_API_KEY"},
    "qwen": {"name": "阿里云百炼 · 千问", "base": "https://dashscope.aliyuncs.com/compatible-mode/v1", "default_model": "qwen-plus", "env": "DASHSCOPE_API_KEY"},
    "doubao": {"name": "火山方舟 · 豆包", "base": "https://ark.cn-beijing.volces.com/api/v3", "default_model": "doubao-seed-2-1-pro-260628", "env": "ARK_API_KEY"},
    "kimi": {"name": "Kimi 官方", "base": "https://api.moonshot.cn/v1", "default_model": "kimi-k3", "env": "MOONSHOT_API_KEY"},
    "zhipu": {"name": "智谱 · GLM", "base": "https://open.bigmodel.cn/api/paas/v4", "default_model": "glm-5.2", "env": "ZHIPUAI_API_KEY"},
}
SETTINGS_LOCK = threading.RLock()
SETTINGS: dict[str, Any] = {
    "provider": "deepseek",
    "models": {key: p["default_model"] for key, p in PROVIDERS.items()},
    "keys": {},
}
MODEL_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/-]{0,119}$")
FACT_KEYS = ("payer", "payee", "income", "date", "place")
FACT_LABELS = {"payer": "付款方所在法域", "payee": "收款方所在法域", "income": "所得类别", "date": "交易日期", "place": "实际履行地点"}
ALLOWED_MODES = {"quick", "deep", "audit"}


def turnover_scenarios(prompt: str) -> dict[str, Any] | None:
    """Arithmetic sensitivity test only; does not calculate tax liabilities."""
    normalized = prompt.replace(",", "").replace("，", "").replace(" ", "")
    if not any(x in normalized for x in ("一千万", "1000万", "10000000", "一千万元")):
        return None
    amount = 10_000_000
    margin_examples = [10, 20, 30]
    return {
        "type":"turnover_margin_examples",
        "revenue":amount,
        "currency":"unspecified",
        "margin_assumptions":margin_examples,
        "gross_profit_examples":[amount * m // 100 for m in margin_examples],
        "legal_tax_computation":False
    }

CASE_LOCK = threading.RLock()


def load_local_credential() -> None:
    """Load owner's default DeepSeek credential at service startup."""
    key = os.environ.get("DEEPSEEK_API_KEY", "").strip()
    if not key and PRIVATE_DEEPSEEK_KEY.is_file():
        key = PRIVATE_DEEPSEEK_KEY.read_text(encoding="utf-8").strip()
    if key and (not key.startswith("sk-") or len(key) > 2048 or "\n" in key or "\r" in key):
        raise RuntimeError("Invalid DeepSeek backend credential")
    with SETTINGS_LOCK:
        SETTINGS["provider"] = "deepseek"
        if key:
            SETTINGS["keys"]["deepseek"] = key


def list_cases(session_id: str = "local-compat") -> list[dict[str, Any]]:
    return chat_store.list_cases(session_id)


def save_case(payload: dict[str, Any], session_id: str = "local-compat") -> dict[str, Any]:
    return chat_store.save_case(session_id, payload)


def delete_case(session_id: str, case_id: int) -> dict[str, Any]:
    return chat_store.delete_case(session_id, case_id)


def _resolved_config(session_id: str | None = None) -> tuple[str, str, str]:
    with SETTINGS_LOCK:
        local = SESSION_SETTINGS.get(session_id or "", {})
        provider = local.get("provider") or SETTINGS["provider"]
        model = local.get("model") or SETTINGS["models"][provider]
        key = local.get("keys", {}).get(provider) or SETTINGS["keys"].get(provider) or os.environ.get(PROVIDERS[provider]["env"], "")
        return provider, model, key


def current_settings(session_id: str | None = None) -> dict[str, Any]:
    """Return non-secret provider state to the active browser."""
    provider, model, key = _resolved_config(session_id)
    return {
        "provider": provider,
        "app_version": APP_VERSION,
        "default_provider": "deepseek",
        "model": model,
        "configured": bool(key),
        "providers": [
            {"id": p, "name": data["name"], "base": data["base"], "default_model": data["default_model"]}
            for p, data in PROVIDERS.items()
        ],
        "history_enabled": True,
        "context_enabled": True,
        "legal_retrieval_connected": False,
    }


def set_settings(payload: dict[str, Any], session_id: str | None = None) -> dict[str, Any]:
    provider = payload.get("provider", "")
    model = payload.get("model", "")
    if provider not in PROVIDERS:
        raise ValueError("未知或未授权的服务商")
    if not isinstance(model, str) or not MODEL_PATTERN.fullmatch(model):
        raise ValueError("模型 ID 只能包含英文、数字、点、下划线、斜线、连字符及冒号")
    key = payload.get("api_key", "")
    if not isinstance(key, str) or len(key) > 2048 or (key and ("\r" in key or "\n" in key or not key.strip())):
        raise ValueError("API Key 格式不正确")
    with SETTINGS_LOCK:
        if session_id is None:
            # Backward-compatible administration API; HTTP requests pass a browser session.
            SETTINGS["provider"] = provider
            SETTINGS["models"][provider] = model
            if key:
                SETTINGS["keys"][provider] = key.strip()
        else:
            obj = SESSION_SETTINGS.setdefault(session_id, {"keys": {}})
            obj["provider"] = provider
            obj["model"] = model
            if key:
                obj["keys"][provider] = key.strip()
    return current_settings(session_id)


def research_slot_available() -> bool:
    now = time.monotonic()
    if MAX_RESEARCH_PER_HOUR == 0:
        return True
    with RESEARCH_LOCK:
        RESEARCH_TIMES[:] = [t for t in RESEARCH_TIMES if now - t < 3600]
        if len(RESEARCH_TIMES) >= MAX_RESEARCH_PER_HOUR:
            return False
        RESEARCH_TIMES.append(now)
        return True


def facts_status(payload: dict[str, Any]) -> tuple[dict[str, str], list[str]]:
    f = payload.get("facts") or {}
    if not isinstance(f, dict):
        raise ValueError("facts 必须是对象")
    clean: dict[str, str] = {}
    missing: list[str] = []
    for key in FACT_KEYS:
        value = f.get(key, "")
        clean[key] = value.strip()[:250] if isinstance(value, str) else ""
        if not clean[key]:
            missing.append(FACT_LABELS[key])
    return clean, missing


def build_messages(payload: dict[str, Any], facts: dict[str, str]) -> list[dict[str, str]]:
    mode = payload["mode"]
    context = (
        "你是 CrossTax 国际税务研究助手，面向跨境企业、财务人员与个人。"
        "请像专业税务研究助手一样完成用户的问题：主动整理交易事实、适用的司法辖区、可能涉及的税种、计算方式与可执行的核查行动。"
        "能够从用户事实和明确假设推导的内容可以给出具体条件性分析与计算，不要把推理框架写成冗长免责声明。"
        "当前法规资料库尚未连接：不要冒充在线检索过现行法条，不编造特定条文、税率、协定生效时间或税局裁定。"
        "确实影响结论的缺失事实请有针对性追问；每个数字须说明计算假设。"
        "不要编造工具调用记录或假装有未连接的证据工具。"
    )
    if mode == "deep":
        context += "研究模式为深度研究。按事实→问题分解→待查法源→不确定性→研究待办组织回答，不输出无证据的法律结论。"
    elif mode == "audit":
        context += "研究模式为业务审查。区分用户提供的合同或报告事实与尚未验证的法律解释；给出问题清单和专业复核准备事项。"
    else:
        context += "研究模式为快速咨询，简短说明概念、研究路径与需要补证的信息。"
    fact_text = "；".join(FACT_LABELS[k] + "：" + (facts[k] or "未提供") for k in FACT_KEYS)
    if payload.get("language") == "en":
        context += " The user chose English UI. Respond in English unless the user asks otherwise."
    else:
        context += " 用户选择了中文界面，默认用中文回答。"
    messages: list[dict[str, str]] = [{"role": "system", "content": context}, {"role": "system", "content": "用户声明的案例事实（未核验）："+fact_text}]
    history = payload.get("history", [])
    if isinstance(history, list):
        # Retain up to 30 messages and roughly 36K characters of context.
        retained = []
        remaining = 36000
        for item in reversed(history[-40:]):
            if not isinstance(item, dict) or item.get("role") not in {"user", "assistant"}:
                continue
            body = item.get("content", "")
            if not isinstance(body, str) or not body.strip():
                continue
            body = body[:5500]
            if body == payload["prompt"] and not retained:
                continue
            if len(body) > remaining:
                body = body[-remaining:]
            if not body:
                break
            retained.append({"role": item["role"], "content": body})
            remaining -= len(body)
            if remaining < 500 or len(retained) >= 30:
                break
        messages.extend(reversed(retained))
    messages.append({"role": "user", "content": payload["prompt"]})
    return messages


class Handler(BaseHTTPRequestHandler):
    server_version = "CrossTaxLoopback/0.2"

    def log_message(self, format: str, *args: Any) -> None:
        # Only logs routes and status; no request bodies, credentials or tax facts.
        return

    def _session(self) -> str:
        if getattr(self, "_session_cached", None):
            return self._session_cached
        cookie = SimpleCookie()
        try:
            cookie.load(getattr(self, "headers", {}).get("Cookie", ""))
        except Exception:
            pass
        value = cookie["ct_session"].value if "ct_session" in cookie else ""
        if not SESSION_ID_RE.fullmatch(value):
            value = secrets.token_urlsafe(32)
            self._new_session = value
        self._session_cached = value
        return value

    def _headers(self, status: int, type_: str, length: int | None = None) -> None:
        self.send_response(status)
        new_session = getattr(self, "_new_session", None)
        if new_session:
            policy = "; Secure" if PUBLIC_ORIGIN else ""
            self.send_header("Set-Cookie", "ct_session=" + new_session +
                             "; Path=/; HttpOnly; SameSite=Lax; Max-Age=31536000" + policy)
            self._new_session = None
        self.send_header("Content-Type", type_)
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Frame-Options", "DENY")
        if length is not None:
            self.send_header("Content-Length", str(length))
        self.end_headers()

    def _write_json(self, status: int, value: dict[str, Any]) -> None:
        body = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self._headers(status, "application/json; charset=utf-8", len(body))
        self.wfile.write(body)

    def _check_origin(self) -> bool:
        # Browser origins allowed only for own loopback server; protects configuration against CSRF.
        host = self.headers.get("Host", "").lower()
        allowed = {f"127.0.0.1:{PORT}", f"localhost:{PORT}"}
        origins = {f"http://{x}" for x in allowed}
        if PUBLIC_ORIGIN:
            parsed = urlparse(PUBLIC_ORIGIN)
            if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
                return False
            allowed.add(parsed.netloc.lower())
            origins.add(PUBLIC_ORIGIN.lower())
        origin = self.headers.get("Origin", "").lower()
        return host in allowed and (not origin or origin in origins)

    def _input(self) -> dict[str, Any]:
        size = self.headers.get("Content-Length", "")
        if not size.isdigit() or int(size) > MAX_BYTES:
            raise ValueError("请求内容过大或缺少 Content-Length")
        raw = self.rfile.read(int(size))
        try:
            obj = json.loads(raw.decode("utf-8"))
        except (UnicodeError, json.JSONDecodeError) as exc:
            raise ValueError("请求 JSON 格式不正确") from exc
        if not isinstance(obj, dict):
            raise ValueError("请求必须是 JSON 对象")
        return obj

    def do_GET(self) -> None:
        session_id = self._session()
        if not self._check_origin():
            return self._write_json(403, {"error": "请求主机或来源不匹配"})
        path = self.path.split("?")[0]
        if path == "/api/cases":
            if not PUBLIC_ORIGIN:
                chat_store.import_legacy_first_local_session(session_id)
            return self._write_json(200, {"cases": list_cases(session_id), "storage": "sqlite"})
        if path == "/api/status":
            return self._write_json(200, current_settings(session_id))
        if path == "/api/health":
            provider, model, key = _resolved_config(session_id)
            return self._write_json(200, {"service": "crosstax", "app_version": APP_VERSION, "ready": bool(key), "provider": provider, "model": model})
        resources = {"/": ("index.html", "text/html; charset=utf-8"), "/index.html": ("index.html", "text/html; charset=utf-8"),
                     "/app.js": ("app.js", "text/javascript; charset=utf-8")}
        if path in resources:
            filename, mime = resources[path]
            data = (BASE / filename).read_bytes()
            self._headers(200, mime, len(data))
            self.wfile.write(data)
        elif path == "/favicon.ico":
            self._headers(204, "text/plain", 0)
        else:
            self._write_json(404, {"error": "未找到资源"})

    def do_POST(self) -> None:
        session_id = self._session()
        if not self._check_origin():
            return self._write_json(403, {"error": "仅允许本机同源请求"})
        try:
            payload = self._input()
            if self.path == "/api/settings":
                return self._write_json(200, set_settings(payload, session_id))
            if self.path == "/api/cases":
                return self._write_json(200, save_case(payload, session_id))
            if self.path == "/api/cases/delete":
                case_id = payload.get("id")
                return self._write_json(200, delete_case(session_id, case_id))
            if self.path == "/api/research":
                return self._research(payload)
            self._write_json(404, {"error": "接口不存在"})
        except ValueError as exc:
            self._write_json(400, {"error": str(exc)})
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _event(self, event: dict[str, Any]) -> bool:
        try:
            self.wfile.write((json.dumps(event, ensure_ascii=False) + "\n").encode("utf-8"))
            self.wfile.flush()
            return True
        except (BrokenPipeError, ConnectionResetError):
            return False

    def _research(self, payload: dict[str, Any]) -> None:
        prompt = payload.get("prompt", "")
        mode = payload.get("mode", "deep")
        if not isinstance(prompt, str) or not prompt.strip() or len(prompt) > 16000:
            raise ValueError("研究问题不能为空且不能超过 16000 字符")
        if mode not in ALLOWED_MODES:
            raise ValueError("不支持的研究模式")
        facts, missing = facts_status(payload)
        session_id = self._session()
        provider, model, key = _resolved_config(session_id)
        if not key:
            return self._write_json(503, {"error": provider + " 暂未配置可用的 API Key，请在右上角设置中填写"})
        if not research_slot_available():
            return self._write_json(429, {"error": "研究请求较频繁，请稍后重试"})
        endpoint = PROVIDERS[provider]["base"] + "/chat/completions"
        case_id = payload.get("case_id")
        if type(case_id) is int and 1 <= case_id <= 10**9:
            case_record = chat_store.get_case(session_id, case_id)
            if case_record:
                stored_history = [
                    {"role": msg["role"], "content": msg["text"]}
                    for msg in case_record["messages"]
                    if msg.get("role") in ("user", "assistant") and msg.get("text")
                ]
                if stored_history:
                    payload = dict(payload, history=stored_history)
        messages = build_messages(payload, facts)
        scenarios = turnover_scenarios(prompt)
        if scenarios is not None:
            messages.insert(2, {"role":"system", "content":"确定性算术情景（不是税务判断）：营业额 10,000,000，币种未确认；假设毛利率 10%/20%/30% 时，示意毛利分别为 1,000,000/2,000,000/3,000,000，同币种。必须明确这些只是毛利率假设，不能当作实际利润、应税利润或最终税额。税额计算仍需成本、税期、交易结构和法律证据。"})
        request_body = {"model": model, "messages": messages, "stream": True}
        raw_body = json.dumps(request_body, ensure_ascii=False).encode("utf-8")
        request = urllib.request.Request(endpoint, data=raw_body, method="POST", headers={
            "Authorization": "Bearer " + key,
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
            "User-Agent": "CrossTaxLocalGateway/0.2",
        })
        self._headers(200, "application/x-ndjson; charset=utf-8")
        if not self._event({"type":"step", "message":"交易事实校验", "detail": ("缺少："+"、".join(missing)) if missing else "五项基础字段均已提供（尚未做专业核验）", "level":"warning" if missing else "ok"}):
            return
        if scenarios is not None:
            if not self._event({"type":"tool_result", "message":"营业额情景计算", "result":scenarios}):
                return
        if not self._event({"type":"step", "message":"专业法规检索", "detail":"未接入已审定的法规检索服务；本次只进行研究指导，不生成法律引用", "level":"warning"}):
            return
        if not self._event({"type":"step", "message":"模型请求", "detail":PROVIDERS[provider]["name"]+" · "+model+" · 流式 API"}):
            return
        sent_text = False
        finish_reason = None
        usage = None
        try:
            # The URL is drawn strictly from the server-side allowlist: user input cannot perform SSRF.
            with urllib.request.urlopen(request, timeout=100) as rsp:
                if rsp.status != 200:
                    raise RuntimeError("上游模型接口未成功返回")
                for raw in rsp:
                    line = raw.decode("utf-8", errors="replace").strip()
                    if not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    if data == "[DONE]":
                        break
                    try:
                        obj = json.loads(data)
                    except json.JSONDecodeError:
                        continue
                    if obj.get("error"):
                        raise RuntimeError("模型服务在流式返回中报告失败")
                    if obj.get("usage"):
                        usage = obj["usage"].get("total_tokens")
                    choices = obj.get("choices") or []
                    if not choices:
                        continue
                    part = choices[0]
                    if part.get("finish_reason"):
                        finish_reason = part["finish_reason"]
                    delta = part.get("delta") or {}
                    chunk = delta.get("content")
                    if isinstance(chunk, str) and chunk:
                        sent_text = True
                        if not self._event({"type": "delta", "text": chunk}):
                            return
                    # The provider may send reasoning_content. Never treat hidden model deliberation
                    # as an auditable tool trace or expose it as fabricated human-readable 'thought'.
            if not sent_text:
                self._event({"type":"step","message":"模型未返回正文","detail":"可能由模型输出模式或配额限制导致","level":"warning"})
            self._event({"type":"finish","finish_reason":finish_reason or "done", "usage":usage})
        except urllib.error.HTTPError as exc:
            # Do not echo upstream error bodies; they may contain tokens or request details.
            self._event({"type":"error","message":"官方模型接口 HTTP "+str(exc.code)+"；检查模型 ID、密钥权限、余额及对应地域"})
        except urllib.error.URLError:
            self._event({"type":"error","message":"无法访问厂商接口；请检查本机网络/代理和服务商状态"})
        except (TimeoutError, OSError, RuntimeError):
            self._event({"type":"error","message":"流式模型执行中断，请检查网络和服务状态"})


def main() -> None:
    load_local_credential()
    if not (1 <= PORT <= 65535):
        raise SystemExit("Invalid CROSSTAX_WEB_PORT")
    if PUBLIC_ORIGIN:
        parsed = urlparse(PUBLIC_ORIGIN)
        if parsed.scheme != "https" or not parsed.hostname:
            raise SystemExit("CROSSTAX_PUBLIC_ORIGIN must be an HTTPS origin")
    # Initialize the separate conversation store at startup; no tax DB changes.
    with chat_store._connect() as db:
        db.commit()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.daemon_threads = True
    print(f"CrossTax local frontend: http://{HOST}:{PORT}/")
    print("CrossTax: DeepSeek default; API providers can be switched in settings")
    print("API keys are server-side only. A static-only web host cannot call the model securely.")
    try:
        server.serve_forever(poll_interval=0.3)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
