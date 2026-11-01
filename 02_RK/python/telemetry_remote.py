"""Read-only bounded telemetry; only explicit operator actions mutate field DB."""
from pathlib import Path
import argparse, json, mmap, os, sqlite3, struct, sys, time
N = Path('/userdata/native_required1138_20261028')
sys.path.insert(0,str(N))
from pose_rate1420 import ObservationRate
BASE = N/'field1382'
ap = argparse.ArgumentParser()
ap.add_argument('--name', required=True)
ap.add_argument('--action', choices=('status', 'stop', 'ack', 'resolve'), default='status')
ap.add_argument('--incident', type=int)
ap.add_argument('--reason', default='')
a = ap.parse_args()
import re
assert re.fullmatch(r'field_[0-9_]+', a.name)
out = BASE/a.name
if a.action == 'stop':
    assert out.is_dir()
    (out/'stop_requested').touch(exist_ok=True)
    print(json.dumps(dict(stopping=True)))
    raise SystemExit()
if a.action in ('ack', 'resolve'):
    sys.path.insert(0, '/userdata/integrated1013_20261027')
    from alarm723 import AlarmStore
    assert a.incident is not None and a.reason.strip()
    store = AlarmStore(BASE/'alarms.sqlite')
    try:
        result = store.apply(a.action.upper(), 'FIELD_OPERATOR', time.monotonic(), a.reason, a.incident)
        print(json.dumps(dict(transition=result, active=store.active())))
    finally:
        store.close()
    raise SystemExit()

sys.path.insert(0, str(BASE))
from field_remote import tail
last_cpu = last_metric = None
pose_rate = ObservationRate()
deadline=time.monotonic()+7800
while time.monotonic()<deadline:
    try:
        row = dict(board_monotonic_ns=time.monotonic_ns(), session=a.name)
        root = N/'evidence'/a.name
        fdpath = Path('/sys/bus/pci/devices/0000:21:00.0/resource0')
        with fdpath.open('rb', buffering=0) as f, mmap.mmap(f.fileno(), 4096, access=mmap.ACCESS_READ) as m:
            row['registers'] = {hex(i): struct.unpack_from('<I', m, i)[0] for i in (0x5c, 0x60, 0x84, 0xcc, 0xd0, 0x134, 0x1d0,0x1d4, 0x1d8, 0x1dc, 0x1e0, 0x1e4)}
        compression=root/'compression.latest.json'
        if compression.exists():row['compression']=json.loads(compression.read_text())
        preprocessing=root/'preprocess.latest.json'
        if preprocessing.exists():row['preprocess']=json.loads(preprocessing.read_text())
        pose = root/'pose/latest1184.json'
        if pose.exists():
            current_pose=json.loads(pose.read_text())
            row['pose'] = current_pose['observation']
            row['pose_count'] = current_pose['observations']
            row['pose_fps'] = pose_rate.update(current_pose['observations'],row['pose']['finished_ns'],time.monotonic_ns())
            row['pose_rate_basis'] = 'producer_count_completion_clock_window_2s'
        for key, path in [('display', root/'video1008/sink_buffers.jsonl'), ('record', root/'sd/kernel_samples.jsonl')]:
            value = tail(path)
            if value is not None:
                row[key] = value if key == 'display' else {k: value[k] for k in ('progress', 'sampler_pending_bytes', 'sampler_peak_bytes', 'sampler_stats') if k in value}
        cpu = [int(x) for x in Path('/proc/stat').read_text().splitlines()[0].split()[1:9]]
        if last_cpu:
            total = sum(cpu)-sum(last_cpu)
            row['cpu_percent'] = 100*(1-(cpu[3]+cpu[4]-last_cpu[3]-last_cpu[4])/max(total, 1))
        last_cpu = cpu
        mem = {l.split(':')[0]: int(l.split()[1])*1024 for l in Path('/proc/meminfo').read_text().splitlines() if l.split(':')[0] in ('MemTotal', 'MemAvailable')}
        row['memory_percent'] = 100*(1-mem['MemAvailable']/mem['MemTotal'])
        row['temperature_c'] = int(Path('/sys/class/thermal/thermal_zone0/temp').read_text())/1000
        if (BASE/'alarms.sqlite').exists():
            with sqlite3.connect((BASE/'alarms.sqlite').as_uri()+'?mode=ro', uri=True, timeout=.05) as db:
                db.row_factory = sqlite3.Row
                active = db.execute("SELECT * FROM incidents WHERE status!='CLOSED'").fetchone()
                row['alarm'] = dict(active) if active else None
        report = out/'report.json'
        if report.exists():
            row['report'] = json.loads(report.read_text())
        print(json.dumps(row), flush=True)
        if 'report' in row:
            break
    except BaseException as e:
        print(json.dumps(dict(telemetry_error=repr(e), board_monotonic_ns=time.monotonic_ns())), flush=True)
    time.sleep(.5)
