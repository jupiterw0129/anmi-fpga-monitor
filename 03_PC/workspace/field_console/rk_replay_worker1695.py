"""Exact recorded FPGA JPEG -> production RK NPU and isolated production scene."""
from pathlib import Path
import argparse,fcntl,hashlib,json,mmap,os,re,sqlite3,struct,sys,tarfile,time

N=Path('/userdata/native_required1138_20261028')
sys.path.insert(0,str(N));sys.path.append('/userdata/integrated1013_20261027')
sys.path.insert(0,'/home/anmi/soak2h727_20261026_v1')
sys.path.insert(0,'/home/anmi/offline_demo/python-packages')


def sha(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
        for chunk in iter(lambda:f.read(1<<20),b''):h.update(chunk)
    return h.hexdigest()


def unpack(archive,directory):
    with tarfile.open(archive,'r') as tar:
        members=tar.getmembers()
        if len({m.name for m in members})!=len(members) or any(not m.isfile() for m in members):raise ValueError('regular unique members required')
        member=tar.getmember('manifest.json')
        if member.size>20*1024**2:raise ValueError('manifest too large')
        manifest=json.load(tar.extractfile(member))
        frames=manifest['frames']
        if not 1<=len(frames)<=6000:raise ValueError('bounded replay supports 1..6000 original inference frames')
        names={'manifest.json'}|{r['jpeg'] for r in frames}
        if names!={m.name for m in members} or len(names)!=len(frames)+1:raise ValueError('archive membership mismatch')
        for row in frames:
            if not re.fullmatch(r'frame_[0-9]{9}\.jpg',row['jpeg']):raise ValueError('unsafe image name')
        directory.mkdir()
        for member in members:
            if member.size>1920*1080*6+65536 and member.name!='manifest.json':raise ValueError('oversized image')
            with tar.extractfile(member) as src,(directory/member.name).open('xb') as dst:
                while True:
                    block=src.read(1<<20)
                    if not block:break
                    dst.write(block)
        for row in frames:
            if sha(directory/row['jpeg'])!=row['jpeg_sha256']:raise ValueError('JPEG digest mismatch')
    return manifest


def main():
    import cv2,numpy as np
    from replay_raw_npu import check_package,PACKAGE,MODEL
    from persistent_monitor1196 import open_monitor
    import scene741,persistent_monitor1196,pose_fall,alarm723
    sys.path.insert(0,str(PACKAGE))
    from pose_rknn import infer_pose
    from rknnlite.api import RKNNLite
    parser=argparse.ArgumentParser();parser.add_argument('--directory',required=True);args=parser.parse_args()
    root=Path(args.directory).resolve()
    if root.parent!=Path('/userdata/fpga_replay1695') or not re.fullmatch(r'replay_[0-9_]+',root.name):raise ValueError('unexpected task directory')
    with (N/'offline1695.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        with (Path('/sys/bus/pci/devices/0000:21:00.0/resource0')).open('rb',buffering=0) as f,mmap.mmap(f.fileno(),4096,access=mmap.ACCESS_READ) as mm:
            if any(struct.unpack_from('<I',mm,i)[0] for i in (0x60,0xa4)):raise ValueError('capture running; stop before replay')
        manifest=unpack(root/'inputs.tar',root/'inputs')
        remedy_version=manifest.get('pose_remedy_version')
        if remedy_version is not None:
            from pose_remedy1806 import infer_pose,configure_scene,VERSION
            if remedy_version!=VERSION:raise ValueError('unsupported saved pose remedy version')
            configure_scene()
        output=root/'results';output.mkdir()
        package=check_package();runtime=RKNNLite();store=scene=None
        report=dict(state='FAILED',live_fpga=False,accuracy_verified=False,physical_latency_verified=False,
            source_session=manifest['source_session'],input_archive_sha256=sha(root/'inputs.tar'),pose_remedy_version=remedy_version,
            package_hashes=package,production_scene_hashes={str(Path(p.__file__)):sha(p.__file__) for p in (scene741,persistent_monitor1196,pose_fall,alarm723)},
            sampling='exact original live-inference source frame IDs, original JPEG bytes and original board timestamps')
        count=0;began=time.monotonic();last=-1
        try:
            if runtime.load_rknn(str(MODEL)) or runtime.init_runtime(core_mask=RKNNLite.NPU_CORE_0_1):raise RuntimeError('RKNN init failed')
            store,scene,startup=open_monitor(str(output/'alarms.sqlite'),root.name)
            report['alarm_startup']=startup
            with (output/'inferred.jsonl').open('x') as log:
                for row in manifest['frames']:
                    if row['frame_id']<=last:raise ValueError('non-increasing source frame ID')
                    last=row['frame_id']
                    raw=(root/'inputs'/row['jpeg']).read_bytes()
                    image=cv2.imdecode(np.frombuffer(raw,dtype=np.uint8),cv2.IMREAD_COLOR)
                    if image is None or image.shape!=(1080,1920,3):raise ValueError('invalid recorded image')
                    image=cv2.rotate(image,cv2.ROTATE_180)
                    people,timing=infer_pose(runtime,image)
                    state=scene.update(row['frame_id'],row['completed_ns']/1e9,people,1920,1080)
                    log.write(json.dumps(dict(frame_id=row['frame_id'],jpeg_sha256=row['jpeg_sha256'],
                        completed_ns=row['completed_ns'],input_upright_bgr_sha256=hashlib.sha256(image.tobytes()).hexdigest(),
                        people=people,fall_state=state,**timing))+'\n');log.flush();count+=1
                    if count%200==0:print(json.dumps(dict(inferences=count)),flush=True)
            if check_package()!=package:raise ValueError('model package changed during replay')
            report.update(state='RK1695_EXACT_JPEG_PRODUCTION_NPU_REPLAY_FINISHED',inferences=count,elapsed_s=time.monotonic()-began,
                transitions=[dict(r) for r in store.db.execute('SELECT * FROM transitions ORDER BY seq')],
                active_alarm=store.active(),database_integrity=store.db.execute('PRAGMA integrity_check').fetchone()[0])
        except BaseException as error:
            report['error']=repr(error);raise
        finally:
            if store:store.close()
            runtime.release()
            (output/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
        print(json.dumps(dict(state=report['state'],inferences=count)),flush=True)


if __name__=='__main__':main()
