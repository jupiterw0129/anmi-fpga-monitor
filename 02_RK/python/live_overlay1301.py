from long_journal1295 import RowJournal,journal_json
from session_config1301 import runtime_seconds
"""One plane binding, mapped ARGB updates; in-place update may tear optically."""
from pathlib import Path
import argparse,ctypes,hashlib,json,signal,sys,time
sys.path.insert(0,'/home/anmi/offline_demo/python-packages')
import cv2
from alarm_overlay1201 import AlarmReader,render_current

def main():
    p=argparse.ArgumentParser()
    for name in ('shared','output','session','alarm-db'):p.add_argument('--'+name,required=True)
    p.add_argument('--generation',type=int,required=True);p.add_argument('--max-seconds',type=runtime_seconds,required=True);a=p.parse_args()
    out=Path(a.output);out.mkdir();latest=out.parent/'pose/latest1184.json';handle=None;reader=None
    report=dict(state='FAILED',updates=[],physical_overlay_verified=False,tear_free_verified=False,in_place_argb_updates=True)
    report['updates']=RowJournal(out/'updates.jsonl')
    lib=ctypes.CDLL(str(Path(__file__).with_name('overlay1190.so')),use_errno=True)
    lib.overlay1190_open.restype=ctypes.c_void_p
    lib.overlay1190_update.argtypes=(ctypes.c_void_p,ctypes.c_void_p,ctypes.c_uint32);lib.overlay1190_update.restype=ctypes.c_int
    lib.overlay1190_close.argtypes=(ctypes.c_void_p,);lib.overlay1190_close.restype=ctypes.c_int
    lib.overlay1190_fb.argtypes=(ctypes.c_void_p,);lib.overlay1190_fb.restype=ctypes.c_uint32
    def interrupted(sig,frame):raise SystemExit('signal '+str(sig))
    for sig in (signal.SIGTERM,signal.SIGHUP):signal.signal(sig,interrupted)
    try:
        reader=AlarmReader(a.alarm_db)
        initial=reader.read();assert initial['known'],'Alarm DB not readable at startup'
        handle=lib.overlay1190_open()
        if not handle:raise OSError(ctypes.get_errno(),'Cannot bind free overlay plane148')
        report['framebuffer_id']=lib.overlay1190_fb(handle)
        (out/'ready.tmp').open('x').write(json.dumps(dict(generation=a.generation,session=a.session,overlay_plane=148)))
        (out/'ready.tmp').replace(out/'ready.json')
        result=None;last_key=None;deadline=time.monotonic()+a.max_seconds
        while True:
            if latest.exists():result=json.loads(latest.read_text())
            now=time.monotonic_ns();db_status=reader.read();image,meta=render_current(result,a.generation,a.session,now,db_status)
            key=(meta['pose_frame_id'],meta['state'],meta['stale'],json.dumps(meta['alarm'],sort_keys=True),meta['alarm_database_known'],meta['alarm_database_error'])
            if key!=last_key:
                started=time.monotonic_ns();assert lib.overlay1190_update(handle,image.ctypes.data,image.nbytes)==0
                report['updates'].append(dict(**meta,db_status=db_status,host_ns=now,copy_ns=time.monotonic_ns()-started,bgra_sha256=hashlib.sha256(image.tobytes()).hexdigest()))
                if meta['pose_frame_id'] is not None and not meta['stale'] and not (out/'sample1184.png').exists():
                    assert cv2.imwrite(str(out/'sample1184.png'),image)
                    (out/'sample1184.json').open('x').write(json.dumps(result,indent=2))
                    (out/'sample_db1201.json').open('x').write(json.dumps(db_status,indent=2))
                last_key=key
            if (out/'stop').exists():break
            if time.monotonic()>deadline:raise TimeoutError('Overlay worker exceeded bound')
            time.sleep(.05)
        atomic=Path('/sys/kernel/debug/dri/0/state').read_text();(out/'atomic_during.txt').write_text(atomic)
        part=atomic.split('plane[148]:')[1].split('plane[165]:')[0]
        assert 'crtc=video_port0' in part and 'format=AR24' in part and 'crtc-pos=1920x1080+0+0' in part
        assert '\tfb='+str(report['framebuffer_id'])+'\n' in part
        report['state']='OVERLAY1190_REAL_POSE_MAPPED_ARGB_PLANE_UPDATED_NOT_OPTICAL'
    except BaseException as e:report['error']=repr(e);raise
    finally:
        if reader:reader.close()
        if handle:report['close_errno']=lib.overlay1190_close(handle)
        after=Path('/sys/kernel/debug/dri/0/state').read_text();(out/'atomic_after.txt').write_text(after)
        report['plane_released']='crtc=(null)' in after.split('plane[148]:')[1].split('plane[165]:')[0]
        if not report['plane_released'] or report.get('close_errno',0):report['state']='FAILED'
        if isinstance(report.get('updates'),RowJournal) and not report['updates'].closed:report['updates'].close()
        (out/'report.json').open('x').write(json.dumps(report,indent=2,default=journal_json))

if __name__=='__main__':main()
