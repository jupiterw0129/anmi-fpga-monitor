"""Board-owned cloud transport. Reads live detector output; never controls DMA."""
import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import re
import signal
import sqlite3
import threading
import time

from cloud1694 import CloudBridge

NATIVE = Path('/userdata/native_required1138_20261028')
HOME = Path('/userdata/board_cloud')


def atomic_json(path, value):
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(value, ensure_ascii=False), encoding='utf-8')
    os.replace(temp, path)


def active_session(proc=Path('/proc')):
    """Only a running live pose worker qualifies, never previews or old files."""
    for path in proc.glob('[0-9]*/cmdline'):
        try:
            args = path.read_bytes().decode().strip('\0').split('\0')
            if str(NATIVE/'live_pose1420.py') not in args:
                continue
            name = args[args.index('--session')+1]
            if re.fullmatch(r'field_[0-9_]+', name):
                return name
        except (OSError, UnicodeError, ValueError, IndexError):
            continue
    return None


def live_snapshot(name, native=NATIVE, now_ns=None):
    if name is None or not re.fullmatch(r'field_[0-9_]+', name):
        return None
    if (native/'field1382'/name/'report.json').exists():
        return None
    now_ns = time.monotonic_ns() if now_ns is None else now_ns
    try:
        row = json.loads((native/'evidence'/name/'pose/latest1184.json').read_text())
        pose = row['observation']
        age = now_ns-pose['finished_ns']
        if row.get('session') != name or not 0 <= age < 2_000_000_000:
            return None
    except (OSError, ValueError, KeyError, TypeError):
        return None
    alarm = None
    dbpath = native/'field1382/alarms.sqlite'
    if dbpath.exists():
        # An unreadable alarm DB must not clear a real alarm in the cloud.
        with closing(sqlite3.connect(dbpath.as_uri()+'?mode=ro', uri=True, timeout=.05)) as db:
            db.row_factory = sqlite3.Row
            value = db.execute("SELECT * FROM incidents WHERE status!='CLOSED' ORDER BY id DESC LIMIT 1").fetchone()
            alarm = dict(value) if value else None
    return dict(phase='RUNNING', purpose='test', session=name,
                fast_pose=dict(pose=pose, board_monotonic_ns=now_ns, pc_received_ns=now_ns),
                telemetry=dict(alarm=alarm))


class Backend:
    def __init__(self):
        from board_background import CameraBackground
        self.LOCK = threading.RLock()
        self.STATE = {}
        self.DATA = NATIVE/'evidence'
        self.APPROVED_BACKGROUND = None
        self.camera_background=CameraBackground()

    def handle_background(self,command,upload):
        return self.camera_background.handle(command,upload)

    @staticmethod
    def log(message):
        print(message, flush=True)


def main():
    import fcntl
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', default=str(HOME/'config.json'))
    args = parser.parse_args()
    HOME.mkdir(exist_ok=True, mode=0o700)
    with (HOME/'daemon.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        backend = Backend()
        bridge = CloudBridge(args.config, backend)
        signal.signal(signal.SIGTERM, lambda *_: bridge.stop())
        signal.signal(signal.SIGINT, lambda *_: bridge.stop())
        bridge.start()
        name = None
        next_scan = 0
        try:
            while not bridge.end.wait(.1):
                try:
                    if time.monotonic() >= next_scan:
                        name = active_session()
                        next_scan = time.monotonic()+.5
                        config = json.loads(Path(args.config).read_text())
                        bridge.set_alarm_forwarding(config.get('forward_alarms', False))
                        background = HOME/'approved_background.jpg'
                        with backend.LOCK:
                            backend.APPROVED_BACKGROUND = background.read_bytes() if background.exists() else None
                    value = live_snapshot(name)
                    with backend.LOCK:
                        backend.STATE = value or {}
                    status = bridge.connection_status()
                    status.update(transport='board', session=name if value else None,
                                  heartbeat_ns=time.monotonic_ns(), pid=os.getpid())
                    atomic_json(HOME/'status.json', status)
                except (OSError, ValueError, sqlite3.Error) as error:
                    with backend.LOCK:
                        backend.STATE = {}
                    atomic_json(HOME/'status.json', dict(state='retrying', device_id=bridge.device_id,
                                transport='board', accepted_packets=bridge.connection_status()['accepted_packets'],
                                last_ack_ns=None, heartbeat_ns=time.monotonic_ns(), error=type(error).__name__))
        finally:
            bridge.stop()
            backend.camera_background.stop()
            bridge.thread.join(8)
            bridge.control_thread.join(8)
            atomic_json(HOME/'status.json', dict(state='stopped', device_id=bridge.device_id,
                        accepted_packets=bridge.connection_status()['accepted_packets'], last_ack_ns=None,
                        transport='board', heartbeat_ns=time.monotonic_ns()))


if __name__ == '__main__':
    main()
