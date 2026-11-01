"""PC field desk: strict JPG2 stream -> bounded lossless recording and latest preview."""
from pathlib import Path
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, quote
import argparse, hashlib, importlib.util, io, json, os, queue, re, shutil, struct, subprocess, sys, threading, time, uuid
from PIL import Image
from compression1412 import options,board_support
from field_failure1793 import startup_failure

ROOT = Path(__file__).resolve().parent
ART = ROOT.parent/'artifacts'
DATA = Path('E:/FPGA_field_tests')
N = '/userdata/native_required1138_20261028'
SSH = ['ssh.exe', '-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', 'rk3576']
HIDDEN = dict(creationflags=subprocess.CREATE_NO_WINDOW) if os.name == 'nt' else {}
spec = importlib.util.spec_from_file_location('jpg2', ART/'jpeg_stream733_20261026/receive_jpg2.py')
jpg2 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(jpg2)
TOKEN = uuid.uuid4().hex
LOCK = threading.RLock()
STATE = dict(phase='IDLE', message='先检测设备，再开始现场测试', session=None, frames=0,
             preview_frames=0, recording=False, logs=[], recordings=[], telemetry={}, error=None)
LATEST = None
PREVIEW = None
PREVIEW_ID = -1
STOP = threading.Event()
RECORD_WANTED = False
THREAD = None


def log(message):
    with LOCK:
        STATE['logs'] = ([dict(time=datetime.now().strftime('%H:%M:%S'), message=str(message))]+STATE['logs'])[:60]


def ssh_json(code, timeout=20):
    r = subprocess.run(SSH+['python3', '-B', '-'], input=code, text=True, capture_output=True, timeout=timeout, **HIDDEN)
    if r.returncode:
        raise RuntimeError(r.stderr.strip() or r.stdout.strip() or 'SSH failed')
    return json.loads(r.stdout)


def preflight(require_sd=True):
    # APP-owned previews must drain before any PC capture takes the camera.
    stop_app_preview="from pathlib import Path\nimport subprocess,json\np=Path('/userdata/board_cloud/camera_owner.json')\nif p.exists():subprocess.run(['python3','-B','/userdata/board_cloud/board_background.py','--stop-owned'],check=True)\nprint('{}')"
    ssh_json(stop_app_preview,timeout=85)
    code = """from pathlib import Path
import mmap,struct,json,os,subprocess
p=Path('/sys/bus/pci/devices/0000:21:00.0/resource0')
r=dict(ssh=True,endpoint=p.exists(),board_ip='192.168.50.2')
if p.exists():
 with p.open('rb',buffering=0) as f,mmap.mmap(f.fileno(),4096,access=mmap.ACCESS_READ) as m:
  r['registers']={hex(a):struct.unpack_from('<I',m,a)[0] for a in (0x5c,0x60,0x84,0xa4,0x90,0x1cc,0x1c8,0x1d0,0x204)}
r['dma_driver']=Path('/sys/module/anlogic_pci').exists()
r['sd_present']=Path('/dev/mmcblk1p1').exists()
r['sd_mounts']=subprocess.run(['findmnt','-rn','-S','/dev/mmcblk1p1'],capture_output=True,text=True).stdout
r['emmc_free']=os.statvfs('/userdata').f_bavail*os.statvfs('/userdata').f_frsize
print(json.dumps(r))
"""
    result = ssh_json(code)
    DATA.mkdir(exist_ok=True, parents=True)
    result['pc_free'] = shutil.disk_usage(DATA).free
    r = result.get('registers', {})
    result['ready'] = bool(r.get('0x5c') in (0x4a505134,0x4a505399) and r.get('0x84', 0)&9 == 1
                           and r.get('0x60') == r.get('0xa4') == r.get('0x90') == 0
                           and result['dma_driver'] and (result['sd_present'] or not require_sd) and not result['sd_mounts'])
    result['reason'] = ('就绪，可启动单路现场测试' if result['ready'] else
                        'FPGA尚未恢复SRAM，请运行恢复脚本' if not result['endpoint'] else
                        '摄像头初始化失败：检查供电与10cm排线，断电后处理' if r.get('0x84', 0)&9 != 1 else
                        '上次采集未清理：FPGA仍处于捕获/DMA状态，需恢复设备（SRAM）' if any(r.get(k,0) for k in ('0x60','0xa4','0x90')) else
                        'SD仍挂载，等待上次会话完成卸载' if result['sd_mounts'] else
                        'DMA驱动未加载，需恢复设备' if not result['dma_driver'] else
                        'SD卡未识别' if not result['sd_present'] else '设备状态不满足启动条件')
    with LOCK:
        STATE['preflight'] = result
        STATE['message'] = result['reason']
    log(result['reason'])
    return result


class Movie:
    def __init__(self, directory, index, on_error):
        self.path = directory/f'clip_{index:02d}.mkv'
        self.manifest = self.path.with_suffix('.frames.jsonl').open('x', encoding='utf-8')
        self.stderr = self.path.with_suffix('.ffmpeg.log').open('xb')
        self.process = subprocess.Popen(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-nostdin', '-n',
            '-f', 'image2pipe', '-framerate', '60', '-vcodec', 'mjpeg', '-i', 'pipe:0',
            '-map', '0:v:0', '-c:v', 'copy', '-metadata', 'comment=Original FPGA JPEG; rotate180 for upright viewing',
            '-f', 'matroska', str(self.path)], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=self.stderr, **HIDDEN)
        self.q = queue.Queue()
        self.lock = threading.Lock()
        self.pending = 0
        self.peak = 0
        self.count = 0
        self.error = None
        self.on_error = on_error
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def push(self, frame, data, received):
        with self.lock:
            if self.error:
                raise RuntimeError(self.error)
            if self.pending+len(data) > 64*1024**2:
                raise BufferError('PC录像队列超过64MiB，停止会话以避免静默丢帧')
            self.pending += len(data)
            self.peak = max(self.peak, self.pending)
        self.q.put((frame, data, received))

    def run(self):
        try:
            while True:
                item = self.q.get()
                if item is None:
                    break
                frame, data, received = item
                view = memoryview(data)
                while view:
                    written = self.process.stdin.write(view)
                    if not written:
                        raise OSError('ffmpeg input failed')
                    view = view[written:]
                self.manifest.write(json.dumps(dict(frame_id=frame, pc_received_ns=received,
                    jpeg_sha256=hashlib.sha256(data).hexdigest(), bytes=len(data)))+'\n')
                self.count += 1
                with self.lock:
                    self.pending -= len(data)
            self.process.stdin.close()
            if self.process.wait(timeout=30):
                raise RuntimeError('录像封装失败，查看ffmpeg日志')
        except BaseException as e:
            self.error = repr(e)
            self.on_error(self.error)
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait(timeout=5)
        finally:
            self.manifest.flush()
            os.fsync(self.manifest.fileno())
            self.manifest.close()
            self.stderr.close()

    def finish(self):
        self.q.put(None)
        self.thread.join(40)
        if self.thread.is_alive():
            raise TimeoutError('录像收尾超过40秒')
        if self.error:
            raise RuntimeError(self.error)
        with self.path.open('r+b') as f:
            os.fsync(f.fileno())
        return dict(name=self.path.name, frames=self.count, bytes=self.path.stat().st_size,
                    queue_peak_bytes=self.peak, session=self.path.parent.name)


def fault(message):
    with LOCK:
        STATE['error'] = str(message)
    STOP.set()
    log(message)


def stop_watcher(name, end):
    while not end.wait(.2):
        if STOP.is_set():
            try:
                action(name, 'stop')
                return
            except BaseException:
                # The session directory may not exist during early startup.
                continue


def exact(stream, count):
    data = bytearray()
    while len(data) < count:
        block = stream.read(count-len(data))
        if not block:
            if not data:
                return None
            raise EOFError('网络数据包截断')
        data.extend(block)
    return bytes(data)


def preview_worker():
    global PREVIEW, PREVIEW_ID
    while True:
        started = time.monotonic()
        try:
            with LOCK:
                value = LATEST
            if value and value[0] != PREVIEW_ID:
                frame, data = value
                with Image.open(io.BytesIO(data)) as im:
                    im.draft('RGB', (960, 540))
                    im = im.convert('RGB').transpose(Image.Transpose.ROTATE_180)
                    im.thumbnail((960, 540))
                    target = io.BytesIO()
                    im.save(target, 'JPEG', quality=78)
                with LOCK:
                    PREVIEW = target.getvalue()
                    PREVIEW_ID = frame
                    STATE['preview_frames'] += 1
                    STATE['preview_updated_pc_ns'] = time.monotonic_ns()
        except BaseException as e:
            fault('预览解码失败：'+repr(e))
        # Include decode/resize/encode time in the 30 Hz budget. Keep only
        # the latest source frame; preview must never queue behind recording.
        time.sleep(max(.001, 1/30-(time.monotonic()-started)))


def pose_worker(name,directory,end):
    proc=subprocess.Popen(SSH+['python3','-B',N+'/field1382/pose_remote.py','--name',name],
        stdout=subprocess.PIPE,stderr=(directory/'pose_channel.stderr').open('xb'),text=True,**HIDDEN)
    try:
        with (directory/'pose_channel.jsonl').open('x',encoding='utf-8') as journal:
            for line in proc.stdout:
                if end.is_set():break
                row=json.loads(line);row['pc_received_ns']=time.monotonic_ns()
                journal.write(json.dumps(row)+'\n');journal.flush()
                with LOCK:STATE['fast_pose']=row
    except BaseException as error:
        if not end.is_set():log('骨架通道异常：'+repr(error))
    finally:
        if proc.poll() is None:proc.terminate()
        proc.wait(timeout=10)


def telemetry_worker(name, directory, end):
    proc = subprocess.Popen(SSH+['python3', '-B', N+'/field1382/telemetry_remote.py', '--name', name],
                            stdout=subprocess.PIPE, stderr=(directory/'telemetry.stderr').open('xb'), text=True, **HIDDEN)
    previous = None
    try:
        with (directory/'telemetry.jsonl').open('x', encoding='utf-8') as journal:
            for line in proc.stdout:
                if end.is_set():
                    break
                row = json.loads(line)
                row['pc_received_ns'] = time.monotonic_ns()
                journal.write(json.dumps(row, ensure_ascii=False)+'\n')
                journal.flush()
                if previous and row.get('registers') and previous.get('registers'):
                    dt = (row['board_monotonic_ns']-previous['board_monotonic_ns'])/1e9
                    row['source_fps'] = (row['registers']['0x1d8']-previous['registers']['0x1d8'])/dt
                    if row.get('pose') and previous.get('pose'):
                        f = row['pose']['frame_id']-previous['pose']['frame_id']
                        # Actual inference rate comes from the result row count at finalization.
                        row['pose_source_advance_fps'] = f/dt
                previous = row
                with LOCK:
                    STATE['telemetry'] = row
    except BaseException as e:
        if not end.is_set():
            fault('设备状态连接异常：'+repr(e))
    finally:
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=10)


def session(seconds,name,directory,preprocess=0,compression='quality',jpeg_quality=50,target_mbps=36,resource_lease=None,binary_threshold=None,preview_only=False):
    from resource_gate1695 import acquire
    lease=resource_lease or acquire()
    try:
        return _session(seconds,name,directory,preprocess,compression,jpeg_quality,target_mbps,binary_threshold,preview_only)
    finally:
        lease.close()


def _session(seconds, name, directory, preprocess=0,compression='quality',jpeg_quality=50,target_mbps=36,binary_threshold=None,preview_only=False):
    global LATEST, RECORD_WANTED
    control = reader = movie = None
    tel_end = threading.Event()
    completed_movies = []
    report = dict(state='FAILED', session=name, seconds_requested=seconds,preview_only=preview_only)
    count = 0
    wire_bytes = 0
    start = time.monotonic()
    last_frame = None
    first_received = None
    movie_index = 0
    receiver = jpg2.Receiver(max_bytes=1920*1080*6+65536)
    try:
        control = subprocess.Popen(SSH+['python3', '-B', N+'/field1382/'+('preview_remote.py' if preview_only else 'field_remote.py'), '--name', name, '--seconds', str(seconds), '--preprocess', str(preprocess),
                                       '--compression',compression,'--jpeg-quality',str(jpeg_quality),'--target-mbps',str(target_mbps),
                                       *([] if binary_threshold is None else ['--binary-threshold',str(binary_threshold)])],
            stdout=(directory/'remote.stdout').open('xb'), stderr=(directory/'remote.stderr').open('xb'), **HIDDEN)
        threading.Thread(target=stop_watcher, args=(name, tel_end), daemon=True).start()
        tel = threading.Thread(target=telemetry_worker, args=(name, directory, tel_end), daemon=True)
        tel.start()
        if not preview_only:threading.Thread(target=pose_worker,args=(name,directory,tel_end),daemon=True).start()
        deadline = time.monotonic()+160
        while time.monotonic() < deadline:
            if control.poll() is not None:
                raise RuntimeError('板端启动失败：'+startup_failure(
                    (directory/'remote.stdout').read_text(errors='replace'),
                    (directory/'remote.stderr').read_text(errors='replace')))
            ready = ssh_json("from pathlib import Path\nimport json\nprint(json.dumps(Path("+repr(N+'/evidence/'+name+'/stream_ready.json')+").exists()))")
            if ready:
                break
            time.sleep(.4)
        else:
            raise TimeoutError('等待板端数据流超时')
        reader = subprocess.Popen(SSH+['python3', '-B', N+'/wire_reader1551.py', '--directory', N+'/evidence/'+name],
            stdout=subprocess.PIPE, stderr=(directory/'wire.stderr').open('xb'), **HIDDEN)
        from process_guard1740 import guard_reader
        guard_reader(control,reader,tel_end)
        log('预览已开启；不录像、不进行检测' if preview_only else '链路就绪：SD循环录像、NPU及PC串流并发启动；HDMI未启用')
        with LOCK:
            STATE['phase'] = 'STOPPING' if STOP.is_set() else 'RUNNING'
        with (directory/'source.frames.jsonl').open('x', encoding='utf-8') as journal:
            while True:
                head = exact(reader.stdout, 4)
                if head is None:
                    break
                size = struct.unpack('<I', head)[0]
                if not (64 <= size <= 4144 and size%16 == 0):
                    raise ValueError('非法JPG2包长')
                packet = exact(reader.stdout, size)
                if packet is None:
                    raise EOFError('缺少包体')
                wire_bytes += size+4
                image = receiver.accept(packet)
                if receiver.aborts:
                    raise RuntimeError('源JPEG中止，不继续伪装录像正常')
                if image is None:
                    continue
                row = receiver.commits.pop()
                frame = row['frame']
                if last_frame is not None and frame != last_frame+1:
                    raise ValueError('源帧序列有缺口')
                if (row['width'], row['height']) != (1920, 1080):
                    raise ValueError('图像尺寸变化')
                last_frame = frame
                count += 1
                received = time.monotonic_ns()
                if first_received is None:
                    first_received = received
                journal.write(json.dumps(dict(frame_id=frame, pc_received_ns=received, bytes=len(image), jpeg_sha256=hashlib.sha256(image).hexdigest()))+'\n')
                with LOCK:
                    LATEST = (frame, image)
                    wanted = RECORD_WANTED and not preview_only
                    STATE.update(frames=count, latest_frame=frame, wire_bytes=wire_bytes, elapsed_s=(received-first_received)/1e9,
                                 received_pc_ns=received)
                if wanted and movie is None:
                    movie_index += 1
                    movie = Movie(directory, movie_index, fault)
                    log('开始PC原始画面录像 '+movie.path.name)
                if movie is not None and not wanted:
                    saved = movie.finish()
                    completed_movies.append(saved)
                    movie = None
                    log('录像已封装，可下载或回放')
                if movie is not None:
                    movie.push(frame, image, received)
                with LOCK:
                    STATE['recording'] = movie is not None
                    STATE['recorded_frames'] = sum(m['frames'] for m in completed_movies)+(movie.count if movie else 0)
                    STATE['recordings'] = list(completed_movies)
                if count%60 == 0 and shutil.disk_usage(directory).free < 2*1024**3:
                    raise OSError('PC剩余空间不足2GiB，停止测试')
            if receiver.pending is not None:
                raise EOFError('流结束于未提交JPEG')
        if reader.wait(timeout=20):
            raise RuntimeError('PC串流SSH异常退出')
        with LOCK:
            STATE['phase'] = 'FINALIZING'
        if control.wait(timeout=100):
            raise RuntimeError('板端运行或收尾失败：'+startup_failure(
                (directory/'remote.stdout').read_text(errors='replace'),
                (directory/'remote.stderr').read_text(errors='replace')))
        remote = ssh_json("from pathlib import Path\nimport json\nprint(Path("+repr(N+'/field1382/'+name+'/report.json')+").read_text())")
        assert remote['state'] == 'FIELD_SESSION_FINISHED' and remote['native']['committed'] == count
        report.update(state='FIELD_PC_SESSION_PASS', frames=count, remote=remote)
    except BaseException as e:
        report['error'] = repr(e)
        fault(str(e))
        try:
            action(name, 'stop')
        except BaseException as cleanup:
            report['stop_error'] = repr(cleanup)
    finally:
        if movie is not None:
            try:
                completed_movies.append(movie.finish())
            except BaseException as e:
                report.update(state='FAILED', recording_error=repr(e))
        if control is not None and control.poll() is None:
            try:
                control.wait(timeout=100)
            except subprocess.TimeoutExpired:
                report.update(state='FAILED', cleanup_error='板端未及时结束，须检查驱动恢复')
        if reader is not None and reader.poll() is None:
            reader.terminate()
            reader.wait(timeout=10)
        tel_end.set()
        # A failed PC stream must retain the independent board recovery result.
        # This never promotes a failed/truncated recording to session success.
        if 'remote' not in report:
            try:
                report['remote'] = ssh_json("from pathlib import Path\nimport json\nprint(Path("+repr(N+'/field1382/'+name+'/report.json')+").read_text())")
            except BaseException as e:
                report['recovery_observation_error'] = repr(e)
        try:
            reader_report=ssh_json("from pathlib import Path\nimport json\np=Path("+repr(N+'/evidence/'+name+'/wire_reader.report.json')+")\nprint(p.read_text() if p.exists() else '{}')") if report.get('remote') else {}
        except BaseException:reader_report={}
        if reader_report.get('delivery_error')=='SSH stdout stalled':
            report['error']='PC串流接收连续阻塞超过2秒，板端发送停止；不是SD容量不足。请保留本段并恢复设备，改用目标平均36Mbps后重试。'
            with LOCK:STATE['error']=report['error']
            log(report['error'])
        # Archive all exact model results and source timestamps for offline review.
        archives=[('pose/frames.jsonl', 'pose.frames.jsonl'), ('frame_notices.jsonl', 'source.timestamps.jsonl'), ('session.json', 'board.session.json'), ('pose/alarms.sqlite', 'field.alarms.sqlite'),('compression.frames.jsonl','compression.frames.jsonl'),('compression.latest.json','compression.latest.json'),('wire_reader.report.json','wire_reader.report.json'),('preprocess.frames.jsonl','preprocess.frames.jsonl'),('preprocess.events.jsonl','preprocess.events.jsonl'),('preprocess.latest.json','preprocess.latest.json')]
        if preview_only:archives=[row for row in archives if not row[0].startswith('pose/')]
        for suffix, dest in archives:
            r = subprocess.run(['scp.exe', 'rk3576:'+N+'/evidence/'+name+'/'+suffix, str(directory/dest)], capture_output=True, timeout=45, **HIDDEN)
            if r.returncode:
                report.setdefault('archive_errors', []).append(suffix)
        if report.get('archive_errors'):
            report['state'] = 'FAILED'
        # Cloud evidence is independent of the capture acceptance result.
        cloud_config=ROOT/'cloud1694.local.json'
        if not preview_only and cloud_config.is_file():
            try:
                if json.loads(cloud_config.read_text(encoding='utf-8-sig')).get('transport')=='board':
                    available=ssh_json("from pathlib import Path\nimport json\nprint(json.dumps(Path("+repr(N+'/evidence/'+name+'/cloud')+").is_dir()))")
                    if available:
                        copied=subprocess.run(['scp.exe','-r','rk3576:'+N+'/evidence/'+name+'/cloud',str(directory/'cloud')],capture_output=True,timeout=30,**HIDDEN)
                        if copied.returncode:raise RuntimeError('cloud journal copy failed')
                        report['cloud_transport']='board'
            except Exception as error:
                report['cloud_archive_error']=type(error).__name__
        report.update(recordings=completed_movies, frames=count, wire_bytes=wire_bytes, elapsed_s=time.monotonic()-start,
                      source_complete=report['state']=='FIELD_PC_SESSION_PASS',
                      unfinished_jpeg=receiver.pending is not None)
        (directory/'report.json').write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding='utf-8')
        with LOCK:
            STATE.update(phase='DONE' if report['state']=='FIELD_PC_SESSION_PASS' else 'ERROR', recording=False,
                         recordings=completed_movies, recorded_frames=sum(m['frames'] for m in completed_movies), report=report, message=('预览已关闭' if preview_only else '会话完成，录像和检测日志已保存') if report['state']=='FIELD_PC_SESSION_PASS' else '会话未通过，查看日志')
        log(STATE['message'])


def action(name, verb, incident=None, reason=''):
    assert re.fullmatch(r'field_[0-9_]+', name)
    cmd = SSH+['python3', '-B', N+'/field1382/telemetry_remote.py', '--name', name, '--action', verb]
    # JSON stdin code avoids shell quoting user-entered reasons.
    if verb in ('ack', 'resolve'):
        return ssh_json("import sys,runpy\nsys.argv="+repr(['telemetry_remote.py', '--name', name, '--action', verb, '--incident', str(int(incident)), '--reason', reason])+"\nrunpy.run_path("+repr(N+'/field1382/telemetry_remote.py')+",run_name='__main__')")
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=20, **HIDDEN)
    result.check_returncode()
    return json.loads(result.stdout)


def set_preprocess(mode):
    if type(mode) is not int or mode not in range(4):raise ValueError('不支持的预处理模式')
    with LOCK:
        if STATE['phase']!='RUNNING':raise ValueError('先开始测试再切换模式')
        if STATE.get('preprocess_sending'):raise ValueError('切换请求正在发送')
        previous=STATE.get('preprocess_request')
        latest=STATE.get('telemetry',{}).get('preprocess',{})
        if previous and not (latest.get('request_id')==previous['request_id'] and latest.get('phase')=='applied'):
            raise ValueError('上一次切换尚未确认')
        name=STATE['session'];STATE['preprocess_sending']=True
    key=uuid.uuid4().hex
    try:
        code="""from pathlib import Path
import json,os,time
base=Path(BASE)
output=Path(OUTPUT)
assert base.is_dir() and not (base/'report.json').exists(),'会话已经结束'
latest=json.loads((output/'preprocess.latest.json').read_text())
assert latest.get('supported'),'当前FPGA不支持运行中切换'
assert latest['phase'] in ('idle','applied'),'上一次切换尚未完成'
assert 0<=time.monotonic_ns()-latest['board_monotonic_ns']<3_000_000_000,'预处理状态已过期'
path=base/'preprocess.request.json'
if path.exists():
 previous=json.loads(path.read_text())
 assert previous['request_id']==latest.get('request_id'),'切换请求正在排队'
value=VALUE
temporary=base/('preprocess.'+value['request_id']+'.tmp')
with temporary.open('x') as f:json.dump(value,f)
os.replace(temporary,path)
print(json.dumps(value))
""".replace('BASE',repr(N+'/field1382/'+name)).replace('OUTPUT',repr(N+'/evidence/'+name)).replace('VALUE',repr(dict(request_id=key,mode=mode)))
        result=ssh_json(code)
        with LOCK:STATE['preprocess_request']=result
        log('请求切换预处理：'+('彩色原图','灰度','高斯滤波','直方图均衡')[mode])
        return result
    finally:
        with LOCK:STATE['preprocess_sending']=False


def request_stop():
    STOP.set()
    with LOCK:
        name = STATE['session']
        if STATE['phase'] in ('STARTING', 'RUNNING'):
            STATE['phase'] = 'STOPPING'
    if name:
        action(name, 'stop')
        log('请求停止：等待帧排空与设备恢复')


def start(values):
    global THREAD, RECORD_WANTED, LATEST, PREVIEW, PREVIEW_ID
    preview_only=values.get('purpose')=='preview'
    seconds = int(values.get('seconds',600 if preview_only else 60))
    if preview_only and not 10<=seconds<=600:raise ValueError('独立预览最长10分钟')
    preprocess = int(values.get('preprocess', 0))
    compression_config=options(values.get('compression','quality'),values.get('jpeg_quality',50),values.get('target_mbps',36))
    from threshold1786 import options as threshold_options
    binary_threshold=values.get('binary_threshold')
    advanced_config=threshold_options(binary_threshold)
    if preprocess not in (0, 1, 2, 3):
        raise ValueError('Unsupported FPGA preprocessing mode')
    if not preview_only and seconds not in (0,10,30,60,180,300,600,1800,3600,7200):
        raise ValueError('请选择有效测试时长或手动停止模式')
    with LOCK:
        if STATE.get('offline_busy'):
            raise ValueError('RK离线复盘正在运行，请等待结束后再开始实时测试')
        if THREAD is not None and THREAD.is_alive():
            raise ValueError('已有会话运行，请先停止并等待收尾')
        # Hold the start lock across preflight so simultaneous API starts cannot race.
        probe = preflight() if not preview_only else preflight(require_sd=False)
        if not probe['ready']:
            raise ValueError(probe['reason'])
        board_support(probe.get('registers',{}).get('0x5c',0x4a505134),compression_config)
        # Manual sessions still retain the tested native two-hour safety bound.
        # Open-ended operation cannot reserve an unknown total. Require one minute
        # of headroom, then use the existing live 2GiB stop threshold.
        budget_seconds=seconds or 60
        required=budget_seconds*35*1024**2+2*1024**3 if values.get('record',True) and not preview_only else 2*1024**3
        if probe['pc_free'] < required:
            raise OSError(f'PC空间不足：开启录像按35MiB/s预留，所选模式需约{required/1024**3:.1f}GiB；请缩短时长或关闭PC录像')
        name = 'field_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f')
        parent=ART/'camera_previews' if preview_only else DATA
        parent.mkdir(exist_ok=True)
        directory = parent/name
        directory.mkdir()
        STOP.clear()
        RECORD_WANTED = bool(values.get('record', True)) and not preview_only
        LATEST = PREVIEW = None
        PREVIEW_ID = -1
        STATE.update(phase='STARTING',purpose='preview' if preview_only else 'test', session=name, frames=0, recorded_frames=0, preview_frames=0, recordings=[], error=None,
                       telemetry={}, fast_pose={},preprocess_request=None,preprocess_sending=False, seconds=seconds, preprocess=preprocess,
                       advanced_config=advanced_config,compression_config=compression_config, message='正在启动并发链路', started_pc_ns=time.monotonic_ns())
        STATE.pop('report', None)
        for key in ('received_pc_ns', 'preview_updated_pc_ns'):
            STATE.pop(key, None)
        (directory/'metadata.json').write_text(json.dumps(dict(**values, name=name, created=datetime.now().isoformat(), original_orientation='sensor JPEG; upright preview rotated180', recording='MJPEG Matroska stream copy; nominal60fps; see source timestamps'), ensure_ascii=False, indent=2), encoding='utf-8')
        from resource_gate1695 import acquire
        try:
            lease=acquire()
            THREAD = threading.Thread(target=session, args=(seconds, name, directory, preprocess,compression_config['compression'],compression_config['jpeg_quality'],compression_config['target_mbps']),kwargs=dict(resource_lease=lease,binary_threshold=binary_threshold,preview_only=preview_only),daemon=True)
            THREAD.start()
        except BaseException:
            if 'lease' in locals():lease.close()
            STATE.update(phase='ERROR',error='RK正被其他任务使用，或会话线程未能启动')
            raise
    log('新现场会话 '+name)
    return dict(session=name)


def safe_file(query):
    name = query.get('session', [''])[0]
    file = query.get('file', [''])[0]
    if not re.fullmatch(r'field_[0-9_]+', name) or not re.fullmatch(r'[A-Za-z0-9_.-]+', file):
        raise ValueError('非法文件路径')
    p = DATA/name/file
    if not p.is_file() or p.is_symlink():
        raise FileNotFoundError(file)
    return p


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send(self, body, mime='application/json; charset=utf-8', status=200):
        self.send_response(status)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        try:
            if parsed.path == '/':
                return self.send((ROOT/'index.html').read_text(encoding='utf-8').replace('__TOKEN__', TOKEN).encode(), 'text/html; charset=utf-8')
            if parsed.path == '/api/status':
                with LOCK:
                    status = dict(STATE, now_pc_ns=time.monotonic_ns(), pc_free=shutil.disk_usage(DATA).free)
                return self.send(json.dumps(status, ensure_ascii=False).encode())
            if parsed.path == '/api/history':
                rows = []
                for p in sorted(DATA.glob('field_*/report.json'), reverse=True)[:40]:
                    r = json.loads(p.read_text(encoding='utf-8'))
                    rows.append(dict(session=p.parent.name, state=r['state'], frames=r.get('frames'), recordings=r.get('recordings', [])))
                return self.send(json.dumps(rows).encode())
            if parsed.path in ('/preview.jpg', '/snapshot.jpg'):
                with LOCK:
                    data = PREVIEW if parsed.path == '/preview.jpg' else (LATEST[1] if LATEST else None)
                if data is None:
                    return self.send(b'No live frame', 'text/plain', 503)
                if parsed.path == '/snapshot.jpg':
                    self.send_response(200)
                    self.send_header('Content-Type', 'image/jpeg')
                    self.send_header('Content-Disposition', 'attachment; filename=sensor_source.jpg')
                    self.send_header('Content-Length', str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                    return
                return self.send(data, 'image/jpeg')
            if parsed.path == '/file':
                p = safe_file(parse_qs(parsed.query))
                self.send_response(200)
                self.send_header('Content-Type', 'application/octet-stream')
                self.send_header('Content-Disposition', 'attachment; filename="'+p.name+'"')
                self.send_header('Content-Length', str(p.stat().st_size))
                self.end_headers()
                with p.open('rb') as f:
                    while data := f.read(1024**2):
                        self.wfile.write(data)
                return
            if parsed.path == '/replay.mjpg':
                p = safe_file(parse_qs(parsed.query))
                if p.suffix != '.mkv':
                    raise ValueError('只能回放完整MKV文件')
                self.send_response(200)
                self.send_header('Content-Type', 'multipart/x-mixed-replace; boundary=frame')
                self.end_headers()
                proc = subprocess.Popen(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-re', '-i', str(p),
                    '-vf', 'hflip,vflip,scale=960:540', '-r', '10', '-q:v', '5', '-f', 'image2pipe', '-vcodec', 'mjpeg', 'pipe:1'],
                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, **HIDDEN)
                try:
                    buf = bytearray()
                    while data := proc.stdout.read(16384):
                        buf.extend(data)
                        while True:
                            end = buf.find(b'\xff\xd9')
                            if end < 0:
                                break
                            frame = bytes(buf[:end+2])
                            del buf[:end+2]
                            self.wfile.write(b'--frame\r\nContent-Type: image/jpeg\r\nContent-Length: '+str(len(frame)).encode()+b'\r\n\r\n'+frame+b'\r\n')
                finally:
                    if proc.poll() is None:
                        proc.terminate()
                    proc.wait(timeout=10)
                return
            self.send(b'Not found', 'text/plain', 404)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass
        except BaseException as e:
            self.send(json.dumps(dict(error=str(e)), ensure_ascii=False).encode(), status=400)

    def do_POST(self):
        global RECORD_WANTED
        try:
            if self.headers.get('X-Field-Token') != TOKEN:
                return self.send(b'{"error":"invalid token"}', status=403)
            origin = self.headers.get('Origin')
            if origin and urlparse(origin).netloc != self.headers.get('Host'):
                return self.send(b'{"error":"origin mismatch"}', status=403)
            length = int(self.headers.get('Content-Length', 0))
            if not 0 <= length <= 8192:
                raise ValueError('请求过大')
            values = json.loads(self.rfile.read(length) or b'{}')
            path = urlparse(self.path).path
            if path == '/api/preflight':
                result = preflight()
            elif path == '/api/start':
                result = start(values)
            elif path == '/api/stop':
                request_stop()
                result = dict(stopping=True)
            elif path == '/api/preprocess':
                result = set_preprocess(values['mode'])
            elif path == '/api/record':
                with LOCK:
                    if STATE['phase'] != 'RUNNING':
                        raise ValueError('先启动会话再切换录像')
                    RECORD_WANTED = bool(values['enabled'])
                result = dict(recording_requested=RECORD_WANTED)
            elif path == '/api/label':
                label = str(values['label']).strip()[:200]
                with LOCK:
                    name, frame = STATE['session'], STATE.get('latest_frame')
                if not name or not label:
                    raise ValueError('先选择会话并填写标签')
                row = dict(pc_time=datetime.now().isoformat(), pc_ns=time.monotonic_ns(), source_frame_id=frame, label=label)
                with (DATA/name/'labels.jsonl').open('a', encoding='utf-8') as f:
                    f.write(json.dumps(row, ensure_ascii=False)+'\n')
                    f.flush()
                log('动作标记：'+label)
                result = row
            elif path in ('/api/ack', '/api/resolve'):
                result = action(STATE['session'], path.rsplit('/', 1)[1], values['incident'], str(values['reason'])[:300])
                log('操作员处理事件：'+path.rsplit('/', 1)[1])
            else:
                raise ValueError('未知操作')
            self.send(json.dumps(result, ensure_ascii=False).encode())
        except BaseException as e:
            self.send(json.dumps(dict(error=str(e)), ensure_ascii=False).encode(), status=400)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--host', default='192.168.50.1')
    ap.add_argument('--port', type=int, default=8080)
    args = ap.parse_args()
    DATA.mkdir(exist_ok=True, parents=True)
    if not shutil.which('ffmpeg'):
        raise SystemExit('ffmpeg not found')
    threading.Thread(target=preview_worker, daemon=True).start()
    print(f'Field desk http://{args.host}:{args.port}', flush=True)
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    try:
        server.serve_forever()
    finally:
        if THREAD is not None and THREAD.is_alive():
            request_stop()
            THREAD.join(120)
