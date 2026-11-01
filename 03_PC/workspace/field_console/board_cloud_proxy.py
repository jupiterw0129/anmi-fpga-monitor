"""PC controls/status for the board service; no PC cloud socket is opened."""
import base64
import json
import hashlib
from pathlib import Path
import threading
import time

HOME = '/userdata/board_cloud'
SERVICE = 'fpga-board-cloud.service'


class BoardCloudBridge:
    def __init__(self, config_path, backend):
        self.config = json.loads(Path(config_path).read_text(encoding='utf-8-sig'))
        self.backend = backend
        self.device_id = self.config['device_id']
        self.end = threading.Event()
        self.lock = threading.Lock()
        self.pending_background = False
        self.background = None
        self.background_version = None
        self.background_update = None
        self.background_io = threading.Lock()
        self.background_status = '背景待同步'
        self.submission_error = None
        self.submission_sha = None
        self._status = dict(state='connecting', device_id=self.device_id, transport='board',
                            accepted_packets=0, last_ack_ns=None, forward_alarms=False)

    def connection_status(self):
        with self.lock:
            return dict(self._status, background_status=self.background_status)

    def set_alarm_forwarding(self, enabled):
        if type(enabled) is not bool:
            raise ValueError('forward_alarms须为布尔值')
        with self.lock:
            self.config['forward_alarms'] = enabled

    def approve_background(self, data, expected_version=None):
        with self.lock:
            if not data:return  # Local display clearing never deletes cloud data.
            if self.pending_background:raise ValueError('背景正在提交，请等待结果')
            if expected_version is None:raise ValueError('请等待背景同步后再拍摄')
            self.background = data
            self.expected_version = expected_version
            self.submission_sha = hashlib.sha256(data).hexdigest()
            self.submission_error = None
            self.pending_background = True
            self.background_status = '背景提交中'

    def take_background_update(self):
        with self.lock:
            value, self.background_update = self.background_update, None
            return value

    def refresh_background(self, force=False, data=None, expected_version=None):
        from background_sync import validate
        with self.background_io:
            with self.lock:known = self.background_version
            payload = base64.b64encode(data).decode() if data else None
            code = ("import sys,json,base64\nsys.path.insert(0,'"+HOME+"')\n"
                    "from background_sync import BackgroundSync\n"
                    "r=BackgroundSync().exchange(known_version="+repr(None if force else known)+
                    ",data="+("base64.b64decode("+repr(payload)+")" if payload else "None")+
                    ",expected_version="+repr(expected_version)+")\nprint(json.dumps(r))")
            result = self.backend.ssh_json(code, timeout=30)
            meta = result.get('background')
            decoded = validate(result, self.device_id) if result.get('content_base64') else None
            with self.lock:
                if meta and (self.background_version is None or meta['background_version'] >= self.background_version):
                    if decoded:
                        self.background_update = (meta, decoded)
                    self.background_version = meta['background_version']
                elif meta is None and not result.get('sync_error'):
                    self.background_version = 0
                self.background_status = result.get('sync_error') or ('背景 v'+str(self.background_version)+' 已同步' if meta else '尚未设置背景')
                if data and result.get('sync_error'):
                    self.submission_error = result['sync_error']
                if meta and meta['sha256'] == self.submission_sha and meta['background_version'] > getattr(self, 'expected_version', 0):
                    self.submission_error = None
                if self.submission_error:self.background_status = '上次提交未确认：'+self.submission_error
            if result.get('sync_error'):self.backend.log(result['sync_error'])
            return result

    def start(self):
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def detach(self):
        """Closing the PC window detaches status monitoring, not board transport."""
        self.end.set()

    def stop(self):
        self.end.set()
        def shutdown():
            try:
                self.backend.ssh_json("import subprocess,json\nsubprocess.run(['systemctl','stop',"+repr(SERVICE)+"],check=True)\nprint('{}')")
            except Exception as error:
                self.backend.log('板端云端服务停止失败：'+type(error).__name__)
        threading.Thread(target=shutdown, daemon=True).start()

    def run(self):
        started = False
        applied = None
        next_background = 0
        while not self.end.is_set():
            try:
                if not started:
                    self.backend.ssh_json("import subprocess,json\nsubprocess.run(['systemctl','start',"+repr(SERVICE)+"],check=True)\nprint('{}')")
                    started = True
                with self.lock:
                    enabled = self.config.get('forward_alarms', False)
                    pending, data = self.pending_background, self.background
                    expected = getattr(self, 'expected_version', None)
                if enabled != applied:
                    self.backend.ssh_json("from pathlib import Path\nimport json,os\np=Path('"+HOME+"/config.json')\nc=json.loads(p.read_text());c['forward_alarms']="+repr(enabled)+"\nt=p.with_suffix('.tmp');t.write_text(json.dumps(c));t.chmod(0o600);os.replace(t,p)\nprint('{}')")
                    applied = enabled
                if pending:
                    try:
                        self.refresh_background(data=data, expected_version=expected)
                    except Exception:
                        with self.lock:
                            self.submission_error = '请检查连接后重新拍摄确认'
                            self.background_status = '上次提交未确认：'+self.submission_error
                        raise
                    finally:
                        with self.lock:self.pending_background = False
                elif time.monotonic() >= next_background:
                    try:
                        self.refresh_background()
                    except Exception:
                        with self.lock:self.background_status = '背景同步失败，保留原背景'
                    next_background = time.monotonic()+2
                value = self.backend.ssh_json("from pathlib import Path\nimport json,time\ns=json.loads(Path('"+HOME+"/status.json').read_text())\nnow=time.monotonic_ns()\ns['ack_age_ns']=now-s['last_ack_ns'] if s.get('last_ack_ns') else None\ns['heartbeat_age_ns']=now-s['heartbeat_ns']\nprint(json.dumps(s))")
                if not 0 <= value['heartbeat_age_ns'] < 5_000_000_000:
                    raise ValueError('stale board cloud status')
                age = value.pop('ack_age_ns')
                value['last_ack_ns'] = time.monotonic_ns()-age if age is not None else None
                with self.lock:
                    self._status = value
            except Exception as error:
                with self.lock:
                    self._status.update(state='retrying', error=type(error).__name__)
                started = False
            self.end.wait(1)
