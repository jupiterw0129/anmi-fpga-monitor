"""Camera preview: no SD mount, no NPU worker, no alarm database mutation."""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time

N=Path('/userdata/native_required1138_20261028')


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--name',required=True)
    parser.add_argument('--seconds',type=int,choices=range(10,601),required=True)
    parser.add_argument('--preprocess',type=int,choices=range(4),default=0)
    parser.add_argument('--compression',choices=('quality','target'),default='quality')
    parser.add_argument('--jpeg-quality',type=int,choices=(25,50,75),default=50)
    parser.add_argument('--target-mbps',type=float,default=36)
    parser.add_argument('--binary-threshold',type=int,choices=range(256))
    args=parser.parse_args()
    if not re.fullmatch(r'field_[0-9_]+',args.name):raise ValueError('Invalid preview identity')
    base=N/'field1382'/args.name;base.mkdir()
    root=N/'evidence'/args.name
    (base/'identity.json').write_text(json.dumps(dict(pid=os.getpid(),
        start_ticks=Path('/proc/self/stat').read_text().rsplit(')',1)[1].split()[19],purpose='preview')))
    def stop(signum,frame):(base/'stop_requested').touch(exist_ok=True)
    signal.signal(signal.SIGHUP,stop);signal.signal(signal.SIGTERM,stop)
    report=dict(state='FAILED',preview_only=True,sd_enabled=False,npu_enabled=False)
    cmd=['python3','-B',str(N/'control_field1382.py'),'--name',args.name,'--frames',str(args.seconds*60),
        '--beats','486','--lines','1097','--delay','48','--preprocess',str(args.preprocess),'--bayer-phase','2',
        '--recordings',str(base/'unused_recordings'),'--compression',args.compression,
        '--jpeg-quality',str(args.jpeg_quality),'--target-mbps',str(args.target_mbps),'--headless','--preview-only']
    if args.binary_threshold is not None:cmd+=['--binary-threshold',str(args.binary_threshold)]
    controller=None
    try:
        with (base/'controller.stdout').open('xb') as out,(base/'controller.stderr').open('xb') as err:
            controller=subprocess.Popen(cmd,stdout=out,stderr=err)
            deadline=time.monotonic()+args.seconds+100
            while controller.poll() is None:
                if time.monotonic()>deadline:
                    (base/'stop_requested').touch(exist_ok=True)
                    raise TimeoutError('Preview deadline exceeded')
                time.sleep(.1)
        session=json.loads((root/'session.json').read_text())
        report.update(native=session.get('native'),driver_restored=session['driver_restored'],
                      cleanup_verified=session['cleanup_verified'],controller_returncode=controller.returncode)
        if controller.returncode or not report['driver_restored'] or not report['cleanup_verified']:
            raise RuntimeError('Preview controller failed: '+str(session.get('error')))
        n=report['native'];interval=n['last_completed']-n['first_completed']
        report.update(state='FIELD_SESSION_FINISHED',source_completion_fps=(n['committed']-1)/interval if interval else None)
    except BaseException as error:report['error']=repr(error)
    finally:
        if controller is not None and controller.poll() is None:
            (base/'stop_requested').touch(exist_ok=True)
            try:controller.wait(timeout=70)
            except subprocess.TimeoutExpired:report['cleanup_error']='Controller restoration still pending'
        (base/'report.json').write_text(json.dumps(report,indent=2))
        print(json.dumps(report),flush=True)
    if report['state']!='FIELD_SESSION_FINISHED':raise SystemExit(1)


if __name__=='__main__':main()
