"""Owner-scoped persistence. PostgreSQL in cloud; separate SQLite for local use.

Every write uses a transaction and revision precondition. Application records do
not write the legal schema. File bytes belong in private object storage in cloud.
"""
from __future__ import annotations
import contextlib
import hashlib
import json
import os
from pathlib import Path
import secrets
import sqlite3
import threading
import time
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
LOCAL_DB = ROOT / 'web/state/workbench.sqlite3'
KINDS = {'case','project','file','summary','task','search','evidence','preferences','recommendation','assessment','check'}


class Conflict(ValueError):
    pass


def validate_dsn(dsn: str) -> None:
    p = urlparse(dsn)
    local = p.hostname in {'127.0.0.1','localhost'} and p.port == 55433 and p.path == '/crosstax'
    neon = bool(p.hostname and p.hostname.endswith('.neon.tech'))
    if p.scheme not in {'postgresql','postgres'} or not (local or neon):
        raise RuntimeError('仅允许本项目 55433/crosstax 或专属 Neon 数据库')
    if neon and os.getenv('CROSSTAX_DATABASE_CONFIRM') != 'crosstax':
        raise RuntimeError('请确认专属云库：CROSSTAX_DATABASE_CONFIRM=crosstax')


class Store:
    def __init__(self, path: Path | None = None, dsn: str | None = None):
        self.dsn = dsn if dsn is not None else os.getenv('CROSSTAX_APP_DATABASE_URL','')
        self.path = path or LOCAL_DB
        self.lock = threading.RLock()
        if self.dsn:
            validate_dsn(self.dsn)
        self.table = 'crosstax_app.records' if self.dsn else 'records'
        self.initialize()

    @contextlib.contextmanager
    def connection(self):
        if self.dsn:
            import psycopg
            from psycopg.rows import dict_row
            db = psycopg.connect(self.dsn, row_factory=dict_row, connect_timeout=12)
            db.execute('SET statement_timeout = 15000')
        else:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            db = sqlite3.connect(self.path, timeout=15)
            db.row_factory = sqlite3.Row
            db.execute('PRAGMA busy_timeout=15000')
            db.execute('PRAGMA journal_mode=WAL')
        try:
            yield db
            db.commit()
        except BaseException:
            db.rollback()
            raise
        finally:
            db.close()

    def sql(self, query):
        return query.replace('?', '%s') if self.dsn else query

    def initialize(self):
        with self.connection() as db:
            if self.dsn:
                db.execute((ROOT/'database/migrations/033_app_workbench.sql').read_text('utf-8'))
            else:
                db.execute('''CREATE TABLE IF NOT EXISTS records (
                  owner_id TEXT NOT NULL, kind TEXT NOT NULL, record_id TEXT NOT NULL,
                  payload TEXT NOT NULL, revision INTEGER NOT NULL,
                  created_at REAL NOT NULL, updated_at REAL NOT NULL,
                  PRIMARY KEY(owner_id,kind,record_id))''')
                db.execute('CREATE INDEX IF NOT EXISTS records_owner ON records(owner_id,kind,updated_at DESC)')

    def unpack(self, row):
        if not row:
            return None
        obj = row['payload'] if isinstance(row['payload'],dict) else json.loads(row['payload'])
        return {**obj, 'revision':row['revision'], 'created_at':row['created_at'], 'updated_at':row['updated_at']}

    def get(self, owner, kind, id):
        with self.connection() as db:
            return self.unpack(db.execute(self.sql(f'SELECT * FROM {self.table} WHERE owner_id=? AND kind=? AND record_id=?'),(owner,kind,str(id))).fetchone())

    def list(self, owner, kind, limit=1000):
        with self.connection() as db:
            rows=db.execute(self.sql(f'SELECT * FROM {self.table} WHERE owner_id=? AND kind=? ORDER BY updated_at DESC LIMIT ?'),(owner,kind,min(limit,2000))).fetchall()
            return [self.unpack(r) for r in rows]

    def put(self, owner, kind, id, obj, expected=None):
        if kind not in KINDS:
            raise ValueError('未知记录类型')
        data={k:v for k,v in obj.items() if k not in {'revision','created_at','updated_at'}}
        body=json.dumps(data,ensure_ascii=False,allow_nan=False)
        if len(body.encode()) > 8*1024*1024:
            raise ValueError('记录容量超过上限，请拆分资料')
        now=time.time()
        with self.lock, self.connection() as db:
            q=self.sql(f'SELECT * FROM {self.table} WHERE owner_id=? AND kind=? AND record_id=?')
            row=db.execute(q+(' FOR UPDATE' if self.dsn else ''),(owner,kind,str(id))).fetchone()
            old=row['revision'] if row else 0
            if expected is not None and expected != old:
                raise Conflict('内容已在其他窗口更新，请刷新后重试')
            if row:
                count=db.execute(self.sql(f'UPDATE {self.table} SET payload=?,revision=?,updated_at=? WHERE owner_id=? AND kind=? AND record_id=? AND revision=?'),(body,old+1,now,owner,kind,str(id),old)).rowcount
                if count!=1:
                    raise Conflict('记录更新冲突')
            else:
                # A unique key also guards concurrent insertion from another process.
                try:
                    db.execute(self.sql(f'INSERT INTO {self.table} VALUES (?,?,?,?,?,?,?)'),(owner,kind,str(id),body,1,now,now))
                except (sqlite3.IntegrityError,) as exc:
                    raise Conflict('记录已经存在') from exc
        return {**data,'revision':old+1,'created_at':row['created_at'] if row else now,'updated_at':now}

    def delete(self, owner, kind, id):
        with self.lock, self.connection() as db:
            return bool(db.execute(self.sql(f'DELETE FROM {self.table} WHERE owner_id=? AND kind=? AND record_id=?'),(owner,kind,str(id))).rowcount)

    def move_cases(self, owner, ids, project_id):
        with self.lock, self.connection() as db:
            if project_id:
                project=db.execute(self.sql(f'SELECT payload FROM {self.table} WHERE owner_id=? AND kind=? AND record_id=?'),(owner,'project',project_id)).fetchone()
                if not project:
                    raise ValueError('项目不存在')
            rows=[]
            for id in ids:
                r=db.execute(self.sql(f'SELECT * FROM {self.table} WHERE owner_id=? AND kind=? AND record_id=?')+(' FOR UPDATE' if self.dsn else ''),(owner,'case',str(id))).fetchone()
                if not r:
                    raise ValueError('对话不存在')
                rows.append(r)
            for r in rows:
                v=self.unpack(r);v['project_id']=project_id
                body=json.dumps({k:x for k,x in v.items() if k not in {'revision','created_at','updated_at'}},ensure_ascii=False)
                db.execute(self.sql(f'UPDATE {self.table} SET payload=?,revision=revision+1,updated_at=? WHERE owner_id=? AND kind=? AND record_id=?'),(body,time.time(),owner,'case',r['record_id']))

    def migrate_guest(self, guest, account):
        if not guest.startswith('guest:') or not account.startswith('user:'):
            raise ValueError('无效迁移身份')
        with self.lock,self.connection() as db:
            rows=db.execute(self.sql(f'SELECT * FROM {self.table} WHERE owner_id=?')+(' FOR UPDATE' if self.dsn else ''),(guest,)).fetchall()
            mapping={}
            for r in rows:
                if r['kind']=='case':
                    exists=db.execute(self.sql(f'SELECT 1 FROM {self.table} WHERE owner_id=? AND kind=? AND record_id=?'),(account,'case',r['record_id'])).fetchone()
                    if exists:
                        mapping[int(r['record_id'])]=int(secrets.randbelow(900000000)+100000000)
            for r in rows:
                obj=self.unpack(r)
                id=r['record_id']
                if r['kind']=='case' and int(id) in mapping:
                    obj['id']=mapping[int(id)];id=str(obj['id'])
                if 'case_id' in obj:
                    obj['case_id']=mapping.get(obj['case_id'],obj['case_id'])
                if 'case_ids' in obj:
                    obj['case_ids']=[mapping.get(x,x) for x in obj['case_ids']]
                body=json.dumps({k:v for k,v in obj.items() if k not in {'revision','created_at','updated_at'}},ensure_ascii=False)
                # Preferences are preserved in an existing account. UUID records cannot clobber it.
                db.execute(self.sql(f'INSERT INTO {self.table} VALUES (?,?,?,?,?,?,?) ON CONFLICT(owner_id,kind,record_id) DO NOTHING'),(account,r['kind'],id,body,r['revision'],r['created_at'],time.time()))
            db.execute(self.sql(f'DELETE FROM {self.table} WHERE owner_id=?'),(guest,))
            return {'migrated':len(rows),'case_id_mapping':mapping}


class Blobs:
    def __init__(self):
        self.bucket=os.getenv('CROSSTAX_FILE_BUCKET','')
        self.local=ROOT/'web/state/files'
        self.client=None
        if self.bucket:
            import boto3
            from botocore.config import Config
            endpoint=os.environ['AWS_ENDPOINT_URL_S3']
            if urlparse(endpoint).scheme!='https':
                raise RuntimeError('对象存储必须使用 HTTPS')
            self.client=boto3.client('s3',endpoint_url=endpoint,region_name=os.getenv('AWS_DEFAULT_REGION','us-east-2'),config=Config(signature_version='s3v4',s3={'addressing_style':'path'}))

    def key(self, owner, id):
        return 'uploads/'+hashlib.sha256(owner.encode()).hexdigest()+'/'+id

    def put(self, key, body):
        if self.client:
            self.client.put_object(Bucket=self.bucket,Key=key,Body=body,ContentType='application/octet-stream')
        else:
            path=self.local/key;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(body)

    def get(self, key):
        if self.client:
            return self.client.get_object(Bucket=self.bucket,Key=key)['Body'].read()
        return (self.local/key).read_bytes()

    def delete(self,key):
        if self.client:
            self.client.delete_object(Bucket=self.bucket,Key=key)
        else:
            (self.local/key).unlink(missing_ok=True)
