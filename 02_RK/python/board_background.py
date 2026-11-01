"""APP-requested camera preview, sharing an existing capture or owning a bounded preview."""
import io
import json
import mmap
import os
from pathlib import Path
import re
import struct
import subprocess
import threading
import time
from datetime import datetime

NATIVE=Path('/userdata/native_required1138_20261028')
HOME=Path('/userdata/board_cloud')
CAP=1920*1080*6+65536
STRIDE=CAP+64
HEADER=struct.Struct('<8sQQdQQIIII')


def source_process():
    for path in Path('/proc').glob('[0-9]*/cmdline'):
        try:
            args=path.read_bytes().decode().strip('\0').split('\0')
            if Path(args[0]).name not in ('publish1585','publish1332','publish_preview'):continue
            if args[1] not in ('--stream-dma','--stream-rec-dma','--stream-av-dma'):continue
            shared=Path(args[3]);generation=int(args[4])
            if shared.parent==Path('/dev/shm') and shared.name.startswith('jpg2_841_'):
                return shared,generation
        except (OSError,UnicodeError,IndexError,ValueError):continue
    return None


def jpeg_snapshot(source,now_ns=None):
    import fcntl
    path,generation=source
    now_ns=time.monotonic_ns() if now_ns is None else now_ns
    rows=[]
    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW)
    try:
        st=os.fstat(fd)
        if st.st_size!=4*STRIDE or st.st_uid!=os.getuid() or st.st_mode&0o777!=0o600:
            raise ValueError('Invalid shared frame file')
        with mmap.mmap(fd,0,access=mmap.ACCESS_READ) as mm:
            for slot in range(4):
                offset=slot*STRIDE
                try:fcntl.lockf(fd,fcntl.LOCK_SH|fcntl.LOCK_NB,STRIDE,offset)
                except BlockingIOError:continue
                try:
                    magic,frame,length,completed,packets,encoded,w,h,gen,flags=HEADER.unpack_from(mm,offset)
                    if magic!=b'JPGS755\0' or gen!=generation or flags!=1:continue
                    if (w,h)!=(1920,1080) or not 0<length<=CAP or length!=encoded:continue
                    if not 0<=now_ns-round(completed*1e9)<2_000_000_000:continue
                    data=bytes(mm[offset+64:offset+64+length])
                    if data.startswith(b'\xff\xd8') and data.endswith(b'\xff\xd9'):rows.append((frame,data))
                finally:fcntl.lockf(fd,fcntl.LOCK_UN,STRIDE,offset)
    finally:os.close(fd)
    if not rows:raise ValueError('No fresh camera frame')
    return max(rows,key=lambda row:row[0])[1]


def upright_preview(data):
    import sys
    sys.path.append('/home/anmi/offline_demo/python-packages')
    import cv2
    import numpy as np
    image=cv2.imdecode(np.frombuffer(data,dtype=np.uint8),cv2.IMREAD_REDUCED_COLOR_2)
    if image is None:raise ValueError('Camera JPEG decode failed')
    image=cv2.rotate(image,cv2.ROTATE_180)
    ok,encoded=cv2.imencode('.jpg',image,[cv2.IMWRITE_JPEG_QUALITY,80])
    if not ok:raise ValueError('Preview encode failed')
    return encoded.tobytes()


def stop_owned(timeout=75):
    owner=HOME/'camera_owner.json'
    if not owner.exists():return
    value=json.loads(owner.read_text());name=value['name']
    if not re.fullmatch(r'field_[0-9_]+',name):raise ValueError('Invalid preview owner')
    base=NATIVE/'field1382'/name
    if not (base/'report.json').exists():
        (base/'stop_requested').touch(exist_ok=True)
        deadline=time.monotonic()+timeout
        while not (base/'report.json').exists():
            if time.monotonic()>deadline:raise TimeoutError('APP preview is still restoring the capture driver')
            time.sleep(.1)
    report=json.loads((base/'report.json').read_text())
    if not report.get('driver_restored') or not report.get('cleanup_verified'):
        raise RuntimeError('APP preview did not restore camera driver')
    owner.unlink(missing_ok=True)


class CameraBackground:
    def __init__(self):
        self.session=None
        self.preview=None
        self.reader=None
        self.lock=threading.RLock()

    def start(self,session):
        with self.lock:
            self.session=session
            if source_process():return
            if self.preview and self.preview.poll() is None:return
            # A controller still starting or restoring owns capture; reuse it when ready.
            for path in Path('/proc').glob('[0-9]*/cmdline'):
                try:
                    if str(NATIVE/'control_field1382.py').encode() in path.read_bytes().split(b'\0'):return
                except OSError:pass
            stop_owned()
            name='field_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f')
            (HOME/'camera_owner.json').write_text(json.dumps(dict(name=name)))
            log=(HOME/'camera_preview.log').open('wb')
            self.preview=subprocess.Popen(['python3','-B',str(NATIVE/'field1382/preview_remote.py'),
                '--name',name,'--seconds','120','--preprocess','0','--compression','quality','--jpeg-quality','50'],
                stdout=log,stderr=log)
            log.close()
            def drain():
                root=NATIVE/'evidence'/name
                deadline=time.monotonic()+30
                while not (root/'wire.fifo').exists():
                    if self.preview.poll() is not None or time.monotonic()>deadline:return
                    time.sleep(.02)
                with (HOME/'camera_reader.log').open('wb') as error:
                    self.reader=subprocess.Popen(['python3','-B',str(NATIVE/'wire_reader1551.py'),'--directory',str(root)],
                                                 stdout=subprocess.DEVNULL,stderr=error)
                    self.reader.wait()
            threading.Thread(target=drain,daemon=True).start()

    def handle(self,command,upload):
        action=command.get('action');session=command.get('session_id')
        if not isinstance(session,str) or not session:raise ValueError('Missing background session')
        if action=='start':self.start(session);return
        if session!=self.session:raise ValueError('Background session mismatch')
        if action=='stop':
            self.session=None
            if self.preview:self.stop()
            return
        if action not in ('preview','capture'):raise ValueError('Unsupported background command')
        deadline=time.monotonic()+4
        while True:
            source=source_process()
            if source:
                try:data=upright_preview(jpeg_snapshot(source));break
                except (ValueError,OSError):pass
            if time.monotonic()>deadline:raise RuntimeError('Camera preview not ready; check camera and capture owner')
            time.sleep(.05)
        upload(session,action,data)

    def stop(self):
        with self.lock:
            stop_owned()
            if self.preview:self.preview.wait(timeout=5)
            if self.reader:self.reader.wait(timeout=5)
            self.preview=None;self.reader=None


if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('--stop-owned',action='store_true',required=True);parser.parse_args()
    stop_owned()
