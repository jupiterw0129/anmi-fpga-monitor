"""Manage only inactive session directories in the fixed board evidence root."""
from contextlib import ExitStack
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import time

ROOT=Path('/userdata/native_required1138_20261028/evidence')
NAME=re.compile(r'[A-Za-z0-9][A-Za-z0-9_-]*\Z')


def inventory(root,name):
    if not isinstance(name,str) or not NAME.fullmatch(name):raise ValueError('无效日志会话名称')
    if root.is_symlink() or root.resolve()!=root:raise ValueError('日志根目录异常')
    top=root/name
    if top.is_symlink() or not top.is_dir():raise ValueError('日志会话目录异常')
    files=[];directories=[]
    for directory,subdirs,names in os.walk(top,followlinks=False):
        current=Path(directory);directories.append(current.relative_to(root).as_posix())
        for path in [current,*[current/item for item in subdirs+names]]:
            info=path.lstat()
            if stat.S_ISLNK(info.st_mode) or root not in path.resolve().parents or not (stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode) or stat.S_ISFIFO(info.st_mode)):
                raise ValueError('日志包含异常文件，禁止清理')
        for name in names:
            path=current/name;info=path.lstat()
            files.append(dict(path=path.relative_to(root).as_posix(),bytes=info.st_size,mtime_ns=info.st_mtime_ns,fifo=stat.S_ISFIFO(info.st_mode)))
    files.sort(key=lambda item:item['path']);directories.sort()
    fingerprint=hashlib.sha256(json.dumps(dict(files=files,directories=directories),sort_keys=True).encode()).hexdigest()
    return dict(name=top.name,bytes=sum(item['bytes'] for item in files),file_count=len(files),fingerprint=fingerprint,files=files,directories=directories,modified_ns=top.stat().st_mtime_ns)


def ensure_idle(root):
    # Capture locks cover starts; open descriptors/arguments cover older tools.
    prefix=str(root)+'/'
    for process in Path('/proc').iterdir():
        if not process.name.isdigit() or int(process.name)==os.getpid():continue
        try:
            args=(process/'cmdline').read_bytes().replace(b'\0',b' ').decode(errors='replace')
            if prefix in args:raise ValueError('板端仍有进程使用日志，请先停止测试或预览')
            for descriptor in [process/'cwd',*list((process/'fd').iterdir())]:
                try:target=os.readlink(descriptor)
                except FileNotFoundError:continue
                if target.startswith(prefix):raise ValueError('板端仍有进程使用日志，请先停止测试或预览')
        except (FileNotFoundError,ProcessLookupError):continue


def scan(root):
    usage=shutil.disk_usage(root);sessions=[];excluded=0
    for path in sorted(root.iterdir(),reverse=True):
        try:row=inventory(root,path.name)
        except ValueError:excluded+=1;continue
        row.pop('files');row.pop('directories');row.update(eligible=True,reason='')
        sessions.append(row)
    sessions.sort(key=lambda item:item['modified_ns'],reverse=True)
    return dict(total_bytes=usage.total,free_bytes=usage.free,used_bytes=usage.used,sessions=sessions,excluded_entries=excluded,checked_at_ns=time.time_ns())


def view(root,name):
    row=inventory(root,name);sections=[]
    candidates=[item for item in row['files'] if not item['fifo'] and (Path(item['path']).suffix in ('.log','.json','.jsonl','.txt') or Path(item['path']).name in ('stdout','stderr'))]
    candidates.sort(key=lambda item:(not item['path'].endswith(('report.json','session.json')),item['path']))
    for item in candidates[:12]:
        with (root/item['path']).open('rb') as stream:
            stream.seek(max(0,item['bytes']-8192));content=stream.read(8192).decode('utf-8',errors='replace')
        sections.append('【'+item['path']+'】\n'+content)
    return dict(name=name,text='\n\n'.join(sections) or '此会话没有可显示的文本日志。',file_count=row['file_count'],shown_files=min(12,len(candidates)))


def delete(root,selected):
    if not isinstance(selected,list) or not selected:raise ValueError('请先选择日志会话')
    names=[item.get('name') for item in selected]
    if len(set(names))!=len(names):raise ValueError('会话重复')
    verified=[]
    for item in selected:
        row=inventory(root,item['name'])
        if row['fingerprint']!=item.get('fingerprint'):raise ValueError('日志已变化，请刷新后重新选择')
        verified.append(row)
    before=shutil.disk_usage(root).free
    for row in verified:
        for item in row['files']:(root/item['path']).unlink()
        for relative in sorted(row['directories'],key=lambda item:len(Path(item).parts),reverse=True):(root/relative).rmdir()
    result=scan(root);result.update(deleted_sessions=names,deleted_bytes=sum(row['bytes'] for row in verified),free_before=before)
    return result


def execute(request):
    import fcntl
    if ROOT.is_symlink() or ROOT.resolve()!=ROOT:raise ValueError('日志根目录异常')
    action=request.get('action')
    if action not in ('scan','view','delete'):raise ValueError('不支持的日志操作')
    with ExitStack() as stack:
        for path in ('/run/fpga_capture.lock','/run/lock/rxdiag712.lock'):
            lock=stack.enter_context(open(path,'a'))
            try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError:raise ValueError('设备正在使用，请停止测试或预览后管理日志') from None
        ensure_idle(ROOT)
        if action=='view':return view(ROOT,request.get('name'))
        return delete(ROOT,request.get('selected')) if action=='delete' else scan(ROOT)
