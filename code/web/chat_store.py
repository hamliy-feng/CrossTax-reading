#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CrossTax persistent per-browser conversation storage (stdlib SQLite).
Never stores API keys. Kept separate from the regulated legal/tax database.
"""
from __future__ import annotations

import json
import sqlite3
import threading
import time
import uuid
from pathlib import Path
from typing import Any

BASE = Path(__file__).resolve().parent
DATABASE = BASE / "state" / "conversations.sqlite3"
LEGACY = BASE / "state" / "cases.json"
LOCK = threading.RLock()
ALLOWED_FACTS = {"payer", "payee", "income", "date", "place"}
ALLOWED_EXTRA = {"parent_jurisdiction", "subsidiary_jurisdiction", "destination", "goods", "turnover", "turnover_currency", "turnover_period", "contracting_seller", "importer_of_record", "gross_profit"}
MAX_CASES_PER_SESSION = 150
MAX_MESSAGES_PER_CASE = 2000


class ClosingConnection(sqlite3.Connection):
    def __exit__(self, *args):
        try:
            return super().__exit__(*args)
        finally:
            self.close()


def _connect() -> sqlite3.Connection:
    DATABASE.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(str(DATABASE), timeout=10, factory=ClosingConnection)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA busy_timeout = 10000")
    db.execute("""
        CREATE TABLE IF NOT EXISTS conversations (
          session_id TEXT NOT NULL,
          case_id INTEGER NOT NULL,
          title TEXT NOT NULL,
          facts_json TEXT NOT NULL DEFAULT '{}',
          extra_json TEXT NOT NULL DEFAULT '{}',
          messages_json TEXT NOT NULL DEFAULT '[]',
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL,
          PRIMARY KEY (session_id, case_id)
        )
    """)
    db.execute("CREATE INDEX IF NOT EXISTS ix_conversations_updated ON conversations(session_id, updated_at DESC)")
    db.execute("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    return db


def _validate(payload: dict[str, Any]) -> dict[str, Any]:
    case_id = payload.get("id")
    title = payload.get("title")
    if type(case_id) is not int or not 1 <= case_id <= 10**9:
        raise ValueError("无效会话编号")
    if not isinstance(title, str) or not 1 <= len(title.strip()) <= 140:
        raise ValueError("会话标题不能为空或超过 140 字")
    f = payload.get("facts") or {}
    if not isinstance(f, dict):
        raise ValueError("facts 必须是对象")
    extras = payload.get("extra") or {}
    if not isinstance(extras, dict):
        raise ValueError("extra 必须是对象")
    messages = payload.get("messages") or []
    if not isinstance(messages, list):
        raise ValueError("messages 必须是列表")
    if len(messages) > MAX_MESSAGES_PER_CASE:
        raise ValueError("会话达到容量限制，请新建对话；旧消息仍保留")
    clean = []
    for m in messages:
        if not isinstance(m, dict) or m.get("role") not in ("user", "assistant", "notice"):
            continue
        body = m.get("text", "")
        if not isinstance(body, str):
            continue
        clean.append({
            "role": m["role"], "text": body[:30000],
            "events": m.get("events", [])[:100] if isinstance(m.get("events"), list) else [],
            "tools": m.get("tools", [])[:10] if isinstance(m.get("tools"), list) else [],
        })
    return {
        "id": case_id, "title": title.strip(),
        "facts": {k: str(v)[:400] for k, v in f.items() if k in ALLOWED_FACTS and v is not None},
        "extra": {k: v for k, v in extras.items() if k in ALLOWED_EXTRA and isinstance(v, (str, int, float, bool, type(None)))},
        "messages": clean,
    }


def _inflate(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["case_id"],
        "title": row["title"],
        "facts": json.loads(row["facts_json"]),
        "extra": json.loads(row["extra_json"]),
        "messages": json.loads(row["messages_json"]),
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }


def list_cases(session_id: str) -> list[dict[str, Any]]:
    with LOCK, _connect() as db:
        rows = db.execute(
            "SELECT * FROM conversations WHERE session_id=? ORDER BY updated_at DESC LIMIT ?",
            (session_id, MAX_CASES_PER_SESSION),
        ).fetchall()
        return [_inflate(row) for row in rows]


def get_case(session_id: str, case_id: int) -> dict[str, Any] | None:
    with LOCK, _connect() as db:
        row = db.execute("SELECT * FROM conversations WHERE session_id=? AND case_id=?", (session_id, case_id)).fetchone()
        return _inflate(row) if row else None


def save_case(session_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    record = _validate(payload)
    now = time.time()
    with LOCK, _connect() as db:
        existing = db.execute(
            "SELECT created_at FROM conversations WHERE session_id=? AND case_id=?",
            (session_id, record["id"]),
        ).fetchone()
        if existing is None:
            count = db.execute("SELECT COUNT(*) FROM conversations WHERE session_id=?", (session_id,)).fetchone()[0]
            if count >= MAX_CASES_PER_SESSION:
                raise ValueError("会话数量已达上限，请先删除旧会话")
        db.execute(
            """INSERT INTO conversations
                 (session_id,case_id,title,facts_json,extra_json,messages_json,created_at,updated_at)
               VALUES (?,?,?,?,?,?,?,?)
               ON CONFLICT(session_id,case_id) DO UPDATE SET
                   title=excluded.title,
                   facts_json=excluded.facts_json,
                   extra_json=excluded.extra_json,
                   messages_json=excluded.messages_json,
                   updated_at=excluded.updated_at""",
            (
                session_id, record["id"], record["title"],
                json.dumps(record["facts"], ensure_ascii=False),
                json.dumps(record["extra"], ensure_ascii=False),
                json.dumps(record["messages"], ensure_ascii=False),
                existing["created_at"] if existing else now, now,
            ),
        )
        db.commit()
    return {"saved": True, "id": record["id"], "updated_at": now}


def delete_case(session_id: str, case_id: int) -> dict[str, Any]:
    if type(case_id) is not int or not 1 <= case_id <= 10**9:
        raise ValueError("无效会话编号")
    with LOCK, _connect() as db:
        cur = db.execute("DELETE FROM conversations WHERE session_id=? AND case_id=?", (session_id, case_id))
        db.commit()
        return {"deleted": bool(cur.rowcount), "id": case_id}


def import_legacy_first_local_session(session_id: str) -> int:
    """One-time local migration. Never expose legacy data to remote visitors."""
    if not LEGACY.is_file():
        return 0
    with LOCK, _connect() as db:
        already = db.execute("SELECT value FROM metadata WHERE key='legacy_imported'").fetchone()
        if already:
            return 0
        try:
            rows = json.loads(LEGACY.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return 0
        if not isinstance(rows, list):
            return 0
        imported = 0
        now = time.time()
        for raw in rows[:MAX_CASES_PER_SESSION]:
            try:
                item = _validate(raw)
            except ValueError:
                continue
            db.execute(
                "INSERT OR IGNORE INTO conversations VALUES (?,?,?,?,?,?,?,?)",
                (
                    session_id, item["id"], item["title"],
                    json.dumps(item["facts"], ensure_ascii=False),
                    json.dumps(item["extra"], ensure_ascii=False),
                    json.dumps(item["messages"], ensure_ascii=False),
                    now - imported, now - imported,
                ),
            )
            imported += 1
        db.execute("INSERT INTO metadata(key,value) VALUES('legacy_imported',?)", (session_id,))
        db.commit()
        return imported
