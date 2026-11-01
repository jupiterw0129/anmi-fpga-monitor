"""Bounded field session harness. No synthetic incidents; no FPGA programming."""
from pathlib import Path
import argparse, hashlib, json, os, signal, sqlite3, subprocess, sys, time

N = Path('/userdata/native_required1138_20261028')
BASE = N/'field1382'
DB = BASE/'alarms.sqlite'
sys.path.insert(0, str(N))
sys.path.insert(0, '/userdata/integrated1013_20261027')
from alarm723 import AlarmStore
from field_failure1793 import controller_failure,read_log_tail,failed_consumers,consumer_failure_reason


def atomic(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value))
    os.replace(temporary, path)


def tail(path):
    if not path.exists():
        return None
    with path.open('rb') as f:
        f.seek(max(0, path.stat().st_size-65536))
        rows = f.read().splitlines()
    for line in reversed(rows):
        try:
            return json.loads(line)
        except ValueError:
            continue


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--name', required=True)
    ap.add_argument('--seconds', type=int, required=True, choices=(0,10,30,60,180,300,600,1800,3600,7200))
    ap.add_argument('--preprocess', type=int, default=0, choices=range(4))
    ap.add_argument('--compression',choices=('quality','target'),default='quality')
    ap.add_argument('--jpeg-quality',type=int,choices=(25,50,75),default=50)
    ap.add_argument('--target-mbps',type=float,default=36)
    ap.add_argument('--binary-threshold',type=int,choices=range(256))
    ap.add_argument('--hdmi',action='store_true',help='Enable physical HDMI output; default is PC preview only')
    a = ap.parse_args()
    capture_seconds=a.seconds or 7200
    import re
    assert re.fullmatch(r'field_[0-9_]+', a.name)
    BASE.mkdir(exist_ok=True)
    out = BASE/a.name
    out.mkdir()
    root = N/'evidence'/a.name
    mount = Path('/mnt')/a.name
    mount.mkdir()
    store = AlarmStore(DB)
    store.close()
    canonical = Path('/userdata/elderly_monitor1196/alarms.sqlite')
    original = hashlib.sha256(canonical.read_bytes()).hexdigest()
    report = dict(state='FAILED', synthetic_incident=False, name=a.name,
                  seconds=a.seconds, manual_stop=a.seconds==0, safety_limit_seconds=capture_seconds, preprocess=a.preprocess,
                  compression=a.compression,jpeg_quality=a.jpeg_quality,target_mbps=a.target_mbps,
                  binary_threshold=a.binary_threshold,field_alarm_database=str(DB))
    report['hdmi_enabled']=a.hdmi
    atomic(out/'identity.json', dict(pid=os.getpid(), start_ticks=Path('/proc/self/stat').read_text().rsplit(')', 1)[1].split()[19]))
    controller = None
    mounted = False
    def interrupted(sig, frame):
        # Let the controller request QUIESCED and drain its native FIFOs.
        (out/'stop_requested').touch(exist_ok=True)
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGHUP, interrupted)
    try:
        assert subprocess.run(['findmnt', '-rn', '-S', '/dev/mmcblk1p1'], capture_output=True).returncode == 1
        assert subprocess.check_output(['blkid', '-s', 'UUID', '-o', 'value', '/dev/mmcblk1p1'], text=True).strip() == '0403-0201'
        subprocess.run(['mount', '-t', 'vfat', '-o', 'rw,nosuid,nodev,noexec', '/dev/mmcblk1p1', str(mount)], check=True)
        mounted = True
        args = ['python3', '-B', str(N/'control_field1382.py'), '--name', a.name,
                '--frames', str(capture_seconds*60), '--beats', '486', '--lines', '1097',
                '--delay', '48', '--preprocess', str(a.preprocess), '--bayer-phase', '2', '--recordings', str(mount/a.name),
                '--compression',a.compression,'--jpeg-quality',str(a.jpeg_quality),'--target-mbps',str(a.target_mbps)]
        if a.binary_threshold is not None:args+=['--binary-threshold',str(a.binary_threshold)]
        if not a.hdmi:args+=['--headless']
        with (out/'controller.stdout').open('xb') as stdout, (out/'controller.stderr').open('xb') as stderr:
            controller = subprocess.Popen(args, stdout=stdout, stderr=stderr)
            deadline = time.monotonic()+capture_seconds+300
            while controller.poll() is None:
                if time.monotonic() > deadline:
                    controller.terminate()
                    raise TimeoutError('Field controller exceeded bounded session deadline')
                time.sleep(.2)
        report['controller_returncode'] = controller.returncode
        if controller.returncode != 0 or not (root/'session.json').exists():
            report['controller_diagnostics'] = controller_failure(controller.returncode,
                read_log_tail(out/'controller.stderr'),read_log_tail(out/'controller.stdout'))
        if not (root/'session.json').exists():
            raise RuntimeError(report['controller_diagnostics']['reason'])
        session = json.loads((root/'session.json').read_text())
        report['cleanup_verified'] = session['cleanup_verified']
        report['driver_restored'] = session['driver_restored']
        if controller.returncode != 0:
            failures=failed_consumers(root)
            report['consumer_failures']=failures
            reason=consumer_failure_reason(failures) if failures else session.get('error') or report['controller_diagnostics']['reason']
            report['controller_diagnostics']['reason']=reason
            raise RuntimeError(reason)
        report['native'] = session['native']
        interval=report['native']['last_completed']-report['native']['first_completed']
        report['source_completion_fps']=(report['native']['committed']-1)/interval if interval>0 else None
        report['sd'] = json.loads((root/'sd/report.json').read_text())
        assert session['hdmi_enabled'] == a.hdmi
        report['video'] = json.loads((root/'video1008/report.json').read_text()) if a.hdmi else dict(enabled=False,reason='HDMI disabled; PC preview and recording remain enabled')
        report['pose'] = json.loads((root/'pose/report.json').read_text())
        report['compression_result']=json.loads((root/'compression.latest.json').read_text())
        report['advanced_config']=session['advanced_config']
        assert report['sd']['frames'] == session['native']['committed']
        if a.hdmi:
            assert report['video']['sink_stats']['rendered'] == session['native']['committed']
            assert report['video']['sink_stats']['dropped'] == 0
        report['state'] = 'FIELD_SESSION_FINISHED'
    except BaseException as e:
        report['error'] = repr(e)
    finally:
        if controller is not None and controller.poll() is None:
            controller.terminate()
            try:
                controller.wait(timeout=80)
            except subprocess.TimeoutExpired:
                # Do not blindly kill a controller while it is restoring hardware.
                report['cleanup_error'] = 'Controller did not finish restoration within80s'
        if mounted:
            result = subprocess.run(['umount', str(mount)], capture_output=True, text=True, timeout=30)
            report['sd_unmounted'] = result.returncode == 0
            if result.returncode:
                report['state'] = 'FAILED'
                report['unmount_error'] = result.stderr
        report['canonical_unchanged'] = hashlib.sha256(canonical.read_bytes()).hexdigest() == original
        if not report['canonical_unchanged']:
            report['state'] = 'FAILED'
        atomic(out/'report.json', report)
        print(json.dumps(report), flush=True)
    if report['state'] != 'FIELD_SESSION_FINISHED':
        raise SystemExit(1)


if __name__ == '__main__':
    main()
