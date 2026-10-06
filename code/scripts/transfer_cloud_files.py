"""Upload verified legal originals to a configured private Neon bucket.

Uses environment-only S3 credentials. Revalidates each byte SHA before upload.
No SQL writes, no visibility/ACL changes, and no deletion of existing objects.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
from urllib.parse import urlparse

ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT/'web'))
from workspace_store import Blobs


def main():
    p=argparse.ArgumentParser();p.add_argument('--verify-only',action='store_true');args=p.parse_args()
    manifest=json.loads((ROOT/'.agent_tools/cloud_bundle/manifest.json').read_text('utf-8'))
    blobs=Blobs()
    if not blobs.client or os.getenv('CROSSTAX_DATABASE_CONFIRM')!='crosstax':
        raise RuntimeError('需要专属 CrossTax 私有存储配置与确认')
    endpoint=urlparse(os.getenv('AWS_ENDPOINT_URL_S3',''))
    if endpoint.scheme!='https' or not (endpoint.hostname or '').endswith('.neon.tech'):
        raise RuntimeError('本脚本只迁移到官方 Neon HTTPS 端点')
    results=[]
    for item in manifest['files']:
        path=(ROOT/item['relative_path']).resolve()
        if ROOT not in path.parents:raise ValueError('原件路径越界')
        body=path.read_bytes()
        if hashlib.sha256(body).hexdigest()!=item['sha256']:raise ValueError('本地原件 SHA 变化，停止迁移')
        try:
            stored=blobs.get(item['object_key'])
            exists=hashlib.sha256(stored).hexdigest()==item['sha256']
        except blobs.client.exceptions.NoSuchKey:
            exists=False
        except Exception as exc:
            if getattr(exc,'response',{}).get('Error',{}).get('Code') in {'NoSuchKey','404'}:exists=False
            else:raise
        if not exists and not args.verify_only:
            blobs.put(item['object_key'],body)
            exists=hashlib.sha256(blobs.get(item['object_key'])).hexdigest()==item['sha256']
        results.append({'sha256':item['sha256'],'verified':exists,'bytes':item['bytes']})
    out=ROOT/'research/acceptance/cloud_files_transfer.json'
    out.write_text(json.dumps({'verify_only':args.verify_only,'count':len(results),'verified':sum(x['verified'] for x in results),'files':results},indent=2)+'\n','utf-8')
    print('verified',sum(x['verified'] for x in results),'/',len(results))


if __name__=='__main__':main()
