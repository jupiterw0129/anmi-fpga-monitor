"""PC SD controls share the same resource lease as capture and replay."""
import json
from pathlib import Path


def request(backend, action, selected=None, kind='sd', name=None):
    from resource_gate1695 import acquire
    lease=None
    try:
        if action!='status':lease=acquire()
        payload=dict(action=action)
        if selected is not None:payload['selected']=selected
        if kind not in ('sd','evidence'):raise ValueError('无效存储类型')
        if name is not None:payload['name']=name
        source=Path(__file__).with_name('evidence_storage.py').read_text(encoding='utf-8') if kind=='evidence' else None
        loader=("exec(compile("+ascii(source)+",'evidence_storage.py','exec'))\n") if source else "from sd_storage import execute\n"
        code=("import sys,json\nsys.path.insert(0,'/userdata/board_cloud')\n"+loader+
              "try:r=dict(ok=True,**execute("+repr(payload)+"))\n"
              "except Exception as e:r=dict(ok=False,error=str(e))\nprint(json.dumps(r))")
        result=backend.ssh_json(code,timeout=120 if action=='delete' else 35)
        if not result.get('ok'):raise ValueError(result.get('error','SD操作失败'))
        if action=='delete':
            from datetime import datetime
            directory=backend.DATA/('log_cleanup' if kind=='evidence' else 'sd_cleanup');directory.mkdir(exist_ok=True)
            (directory/(datetime.now().strftime('%Y%m%d_%H%M%S_%f')+'.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
        return result
    finally:
        if lease:lease.close()


def pc_recording_status(data, name):
    """Presence is informational, never a claim of byte-for-byte SD backup."""
    path=Path(data)/name
    try:
        report=json.loads((path/'report.json').read_text(encoding='utf-8'))
        movies=report.get('recordings',[])
        if report.get('state')=='FIELD_PC_SESSION_PASS' and movies and all((path/item['name']).is_file() and (path/item['name']).stat().st_size>0 for item in movies):
            return '有PC录像'
    except (OSError,ValueError,KeyError):pass
    return '未找到PC录像'
