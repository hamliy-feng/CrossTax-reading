"""Read-only legal export and SHA-indexed file manifest for a dedicated cloud DB."""
from datetime import datetime,timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT/'web'))
import legal_service


def main():
    info=json.loads(subprocess.check_output(['docker','inspect','crosstax-postgres'],text=True))[0]
    if not any(x['Source'].replace('\\','/').lower()=='d:/app/crosstax/data/postgres' for x in info['Mounts']):
        raise RuntimeError('CrossTax 容器挂载不匹配')
    if not any(x['HostPort']=='55433' and x['HostIp']=='127.0.0.1' for x in info['HostConfig']['PortBindings']['5432/tcp']):
        raise RuntimeError('CrossTax 端口不匹配')
    out=ROOT/'.agent_tools/cloud_bundle';out.mkdir(parents=True,exist_ok=True)
    body=subprocess.check_output(['docker','exec','crosstax-postgres','pg_dump','-U','crosstax','-d','crosstax','--schema=crosstax','--format=custom','--no-owner','--no-privileges'])
    sha=hashlib.sha256(body).hexdigest();dump=out/(sha+'.dump')
    if not dump.exists():dump.write_bytes(body)
    tables=legal_service.rows("SELECT tablename FROM pg_tables WHERE schemaname='crosstax' ORDER BY tablename")
    counts={}
    for t in tables:
        name=t['tablename']
        if not name.replace('_','').isalnum():raise ValueError('无效表名')
        counts[name]=legal_service.rows('SELECT count(*) AS n FROM crosstax.'+name)[0]['n']
    versions=legal_service.rows('SELECT version_id,source_sha256,content_locator FROM crosstax.document_versions WHERE source_sha256 IS NOT NULL')
    files=[];seen=set()
    for directory in [ROOT/'data/raw',ROOT/'research/benchmarks/_sources']:
        for file in sorted(directory.rglob('*')):
            if not file.is_file():continue
            body=file.read_bytes();hash=hashlib.sha256(body).hexdigest()
            if hash in seen:continue
            seen.add(hash)
            files.append({'relative_path':file.relative_to(ROOT).as_posix(),'sha256':hash,'bytes':len(body),'object_key':'legal/'+hash})
    missing=[{'version_id':x['version_id'],'sha256':x['source_sha256'],'content_locator':x['content_locator']} for x in versions if x['source_sha256'] not in seen]
    manifest={'created_at':datetime.now(timezone.utc).isoformat(),'source':'crosstax/127.0.0.1:55433','schema':'crosstax',
      'dump_file':dump.name,'dump_sha256':sha,'dump_bytes':dump.stat().st_size,'table_rows':counts,
      'files':files,'total_file_bytes':sum(f['bytes'] for f in files),'missing_version_originals':missing,
      'cloud_target':'not_configured','restore_performed':False,'application_schema_migration':'033_app_workbench.sql'}
    (out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n','utf-8')
    # Public/committed summary excludes all bytes of the dump and original corpus.
    summary={k:v for k,v in manifest.items() if k not in {'files','table_rows'}}
    summary['tables']=len(counts);summary['rows']=sum(counts.values());summary['unique_files']=len(files)
    (ROOT/'research/acceptance/cloud_bundle_preparation_2026-10-07.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n','utf-8')
    print(json.dumps({'tables':len(counts),'rows':sum(counts.values()),'unique_files':len(files),'total_mib':round(manifest['total_file_bytes']/1048576,2),'missing_version_originals':len(missing),'restored':False}))


if __name__=='__main__':main()
