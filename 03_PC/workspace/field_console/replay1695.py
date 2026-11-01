"""Run the saved FPGA JPEGs through RK again without recapturing or relabeling."""
from pathlib import Path
from datetime import datetime
from collections import Counter
import argparse,hashlib,json,subprocess,tarfile,threading
from evaluate_field1416 import load_session,digest,rows,summary

ROOT=Path(__file__).resolve().parent
SSH=['ssh.exe','-T','-o','BatchMode=yes','-o','ConnectTimeout=8','rk3576']
HIDDEN=dict(creationflags=subprocess.CREATE_NO_WINDOW) if __import__('os').name=='nt' else {}


def prepare(directory):
    directory=Path(directory).resolve()
    protected=Path('C:/Users/Jupiterw/OneDrive').resolve()
    if directory==protected or protected in directory.parents:raise ValueError('OneDrive目录受保护')
    checked=load_session(directory)
    reference=list(rows(directory/'pose.frames.jsonl'))
    if not 1<=len(reference)<=6000:raise ValueError('本轮支持最多6000个原始推理帧；长会话请分段复盘')
    key='replay_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f')
    out=directory/'replays'/key;images=out/'inputs';images.mkdir(parents=True)
    selected={r['frame_id']:r for r in reference};frames=[]
    for clip in checked['recordings']:
        movie=directory/clip['name'];manifest=list(rows(movie.with_suffix('.frames.jsonl')))
        # Demux stream copy. Never seek to Matroska packet.pos: it includes
        # block metadata and isn't the first byte of the JPEG payload.
        with (out/(movie.stem+'.demux.stderr')).open('xb') as error:
            process=subprocess.Popen(['ffmpeg','-hide_banner','-loglevel','error','-nostdin','-i',str(movie),
                '-map','0:v:0','-c:v','copy','-f','mjpeg','pipe:1'],stdout=subprocess.PIPE,stderr=error,**HIDDEN)
            try:
                for source in manifest:
                    size=source['bytes'];raw=bytearray()
                    while len(raw)<size:
                        block=process.stdout.read(size-len(raw))
                        if not block:raise EOFError('demux stream truncated')
                        raw.extend(block)
                    if hashlib.sha256(raw).hexdigest()!=source['jpeg_sha256']:raise ValueError('demux JPEG digest mismatch')
                    frame=source['frame_id']
                    if frame in selected:
                        name=f'frame_{frame:09d}.jpg';(images/name).write_bytes(raw)
                        frames.append(dict(frame_id=frame,completed_ns=selected[frame]['completed_ns'],jpeg=name,jpeg_sha256=source['jpeg_sha256']))
                if process.stdout.read(1):raise ValueError('unexpected JPEG data after manifest')
                if process.wait(timeout=15):raise RuntimeError('demux failed')
            finally:
                process.stdout.close()
                if process.poll() is None:process.terminate();process.wait(timeout=10)
    frames.sort(key=lambda row:row['frame_id'])
    if [r['frame_id'] for r in frames]!=sorted(selected):raise ValueError('original inference input coverage incomplete')
    if not all(digest(directory/name)==sha for name,sha in checked['bindings'].items()):raise ValueError('input changed during preparation')
    versions={r.get('remedy_version') for r in reference}
    if len(versions)!=1:raise ValueError('原会话检测实现版本不一致')
    manifest=dict(schema_version=1,source_session=directory.name,bindings=checked['bindings'],frames=frames,
                  pose_remedy_version=versions.pop(),
                  orientation='rotate180 before production inference',accuracy_verified=False)
    (images/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    with tarfile.open(out/'inputs.tar','x') as tar:
        for p in sorted(images.iterdir()):tar.add(p,arcname=p.name,recursive=False)
    return out,reference,checked


def compare(reference,inferred):
    if [r['frame_id'] for r in reference]!=[r['frame_id'] for r in inferred]:raise ValueError('replay output frame coverage mismatch')
    differences=[]
    for old,new in zip(reference,inferred):
        if old['jpeg_sha256']!=new['jpeg_sha256'] or old['completed_ns']!=new['completed_ns']:raise ValueError('replay input identity mismatch')
        fields=[]
        if old['people']!=new['people']:fields.append('people')
        for key in ('state','reason','detector_event'):
            if old['fall_state'].get(key)!=new['fall_state'].get(key):fields.append('fall_state.'+key)
        if fields:differences.append(dict(frame_id=old['frame_id'],fields=fields))
    return dict(compared_frames=len(reference),exact_output_match_frames=len(reference)-len(differences),differences=differences,
                scope='同JPEG/同源时刻的输出重现比较；非独立真值、准确率或实时吞吐；告警数据库隔离，事件编号不比较')


def run_replay(directory,backend=None):
    import server as b
    backend=backend or b
    with backend.LOCK:
        if backend.STATE.get('offline_busy') or (backend.THREAD and backend.THREAD.is_alive()):raise ValueError('请先停止实时测试或等待离线复盘结束')
        from resource_gate1695 import acquire
        lease=acquire()
        backend.STATE['offline_busy']=True
    try:
        probe=backend.preflight()
        if not probe['ready']:raise ValueError(probe['reason'])
        backend.log('RK离线复盘：核验并提取原始JPEG，不启动相机')
        out,reference,checked=prepare(directory)
        remote='/userdata/fpga_replay1695/'+out.name
        subprocess.run(SSH+['mkdir','-p',remote],check=True,timeout=20,**HIDDEN)
        subprocess.run(['scp.exe',str(out/'inputs.tar'),str(ROOT/'rk_replay_worker1695.py'),'rk3576:'+remote+'/'],check=True,timeout=120,capture_output=True,**HIDDEN)
        with (out/'rk.stdout').open('xb') as stdout,(out/'rk.stderr').open('xb') as stderr:
            result=subprocess.run(SSH+['python3','-B',remote+'/rk_replay_worker1695.py','--directory',remote],stdout=stdout,stderr=stderr,timeout=900,**HIDDEN)
        if result.returncode:
            (out/'failure.json').write_text(json.dumps(dict(state='RK1695_REPLAY_FAILED',returncode=result.returncode,remote=remote,stderr=(out/'rk.stderr').read_text(encoding='utf-8',errors='replace')[-4000:]),ensure_ascii=False,indent=2),encoding='utf-8')
            raise RuntimeError('RK重新检测失败，保留日志：'+str(out/'failure.json'))
        for name in ('inferred.jsonl','report.json','alarms.sqlite'):
            subprocess.run(['scp.exe','rk3576:'+remote+'/results/'+name,str(out/name)],check=True,timeout=45,capture_output=True,**HIDDEN)
        result.check_returncode()
        report=json.loads((out/'report.json').read_text(encoding='utf-8'));inferred=list(rows(out/'inferred.jsonl'))
        if report['state']!='RK1695_EXACT_JPEG_PRODUCTION_NPU_REPLAY_FINISHED' or report['input_archive_sha256']!=digest(out/'inputs.tar'):raise ValueError('RK replay failed or archive identity changed')
        comparison=compare(reference,inferred)
        comparison.update(state='RK1695_REPLAY_COMPARED',source_bindings=checked['bindings'],
            state_counts=dict(Counter(r['fall_state']['state'] for r in inferred)),
            reason_counts=dict(Counter(r['fall_state'].get('reason') or 'valid_observation' for r in inferred)),
            npu_ms=summary([r['npu_ms'] for r in inferred]),
            input_archive_sha256=digest(out/'inputs.tar'),accuracy_verified=False,
            source_files_unchanged=all(digest(Path(directory)/name)==sha for name,sha in checked['bindings'].items()),
            postflight=backend.preflight())
        if not comparison['source_files_unchanged'] or not comparison['postflight']['ready']:raise ValueError('input or board postflight changed')
        (out/'comparison.json').write_text(json.dumps(comparison,ensure_ascii=False,indent=2),encoding='utf-8')
        lines=['# RK原片重新检测', '',str(directory),'',
               f"比较 {comparison['compared_frames']} 帧；完全重现 {comparison['exact_output_match_frames']} 帧；差异 {len(comparison['differences'])} 帧。",'',
               comparison['scope'],'','状态分布：'+json.dumps(comparison['state_counts'],ensure_ascii=False),
               '观测原因：'+json.dumps(comparison['reason_counts'],ensure_ascii=False),
               '', '所有本轮告警保存在独立数据库，不修改实时告警、不发送云端。人工真值仍使用原会话复核记录，不能用复盘输出自动生成真值。']
        (out/'RK复盘报告.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
        backend.log('RK离线复盘完成：'+str(out))
        return out,comparison
    finally:
        with backend.LOCK:backend.STATE['offline_busy']=False
        lease.close()


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('session',type=Path);a=parser.parse_args()
    out,result=run_replay(a.session)
    print(json.dumps(dict(output=str(out),compared=result['compared_frames'],exact=result['exact_output_match_frames']),ensure_ascii=False))
