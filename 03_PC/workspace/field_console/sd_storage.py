"""Scoped SD recording management. Never format or follow arbitrary paths."""
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import time

DEVICE='/dev/mmcblk1p1'
CARD_UUID='0403-0201'
MOUNT=Path('/userdata/board_cloud/sd_manage')
REPORTS=Path('/userdata/native_required1138_20261028/field1382')
SESSION=re.compile(r'field_[0-9_]+\Z')


def identity():
    value=subprocess.check_output(['blkid','-s','UUID','-o','value',DEVICE],text=True).strip()
    if value!=CARD_UUID:raise ValueError('SD卡标识不匹配，未执行操作')


def mounts():
    result=subprocess.run(['findmnt','-J','-S',DEVICE,'-o','SOURCE,TARGET,FSTYPE,OPTIONS'],capture_output=True,text=True)
    if result.returncode==1:return []
    if result.returncode:raise ValueError('无法读取SD挂载状态')
    return json.loads(result.stdout)['filesystems']


@contextmanager
def card(writable=False):
    import fcntl
    # Same lock as camera capture; APP preview and a second manager cannot race.
    with open('/run/fpga_capture.lock','a') as lock:
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:raise ValueError('相机正在预览或测试，请停止后操作SD卡') from None
        identity()
        if mounts():raise ValueError('SD卡正在使用，请等待本次会话保存结束')
        MOUNT.mkdir(exist_ok=True)
        if MOUNT.is_symlink() or MOUNT.resolve()!=MOUNT or any(MOUNT.iterdir()):
            raise ValueError('SD管理挂载点异常')
        subprocess.run(['mount','-t','vfat','-o',('rw' if writable else 'ro')+',nosuid,nodev,noexec',DEVICE,str(MOUNT)],check=True,timeout=20)
        try:
            rows=mounts()
            if len(rows)!=1 or rows[0]['source']!=DEVICE or rows[0]['target']!=str(MOUNT) or rows[0]['fstype']!='vfat':
                raise ValueError('SD挂载身份校验失败')
            yield MOUNT
        finally:
            subprocess.run(['umount',str(MOUNT)],check=True,timeout=30)


def usage(path):
    row=shutil.disk_usage(path)
    return dict(total_bytes=row.total,free_bytes=row.free,used_bytes=row.used,card_uuid=CARD_UUID)


def completed(name, reports=REPORTS):
    try:
        row=json.loads((reports/name/'report.json').read_text())
        if row.get('name')!=name or row.get('driver_restored') is not True or row.get('sd_unmounted') is not True:
            return False
        if row.get('cleanup_verified') is True:return True
        # FPGA drain failure does not keep an unmounted recording in use.
        # The final wrapper report must confirm controller exit and no pending
        # restoration/unmount error. card() still holds the capture lock and
        # refuses any existing SD mount before listing or deleting files.
        code=row.get('controller_returncode')
        return (row.get('state')=='FAILED' and type(code) is int and code!=0
                and row.get('canonical_unchanged') is True
                and not row.get('cleanup_error') and not row.get('unmount_error'))
    except (OSError,ValueError):return False


def inventory(root, name):
    if not isinstance(name,str) or not SESSION.fullmatch(name):raise ValueError('无效会话名称')
    root=root.resolve();top=root/name
    if top.is_symlink() or not top.is_dir() or top.resolve().parent!=root:
        raise ValueError('会话目录不安全')
    files=[];directories=[]
    for directory,subdirs,names in os.walk(top,followlinks=False):
        current=Path(directory)
        for child in [current,*[current/item for item in subdirs],*[current/item for item in names]]:
            info=child.lstat()
            if stat.S_ISLNK(info.st_mode) or (not stat.S_ISDIR(info.st_mode) and not stat.S_ISREG(info.st_mode)) or root not in child.resolve().parents:
                raise ValueError('会话包含异常文件，禁止清理')
        directories.append(current.relative_to(root).as_posix())
        for item in names:
            path=current/item;info=path.stat()
            files.append(dict(path=path.relative_to(root).as_posix(),bytes=info.st_size,mtime_ns=info.st_mtime_ns))
    files.sort(key=lambda item:item['path']);directories.sort()
    data=dict(name=name,files=files,directories=directories)
    fingerprint=hashlib.sha256(json.dumps(data,sort_keys=True).encode()).hexdigest()
    return dict(name=name,bytes=sum(item['bytes'] for item in files),file_count=len(files),
                fingerprint=fingerprint,files=files,directories=directories)


def scan(root, reports=REPORTS):
    result=usage(root);sessions=[];excluded=0
    for path in sorted(root.iterdir(),reverse=True):
        if not SESSION.fullmatch(path.name):
            excluded+=1;continue
        try:
            row=inventory(root,path.name)
            row['eligible']=completed(path.name,reports)
            row['reason']='' if row['eligible'] else '尚未确认会话已保存并恢复设备'
            row.pop('files');row.pop('directories');sessions.append(row)
        except ValueError:excluded+=1
    result.update(sessions=sessions,excluded_entries=excluded,checked_at_ns=time.time_ns(),in_use=False)
    return result


def delete(root, selected, reports=REPORTS):
    if not isinstance(selected,list) or not selected:raise ValueError('请先选择录像')
    names=[item.get('name') for item in selected]
    if len(set(names))!=len(names):raise ValueError('会话重复')
    verified=[]
    # Check every selection before deleting the first file.
    for item in selected:
        row=inventory(root,item['name'])
        if not completed(row['name'],reports):raise ValueError('会话仍在使用或未完成恢复')
        if row['fingerprint']!=item.get('fingerprint'):raise ValueError('SD录像已变化，请刷新后重新选择')
        verified.append(row)
    before=usage(root)
    for row in verified:
        for item in row['files']:(root/item['path']).unlink()
        for relative in sorted(row['directories'],key=lambda item:len(Path(item).parts),reverse=True):
            (root/relative).rmdir()
    if hasattr(os,'sync'):os.sync()
    result=scan(root,reports)
    result.update(deleted_sessions=names,deleted_bytes=sum(row['bytes'] for row in verified),free_before=before['free_bytes'])
    return result


def execute(request):
    action=request.get('action')
    if action not in ('status','scan','delete'):raise ValueError('不支持的SD操作')
    identity()
    mounted=mounts()
    if action=='status' and mounted:
        if len(mounted)!=1 or mounted[0]['source']!=DEVICE or mounted[0]['fstype']!='vfat':raise ValueError('SD挂载状态异常')
        return dict(usage(Path(mounted[0]['target'])),in_use=True,checked_at_ns=time.time_ns())
    with card(writable=action=='delete') as root:
        result=delete(root,request.get('selected')) if action=='delete' else scan(root) if action=='scan' else dict(usage(root),in_use=False,checked_at_ns=time.time_ns())
    result['unmounted']=True
    if action=='delete':
        receipt=MOUNT.parent/('sd_cleanup_'+str(time.time_ns())+'.json')
        receipt.write_text(json.dumps(result,ensure_ascii=False),encoding='utf-8')
    return result


if __name__=='__main__':
    try:print(json.dumps(dict(ok=True,**execute(json.load(sys.stdin))),ensure_ascii=False))
    except Exception as error:print(json.dumps(dict(ok=False,error=str(error)),ensure_ascii=False))
