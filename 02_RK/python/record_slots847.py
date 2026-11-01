"""Independent JPGS755 slot -> SD event recorder, with read-only alarm SQLite.

This process never opens DMA/BAR or waits in the display/NPU process. It copies
each slot under a nonblocking shared lock, releases that lock, then writes SD.
Slot overwrite/gaps and lock contention are counted; complete60fps recording
must be measured, not inferred from a nominal slot rate.
"""
from pathlib import Path
import argparse,fcntl,json,math,mmap,os,sqlite3,struct,time
from event_record837 import EventRecorder
CAP=1920*1080*6+65536;STRIDE=CAP+64;SIZE=4*STRIDE
HEADER=struct.Struct('<8sQQdQQIIII')
def snapshot(fd,mm,generation,last):
    frames=[];busy=0
    for slot in range(4):
        try:fcntl.lockf(fd,fcntl.LOCK_SH|fcntl.LOCK_NB,STRIDE,slot*STRIDE)
        except BlockingIOError:busy+=1;continue
        try:
            h=HEADER.unpack_from(mm,slot*STRIDE)
            if h[0]==b'\0'*8:continue
            magic,frame,length,completed,packets,encoded,w,ht,gen,flags=h
            if magic!=b'JPGS755\0' or gen!=generation or flags!=1 or not 0<length<=CAP or length!=encoded:
                raise ValueError('JPEG slot identity/length mismatch')
            if (w,ht)!=(1920,1080) or not math.isfinite(completed) or completed<=0 or packets<=0:
                raise ValueError('JPEG slot geometry/time mismatch')
            if last is not None and frame<=last:continue
            data=bytes(mm[slot*STRIDE+64:slot*STRIDE+64+length])
            if not(data[:2]==b'\xff\xd8' and data[-2:]==b'\xff\xd9'):raise ValueError('JPEG slot boundaries missing')
            frames.append((frame,round(completed*1e9),data))
        finally:fcntl.lockf(fd,fcntl.LOCK_UN,STRIDE,slot*STRIDE)
    frames.sort(key=lambda r:r[0])
    if len({r[0] for r in frames})!=len(frames):raise ValueError('Duplicate slot frame identity')
    return frames,busy
def run(a):
    out=Path(a.output);out.mkdir()
    fd=os.open(a.shared,os.O_RDONLY|os.O_NOFOLLOW);st=os.fstat(fd)
    if st.st_size!=SIZE or st.st_uid!=os.getuid() or st.st_mode&0o777!=0o600:
        os.close(fd);raise ValueError('Shared slot file ownership/size/mode mismatch')
    db=sqlite3.connect(Path(a.alarm_db).resolve().as_uri()+'?mode=ro',uri=True,timeout=.05)
    db.row_factory=sqlite3.Row
    # Fail before readiness if the persistent alarm table is not available.
    db.execute('SELECT id,status,opened_session,opened_s FROM incidents LIMIT 1').fetchall()
    rec=EventRecorder(a.recordings,1920,1080,60,pre_ns=round(a.pre*1e9),post_ns=round(a.post*1e9),
                      alarm_lag_ns=round(a.alarm_lag*1e9),buffer_bytes=a.buffer_bytes,quota_bytes=a.quota_bytes)
    result=dict(state='FAILED',frames_received=0,frame_id_gaps=0,slot_lock_busy=0,alarm_db_busy=0,
                wrong_session_alarms_ignored=0,alarm_errors=[],physical_camera60fps_verified=False)
    last=None;pending=None;seen=set();foreign=set();start=time.monotonic()
    try:
        with mmap.mmap(fd,SIZE,access=mmap.ACCESS_READ) as mm:
            (out/'ready.json').open('x').write(json.dumps(dict(generation=a.generation,session=a.session)))
            while True:
                frames,busy=snapshot(fd,mm,a.generation,last);result['slot_lock_busy']+=busy
                for row in frames:
                    if last is not None:result['frame_id_gaps']+=row[0]-last-1
                    rec.frame(*row);last=row[0];result['frames_received']+=1
                try:active=db.execute("SELECT * FROM incidents WHERE status!='CLOSED'").fetchone()
                except sqlite3.OperationalError as e:
                    if 'locked' not in str(e).lower():raise
                    active=None;result['alarm_db_busy']+=1
                if active:
                    if active['opened_session']!=a.session:
                        if active['id'] not in foreign:foreign.add(active['id']);result['wrong_session_alarms_ignored']+=1
                    elif active['id'] not in seen:
                        pending=(active['id'],round(active['opened_s']*1e9))
                if pending and rec.last and pending[1]<=rec.last[1] and rec.active is None:
                    try:rec.alarm(*pending)
                    except (ValueError,OSError) as e:
                        result['alarm_errors'].append(dict(incident_id=pending[0],error=repr(e)))
                    seen.add(pending[0]);pending=None
                if Path(a.stop).exists():break
                if time.monotonic()-start>a.max_seconds:raise TimeoutError('Recording worker exceeded bounded run')
                time.sleep(.002)
        rec.close()
        result.update(state='SLOTS847_WORKER_STOPPED',last_frame_id=last,events=rec.completed,
                      peak_buffer_bytes=rec.peak_buffer_bytes,evicted_bytes=rec.evicted_bytes,
                      host_elapsed_seconds=time.monotonic()-start)
    except BaseException as e:
        result['error']=repr(e)
        if rec.active:rec.active['clip'].abort()
        raise
    finally:
        db.close();os.close(fd)
        (out/'report.json').open('x').write(json.dumps(result,indent=2))
    return result
def parser():
    p=argparse.ArgumentParser();p.add_argument('--shared',required=True);p.add_argument('--alarm-db',required=True)
    p.add_argument('--session',required=True);p.add_argument('--generation',type=int,required=True)
    p.add_argument('--recordings',required=True);p.add_argument('--output',required=True);p.add_argument('--stop',required=True)
    p.add_argument('--pre',type=float,default=3);p.add_argument('--post',type=float,default=3);p.add_argument('--alarm-lag',type=float,default=2)
    p.add_argument('--buffer-bytes',type=int,default=64*1024**2);p.add_argument('--quota-bytes',type=int,default=24*1024**3)
    p.add_argument('--max-seconds',type=float,default=900);return p
if __name__=='__main__':print(json.dumps(run(parser().parse_args())))
