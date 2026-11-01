from long_journal1295 import RowJournal,journal_json
from session_config1301 import runtime_seconds
import sys
sys.path.append('/userdata/integrated1013_20261027')
"""Independent latest real JPEG -> RKNN pose -> persistent fall scene."""
from pathlib import Path
import argparse,hashlib,json,mmap,os,sqlite3,sys,time,signal
import cv2,numpy as np
from latest_decode1790 import LatestDecode
from record_slots847 import snapshot
from alarm723 import AlarmStore
from persistent_monitor1196 import open_monitor
sys.path.insert(0,'/home/anmi/soak2h727_20261026_v1')
from replay_raw_npu import MODEL,PACKAGE,check_package
sys.path.insert(0,str(PACKAGE))
from rknnlite.api import RKNNLite
from pose_remedy1806 import infer_pose, configure_scene, VERSION as REMEDY_VERSION

def main():
    p=argparse.ArgumentParser()
    for name in ('shared','output','session','alarm-db'):p.add_argument('--'+name,required=True)
    p.add_argument('--generation',type=int,required=True);p.add_argument('--max-seconds',type=runtime_seconds,required=True);a=p.parse_args()
    out=Path(a.output);out.mkdir()
    report=dict(state='FAILED',frames=[],physical_latency_verified=False,fall_accuracy_verified=False)
    report['frames']=RowJournal(out/'frames.jsonl')
    package=check_package();runtime=RKNNLite();fd=None;mm=None;store=None;scene=None;pipeline=None
    def interrupted(sig,frame):raise SystemExit('signal '+str(sig))
    for sig in (signal.SIGTERM,signal.SIGHUP):signal.signal(sig,interrupted)
    try:
        assert runtime.load_rknn(str(MODEL))==0
        assert runtime.init_runtime(core_mask=RKNNLite.NPU_CORE_0_1)==0
        configure_scene()
        report['pose_remedy']=dict(version=REMEDY_VERSION,files_sha256={name:hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest() for name in ('pose_remedy1806.py','pose_fall1806.py')})
        store,scene,startup=open_monitor(a.alarm_db,a.session);report['persistent_alarm_startup']=startup
        fd=os.open(a.shared,os.O_RDONLY|os.O_NOFOLLOW);mm=mmap.mmap(fd,0,access=mmap.ACCESS_READ)
        def latest_source(last):
            frames,busy=snapshot(fd,mm,a.generation,last)
            return frames[-1] if frames else None
        def decode_image(row):
            frame,completed,data=row
            started=time.monotonic_ns()
            image=cv2.imdecode(np.frombuffer(data,dtype=np.uint8),cv2.IMREAD_COLOR)
            assert image is not None and image.shape==(1080,1920,3)
            image=cv2.rotate(image,cv2.ROTATE_180)
            return frame,completed,data,started,image,time.monotonic_ns()
        pipeline=LatestDecode(latest_source,decode_image).start()
        last=None;deadline=time.monotonic()+a.max_seconds
        (out/'ready.tmp').open('x').write(json.dumps(dict(generation=a.generation,session=a.session)))
        os.replace(out/'ready.tmp',out/'ready.json')
        while True:
            row=pipeline.take()
            if row is not None:
                frame,completed,data,started,image,decoded_at=row
                assert last is None or frame>last
                inference_started=time.monotonic_ns()
                people,timing=infer_pose(runtime,image)
                timing.update(jpeg_decode_rotate_ms=(decoded_at-started)/1e6,
                              decoded_wait_ms=(inference_started-decoded_at)/1e6)
                state=scene.update(frame,completed/1e9,people,1920,1080)
                finished=time.monotonic_ns()
                report['frames'].append(dict(frame_id=frame,completed_ns=completed,
                    jpeg_sha256=hashlib.sha256(data).hexdigest(),started_ns=started,finished_ns=finished,
                    host_completion_to_result_ms=(finished-completed)/1e6,people=people,fall_state=state,**timing))
                current=dict(generation=a.generation,session=a.session,observation=report['frames'][-1],observations=len(report['frames']))
                temporary=out/'latest1184.tmp'
                with temporary.open('w') as latest:json.dump(current,latest)
                os.replace(temporary,out/'latest1184.json')
                last=frame
            if (out/'stop').exists():break
            if time.monotonic()>deadline:raise TimeoutError('Pose worker exceeded bound')
            time.sleep(.002)
        assert check_package()==package
        assert report['frames']
        report.update(state='LIVE1012_REAL_RKNN_POSE_AND_PERSISTENT_SCENE_RAN',package_hashes=package,
            active_alarm=store.active(),observations=len(report['frames']))
    except BaseException as e:
        report['error']=repr(e);raise
    finally:
        decoder_stopped=True
        if pipeline:
            try:report['decode_pipeline']=pipeline.close()
            except BaseException as error:
                decoder_stopped=False
                report.update(state='FAILED',error=repr(error))
        if store:
            try:
                report['stop_hold_transition']=scene.stop(time.monotonic())
                report['active_alarm_after_stop']=store.active()
                store.snapshot(out/'alarms.sqlite')
            finally:store.close()
        if mm and decoder_stopped:mm.close()
        if fd is not None and decoder_stopped:os.close(fd)
        runtime.release()
        if (out/'alarms.sqlite').exists():
            with sqlite3.connect(out/'alarms.sqlite') as db:
                report['database_integrity']=db.execute('PRAGMA integrity_check').fetchone()[0]
                report['incidents']=db.execute('SELECT count(*) FROM incidents').fetchone()[0]
        if isinstance(report.get('frames'),RowJournal) and not report['frames'].closed:report['frames'].close()
        (out/'report.json').open('x').write(json.dumps(report,indent=2,default=journal_json))
        if not decoder_stopped:raise RuntimeError(report['error'])

if __name__=='__main__':main()
