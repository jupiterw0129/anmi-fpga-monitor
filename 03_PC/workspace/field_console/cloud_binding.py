"""Dedicated FPGA binding maintenance; never transfers an owned device."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parent


def binding_status(regenerate=False):
    config=json.loads((ROOT/'cloud1694.local.json').read_text(encoding='utf-8'))
    if config['device_id']!=903 or config['server_url']!='https://fallmonitor.cn':
        raise ValueError('此维护入口仅适用于本机专用设备903')
    token=ROOT/config['device_token_file']
    digest=hashlib.sha256(token.read_text(encoding='utf-8').strip().encode()).hexdigest()
    code=f'''
import hashlib,json,os,secrets,sqlite3,time
from pathlib import Path
root=Path('/opt/dachuang/software/skeleton_monitor/.runtime')
database=root/'skeleton_monitor.sqlite3'
secret=root/'fpga-903.json'
mode={bool(regenerate)!r}
db=sqlite3.connect(database if mode else 'file:'+str(database)+'?mode=ro',uri=not mode)
def hashed(value):return hashlib.sha256(value.encode()).hexdigest()
if mode:
    backup_path=root/('fpga-before-bind-'+str(time.time_ns())+'.sqlite3')
    fd=os.open(backup_path,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600);os.close(fd)
    backup=sqlite3.connect(backup_path)
    try:db.backup(backup)
    finally:backup.close()
    db.execute('BEGIN IMMEDIATE')
try:
    row=db.execute('SELECT token_hash,user_id,bind_code_hash FROM device_credentials WHERE device_id=903').fetchone()
    if not row or row[0]!={digest!r}:raise ValueError('Dedicated device authentication mismatch')
    saved=json.loads(secret.read_text())
    bound=row[1] is not None
    if mode:
        if bound:raise ValueError('Device is bound; unbind from the owner APP first')
        saved['bind_code']=secrets.token_urlsafe(16)[:10]
        db.execute('UPDATE device_credentials SET bind_code_hash=? WHERE device_id=903 AND user_id IS NULL',
            (hashed(saved['bind_code']),))
        temporary=secret.with_suffix('.tmp')
        fd=os.open(temporary,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
        with os.fdopen(fd,'w') as stream:json.dump(saved,stream)
        os.replace(temporary,secret)
        db.commit()
        row=(row[0],None,hashed(saved['bind_code']))
    current=saved.get('bind_code','')
    usable=not bound and current and hashed(current)==row[2]
    print(json.dumps(dict(device_id=903,bound=bound,bind_code=current if usable else None)))
finally:db.close()
'''
    result=subprocess.run(['ssh.exe','-T','-o','BatchMode=yes','-o','ConnectTimeout=5',
        'monitor','python3','-'],input=code,capture_output=True,text=True,timeout=15,
        **(dict(creationflags=subprocess.CREATE_NO_WINDOW) if hasattr(subprocess,'CREATE_NO_WINDOW') else {}))
    if result.returncode:raise RuntimeError('无法读取云端绑定状态，请检查网络及本机维护权限；已绑定设备需先由原账号解绑')
    value=json.loads(result.stdout)
    value['server_url']=config['server_url']
    # Remove stale cached codes after owner binding or APP-side unbinding.
    (ROOT/'.private/fpga903_binding.json').write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8')
    return value
