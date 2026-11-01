from long_journal1295 import RowJournal,journal_json
from session_config_field1382 import plan,validate_directories
"""Bounded board1018 JPG2 trial with original-driver restoration on every exit.

Use only after independent physical/download gates. Geometry and delay are
explicit arguments from sensor observations, never inherited from board727.
"""
import signal
from threshold1786 import options as threshold_options,control_word
from compression1412 import options,board_support
from compression1564 import Observer
from compression1608 import Observer as MetadataObserver
from preprocess_runtime1520 import RuntimeModes,source_verdict_reason
import ctypes,argparse,fcntl,hashlib,json,mmap,os,select,struct,subprocess,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parent
RESOURCE=Path('/sys/bus/pci/devices/0000:21:00.0/resource0')
SHARED_BYTES=4*(1920*1080*6+65536+64)
OFFSETS=(0x5c,0x60,0x54,0x84,0x90,0xa4,0xb8,0xc0,0xcc,0xd0,0x104,0x108,0x10c,0x134,0x138,0x13c,*range(0x1c0,0x1f8,4))
# BAR写入统一经带屏障的本地MMIO函数，避免直接Python写入的可见性问题。
class Bar:
    def __init__(self):
        self.fd=os.open(RESOURCE,os.O_RDWR|os.O_SYNC)
        self.m=mmap.mmap(self.fd,4096,access=mmap.ACCESS_WRITE)
        self._anchor=ctypes.c_uint8.from_buffer(self.m)
        self._base=ctypes.addressof(self._anchor)
        self._io=ctypes.CDLL('/userdata/mmio1056_20261028/mmio1056.so')
        self._io.mmio1056_write32.argtypes=(ctypes.c_void_p,ctypes.c_uint32,ctypes.c_uint32)
        self._io.mmio1056_write32.restype=ctypes.c_int
    def read(self,a):return struct.unpack_from('<I',self.m,a)[0]
    def write(self,a,v):
        if not (0<=a<=4092 and a%4==0 and 0<=v<=0xffffffff):raise ValueError('Unaligned/out-of-range MMIO write')
        if self._io.mmio1056_write32(self._base,a,v):raise RuntimeError('MMIO write rejected')
    def close(self):
        del self._anchor
        self.m.close();os.close(self.fd)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def snap(b):return {hex(a):b.read(a) for a in OFFSETS}

def decode_fault(registers):
    if registers['0x5c'] not in (0x4a505134,0x4a505399):
        raise ValueError('Fault layout requires board976')
    code,occ,peak = (registers[hex(a)] for a in (0x134,0x138,0x13c))
    return dict(**source_verdict_reason(code),cause_bits=code&511,group_index=code>>13,
                input_groups=occ&32767,output_words=(occ>>15)&255,queued=(occ>>23)&15,
                input_peak=peak&32767,output_peak=(peak>>15)&255)
def identity(b):
    version=b.read(0x5c)
    if version not in (0x4a505134,0x4a505399):raise RuntimeError('Unknown FPGA profile')
    expected={0x1c0:0x3247504a,0x1c4:0x10000,0x1c8:15 if version==0x4a505134 else 31,0x1ec:1,0x1f0:1}
    for a,value in expected.items():
        if b.read(a)!=value:raise RuntimeError('JPG2 capability mismatch')
    if (version==0x4a505134 and b.read(0x1d0)!=50) or not 1<=b.read(0x1d0)<=100:
        raise RuntimeError('Unexpected JPEG quality')

def wait(b,a,value,mask=0xffffffff,timeout=5):
    deadline=time.monotonic()+timeout
    while b.read(a)&mask!=value:
        if time.monotonic()>=deadline:raise TimeoutError(f'{a:#x}: {b.read(a):#x}, expected {value:#x}')
        time.sleep(.001)
def idle(b):
    identity(b)
    if b.read(0x60) or b.read(0xa4) or b.read(0x90) or (b.read(0x1cc)&7):
        raise RuntimeError('JPG2 transport is not idle')
    if b.read(0x84)&9!=1:raise RuntimeError('Camera I2C not ready or bus error')
def unoccupied(require_devices=True):
    paths=[str(p) for pattern in ('ANLOGIC-PCI0_*','video*') for p in Path('/dev').glob(pattern)]
    if not paths:
        if require_devices:raise RuntimeError('No board devices')
        return
    r=subprocess.run(['fuser',*paths],capture_output=True,text=True,timeout=5)
    if not paths or r.returncode!=1 or r.stdout.strip():raise RuntimeError('Board devices occupied or fuser failed')
def line(p,timeout=10,tick=None):
    deadline=time.monotonic()+timeout;data=bytearray()
    while len(data)<4096:
        if tick is not None:tick()
        remaining=deadline-time.monotonic()
        if remaining<=0:raise TimeoutError('Native notice timeout')
        if not select.select([p.stdout],[],[],min(.05,remaining) if tick is not None else remaining)[0]:
            if tick is not None:continue
            raise TimeoutError('Native notice timeout')
        c=os.read(p.stdout.fileno(),1)
        if not c:raise RuntimeError(f'Native process exited {p.poll()}')
        if c==b'\n':return data.decode('ascii')
        data.extend(c)
    raise ValueError('Native notice exceeds limit')
def send(p,c):p.stdin.write(c);p.stdin.flush()
def armed(p):
    with RESOURCE.with_name('resource1').open('rb',buffering=0) as f,mmap.mmap(f.fileno(),8192,access=mmap.ACCESS_READ) as mm:
        if struct.unpack_from('<I',mm,0x1000)[0]>>16!=0x1fc1:raise RuntimeError('DMA channel identity mismatch')
        deadline=time.monotonic()+2
        while p.poll() is None and time.monotonic()<deadline:
            status=struct.unpack_from('<I',mm,0x1040)[0]
            if status&1:return status
            time.sleep(.001)
    raise TimeoutError('DMA channel failed to arm')
def restore_drivers(recovery,ring_id,params,video_loaded,vp,changed,module_exists=None):
    if module_exists is None:module_exists=lambda name:Path('/sys/module',name).exists()
    # A failed temporary insmod can leave zero device nodes. That must not
    # prevent restoring the already-unloaded original module.
    unoccupied(require_devices=False)
    if changed:
        if module_exists('anlogic_pci'):
            current=recovery.module_id()
            if current not in (ring_id,recovery.DMA_ID):raise RuntimeError('Unexpected driver during recovery')
            if current==ring_id:recovery.run(['rmmod','anlogic_pci'])
        if not module_exists('anlogic_pci'):
            recovery.run(['insmod',str(recovery.DMA),*[f'{k}={v}' for k,v in params.items()]])
    if video_loaded and not module_exists('milianke_v4l2'):
        recovery.run(['insmod',str(recovery.VIDEO),*[f'{k}={v}' for k,v in vp.items()]])
    if recovery.module_id()!=recovery.DMA_ID or recovery.parameters('anlogic_pci')!=params:
        raise RuntimeError('DMA driver restoration differs')
    if module_exists('milianke_v4l2')!=video_loaded or recovery.parameters('milianke_v4l2')!=vp:
        raise RuntimeError('Video driver restoration differs')

def request_stop1025(b,p,state):
    state['stop_request_host_ns']=time.monotonic_ns()
    state['at_target']=snap(b)
    b.write(0x1f4,1);wait(b,0x1f4,1,1)
    send(p,b'Q')

def stop_source1025(b,p,state,notice):
    if notice=='QUIESCED':
        wait(b,0x1f4,7,7);wait(b,0x1cc,1,7)
        if any(b.read(x) for x in (0x1dc,0x1e0,0xc0)) or b.read(0x1e4)!=state['denied_baseline']:
            raise RuntimeError('Quiesced source still has abort/fault/drop/denied errors')
        if b.read(0x1d4)!=b.read(0x1d8):raise RuntimeError('Quiesced source terminal counts differ')
    elif notice=='FAULT':
        state['hardware_fault_before_drain']=snap(b)
        try:
            state['source_raster_at_fault']={hex(x):b.read(x) for x in range(0x140,0x164,4)}
            import read_diag902
            read_diag902.VERSION=b.read(0x5c)
            state['source_byte_snapshot_at_fault']=read_diag902.collect(b.read,b.write)
        except BaseException as error:state['source_snapshot_error']=repr(error)
    else:raise RuntimeError('Not an authorized source-stop notice')
    state['before_stop_notice']=notice
    state['before_stop_host_ns']=time.monotonic_ns();state['before_stop']=snap(b)
    b.write(0x60,0);wait(b,0x60,0)
    state['after_camera_off_host_ns']=time.monotonic_ns();state['after_camera_off']=snap(b)
    send(p,b'D')

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--name',required=True)
    ap.add_argument('--frames',required=True,type=int,choices=range(2,432001))
    ap.add_argument('--beats',required=True,type=int,choices=range(481,1025))
    ap.add_argument('--lines',required=True,type=int,choices=range(1080,2301))
    ap.add_argument('--bayer-phase',type=int,choices=range(4),required=True)
    ap.add_argument('--preprocess',type=int,choices=range(4),default=0)
    ap.add_argument('--compression',choices=('quality','target'),default='quality')
    ap.add_argument('--jpeg-quality',type=int,choices=(25,50,75),default=50)
    ap.add_argument('--target-mbps',type=float,default=36)
    ap.add_argument('--binary-threshold',type=int,choices=range(256))
    ap.add_argument('--recordings',required=True)
    ap.add_argument('--headless',action='store_true')
    ap.add_argument('--preview-only',action='store_true')
    ap.add_argument('--preflight-only',action='store_true')
    ap.add_argument('--delay',required=True,type=int,choices=range(64));a=ap.parse_args()
    def interrupted(sig,frame):raise SystemExit('signal '+str(sig))
    for sig in (signal.SIGTERM,signal.SIGHUP):signal.signal(sig,interrupted)
    config=plan(a.name,a.frames,a.recordings)
    advanced_config=threshold_options(a.binary_threshold)
    # Binding is created by staging, before any run, and covers native code,
    # original rollback modules and the tested temporary ring driver.
    with RESOURCE.open('rb',buffering=0) as fd,mmap.mmap(fd.fileno(),4096,access=mmap.ACCESS_READ) as view:
        version=struct.unpack_from('<I',view,0x5c)[0]
    compression=options(a.compression,a.jpeg_quality,a.target_mbps)
    board_support(version,compression)
    binding=json.loads((ROOT/('binding_quality1412.json' if version==0x4a505399 else 'binding_field1382.json')).read_text())
    for p,h in binding['files'].items():
        if sha(p)!=h:raise RuntimeError('Runtime binding changed: '+p)
    sys.path.insert(0,'/home/anmi/board_crop727_20261025_v1/recovery727_v2')
    import recover727 as recovery
    if recovery.module_id()!=recovery.DMA_ID:raise RuntimeError('Original DMA driver not loaded')
    for p,h in recovery.HASHES.items():
        if sha(p)!=h:raise RuntimeError('Original driver hash changed')
    ring=Path(binding['ring_driver']);ring_id=binding['ring_build_id']
    for device in ('0000:20:00.0','0000:21:00.0'):
        if Path('/sys/bus/pci/devices',device,'current_link_speed').read_text().strip()!='5.0 GT/s PCIe':
            raise RuntimeError('Expected Gen2 PCIe link')
    if a.preview_only:
        if not a.headless or a.frames>36000:raise ValueError('Preview requires headless mode and at most ten minutes')
        output=ROOT/'evidence'/a.name
        if output.exists() or output.parent.is_symlink():raise ValueError('Preview output already exists or is unsafe')
        if os.statvfs(output.parent).f_bavail*os.statvfs(output.parent).f_frsize<1024**3:raise OSError('Insufficient evidence space')
        config=dict(**config,output=str(output),preview_only=True)
    else:config=validate_directories(config,ROOT/'evidence')
    if a.preflight_only:
        print(json.dumps(config,indent=2));return
    output=Path(config['output']);output.mkdir(exist_ok=False)
    os.mkfifo(output/'wire.fifo',0o600)
    os.mkfifo(output/'record.fifo',0o600)
    if not a.headless:os.mkfifo(output/'video.fifo',0o600)
    (output/'stream_ready.json').open('x').write(json.dumps(dict(fifo=str(output/'wire.fifo'),max_wire_bytes=70*1024**3)))
    if os.statvfs('/dev/shm').f_bavail*os.statvfs('/dev/shm').f_frsize<SHARED_BYTES:raise RuntimeError('Insufficient shared memory')
    unoccupied();b=Bar();p=None;original=None;changed=False
    shared=Path('/dev/shm')/f'jpg2_841_{os.getpid()}'
    params=recovery.parameters('anlogic_pci');video_loaded=Path('/sys/module/milianke_v4l2').exists();vp=recovery.parameters('milianke_v4l2')
    observer=None
    runtime_modes=None
    workers={};video=None;video_dir=output/"video1008"
    state=dict(bayer_phase=a.bayer_phase,preprocess_mode=a.preprocess,state='FAILED',driver_restored=False,cleanup_verified=False,physical_camera60fps_verified=False)
    state['runtime_config']=config
    state['hdmi_enabled']=not a.headless
    state['preview_only']=a.preview_only
    try:
        idle(b);wait(b,0x1f4,0);state['before']=snap(b);denied_before=b.read(0x1e4);state['denied_baseline']=denied_before
        original={x:b.read(x) for x in (0x54,0xb8,0xcc,0x104,0x108)}
        for addr,value in ((0x54,a.delay),(0xb8,0),(0xcc,control_word(a.preprocess,a.bayer_phase,a.binary_threshold)),(0x104,a.beats),(0x108,a.lines)):
            b.write(addr,value);wait(b,addr,value)
        b.write(0xa4,1);wait(b,0xa4,1);wait(b,0x1cc,1,7)
        if any(b.read(x) for x in (0x1d4,0x1d8,0x1dc,0x1e0)):raise RuntimeError('Session counters not reset')
        if version==0x4a505399:
            b.write(0xc4,a.jpeg_quality);wait(b,0x1d0,a.jpeg_quality)
        state['advanced_config']=advanced_config
        state['compression_config']=compression
        state['prepared']=snap(b)
        if video_loaded:recovery.run(['rmmod','milianke_v4l2'])
        recovery.run(['rmmod','anlogic_pci']);changed=True
        args={**params,'lossless709_ring_mode':'1','jpg2_denied_baseline':str(denied_before)}
        recovery.run(['insmod',str(ring),*[f'{k}={v}' for k,v in args.items()]])
        if recovery.module_id()!=ring_id:raise RuntimeError('Ring driver build ID mismatch')
        fd=os.open(shared,os.O_RDWR|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600);os.ftruncate(fd,SHARED_BYTES);os.close(fd)
        generation=int(time.monotonic_ns()&0xffffffff);state['generation']=generation
        with (output/'native.stderr').open('xb') as err,(output/'notices.jsonl').open('x') as journal:
            if not a.headless:
                video=subprocess.Popen(['python3','-B','/userdata/native_required1138_20261028/reliable1326/live_display1332.py',
                    '--shared',str(shared),'--generation',str(generation),'--output',str(video_dir),'--max-seconds',str(config['worker_max_seconds']),'--frame-fifo',str(output/'video.fifo')],
                    stdout=(output/'video.stdout').open('xb'),stderr=(output/'video.stderr').open('xb'))
                video_deadline=time.monotonic()+15
                while not (video_dir/'ready.json').exists():
                    if video.poll() is not None:raise RuntimeError('Video worker failed before readiness')
                    if time.monotonic()>video_deadline:raise TimeoutError('Video readiness timeout')
                    time.sleep(.01)
                state['video_ready']=json.loads((video_dir/'ready.json').read_text())
            for kind in (() if a.preview_only else ('pose','sd') if a.headless else ('pose','overlay','sd')):
                directory=output/kind
                cmd=['python3','-B',str(ROOT/('live_pose1420.py' if kind=='pose' else 'live_overlay1301.py' if kind=='overlay' else 'live_record1781.py')),
                     '--shared',str(shared),'--generation',str(generation),'--output',str(directory),'--session',a.name,'--max-seconds',str(config['worker_max_seconds'])]
                if kind in ('pose','overlay'):cmd+=['--alarm-db','/userdata/native_required1138_20261028/field1382/alarms.sqlite']
                if kind=='sd':cmd+=['--alarm-db','/userdata/native_required1138_20261028/field1382/alarms.sqlite',
                    '--recordings',config['recordings'],'--frame-fifo',str(output/'record.fifo')]
                worker=subprocess.Popen(cmd,env=dict(os.environ,PYTHONPATH='/home/anmi/offline_demo/python-packages',PYTHONDONTWRITEBYTECODE='1'),stdout=(output/(kind+'.stdout')).open('xb'),stderr=(output/(kind+'.stderr')).open('xb'))
                workers[kind]=(worker,directory)
                deadline_worker=time.monotonic()+(120 if kind=='sd' else 20)
                while not (directory/'ready.json').exists():
                    if worker.poll() is not None:raise RuntimeError(kind+' failed before readiness')
                    if time.monotonic()>deadline_worker:raise TimeoutError(kind+' readiness timeout')
                    time.sleep(.01)
                state[kind+'_ready']=json.loads((directory/'ready.json').read_text())
            # Consumers may preallocate on SD before the strict10s native command window.
            p=subprocess.Popen([str(Path('/userdata/preview_transport_fix_20261031/native/publish_preview') if a.preview_only and version==0x4a505399 else Path('/userdata/feedback1585_20261029/native/publish1585') if version==0x4a505399 else ROOT/'reliable1326/publish1332'),('--stream-dma' if a.preview_only else '--stream-rec-dma' if a.headless else '--stream-av-dma'),'/dev/ANLOGIC-PCI0_c2h_0',str(shared),str(generation),str(a.frames),str(RESOURCE),str(output/'wire.fifo'),str(denied_before),*([str(output/'record.fifo')] if not a.preview_only else []),*([] if a.headless else [str(output/'video.fifo')])],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=err,bufsize=0)
            native_stat=Path('/proc',str(p.pid),'stat').read_text()
            native_identity=dict(pid=p.pid,start_ticks=native_stat.rsplit(')',1)[1].split()[19])
            (output/'native_identity.tmp').open('x').write(json.dumps(native_identity))
            os.replace(output/'native_identity.tmp',output/'native_identity.json')
            ready_notice=line(p);state['native_readiness_notice']=ready_notice
            if ready_notice!='READY':raise RuntimeError('Native receiver failed readiness: '+ready_notice)
            send(p,b'S');state['dma_armed_status']=armed(p)
            state['capture_start_host_ns']=time.monotonic_ns();b.write(0x60,1);wait(b,0x60,1)
            # Observe current source independently of provisional geometry.
            # Consume FRAME notices immediately; delayed diagnostics would overwrite feedback slots.
            state['raw_snapshot_deferred_for_frame_feedback']=True
            wait(b,0xd0,a.bayer_phase<<4,0x30)
            state['raw_raster']={hex(x):b.read(x) for x in range(0x140,0x164,4)}
            deadline=time.monotonic()+config['capture_timeout_seconds'];frames=RowJournal(output/'frame_notices.jsonl');aborts=[];stop=False;quiescing=False
            observer=(MetadataObserver if version==0x4a505399 else Observer)(shared,output,generation,compression)
            runtime_modes=RuntimeModes(b,output,ROOT/'field1382'/a.name,a.preprocess,a.binary_threshold)
            state['consumer_exits']=[]
            def observe_consumers():
                nonlocal quiescing
                if state['consumer_exits']:return
                for kind,worker in [*([('video',video)] if video is not None else []),*[(k,v[0]) for k,v in workers.items()]]:
                    code=worker.poll()
                    if code is not None:
                        state['consumer_exits'].append(dict(consumer=kind,returncode=code,host_ns=time.monotonic_ns(),frames_observed=len(frames)))
                if state['consumer_exits'] and not quiescing:
                    state['stop_reason']='consumer_exit'
                    request_stop1025(b,p,state);quiescing=True
            while time.monotonic()<deadline:
                if not quiescing and (ROOT/'field1382'/a.name/'stop_requested').exists():
                    state['operator_stop']=True;request_stop1025(b,p,state);quiescing=True
                if not quiescing:runtime_modes.poll()
                notice=line(p,tick=observe_consumers);journal.write(json.dumps(dict(host_ns=time.monotonic_ns(),notice=notice))+'\n');journal.flush()
                if notice=='PRESSURE wire' and a.preview_only:
                    state['transport_pressure']=True
                    if not quiescing:
                        state['operator_stop']=True;state['stop_reason']='wire_queue_pressure'
                        request_stop1025(b,p,state);quiescing=True
                elif notice.startswith('FRAME '):
                    frames.append(' '.join(notice.split()[:5]))
                    mode_row=runtime_modes.observe(int(notice.split()[1]))
                    observer.observe(notice,b,mode_row['mode'])
                elif notice.startswith('ABORT '):aborts.append(notice)
                elif notice=='EARLY_STOP' and quiescing and (state['consumer_exits'] or state.get('operator_stop')):
                    state['early_stop_ack_host_ns']=time.monotonic_ns()
                elif notice=='TARGET' and not stop and not quiescing:
                    request_stop1025(b,p,state);quiescing=True
                elif (notice=='QUIESCED' and quiescing and not stop) or (notice=='FAULT' and not stop):
                    stop_source1025(b,p,state,notice);stop=True
                elif notice=='DRAINED' and stop:
                    wait(b,0x1cc,1,7);state['after_drain']=snap(b);send(p,b'T');break
                else:raise RuntimeError('Unexpected receiver notice: '+notice)
            else:raise TimeoutError('Capture deadline exceeded')
            stdout,_=p.communicate(timeout=10);n=json.loads(stdout);state['native']=n
            if p.returncode or n['errno'] or n['aborted'] or (n['committed']<a.frames and not state['consumer_exits'] and not state.get('operator_stop')) or n['published']!=n['committed'] or n['slot_busy_drops']:
                raise RuntimeError('Native receiver rejected stream')
            if len(frames)!=n['committed'] or len(aborts)!=n['aborted']:raise RuntimeError('Notice counts differ')
            if (b.read(0x1d8),b.read(0x1dc),b.read(0x1d4))!=(n['committed'],n['aborted'],n['committed']+n['aborted']):
                raise RuntimeError('Hardware and native terminal counts differ')
            if any(b.read(x) for x in (0x1e0,0xc0)) or b.read(0x1e4)!=denied_before:raise RuntimeError('Hardware fault/drop/denied count nonzero')
        with shared.open('rb') as src,(output/'slots.bin').open('xb') as dest:
            while chunk:=src.read(1024*1024):dest.write(chunk)
        state.update(state=('FAILED' if state['consumer_exits'] else 'LIVE877_JPG2_DMA_PUBLICATION_PENDING_INDEPENDENT_DECODE'),frame_notices=frames,abort_notices=aborts)
        if state['consumer_exits']:state['error']='Consumer exited during capture; early drain completed'
        if state.get('transport_pressure'):
            state.update(state='FAILED',error='PC预览发送队列接近上限，已提前停止并排空；请检查串流处理与网络负载')
    except BaseException as e:
        state['error']=repr(e);state['fault_registers']=snap(b)
        from source_fault_diagnostics import capture
        capture(state,b)
    finally:
        if runtime_modes is not None:
            try:
                runtime_modes.close();state['runtime_preprocess']=runtime_modes.latest
            except BaseException as error:
                state.update(state='FAILED',error='Preprocess journal finalization: '+repr(error))
        if observer is not None:observer.close()
        try:
            # Guard against modifying an unexpected replacement board during cleanup.
            identity(b)
            if original is not None:
                b.write(0x60,0);wait(b,0x60,0)
            if p is not None and p.poll() is None:
                p.terminate();p.wait(timeout=5)
            if original is not None:
                wait(b,0x1cc,0,2)
                if b.read(0xa4):b.write(0xa4,0);wait(b,0xa4,0);wait(b,0x1cc,0,7)
                for addr,value in original.items():b.write(addr,value);wait(b,addr,value)
                if version==0x4a505399:b.write(0xc4,50);wait(b,0x1d0,50)
                idle(b)
            state['cleanup_verified']=True
        except BaseException as e:state.update(cleanup_error=repr(e),state='FAILED')
        try:
            for worker,directory in workers.values():
                if directory.exists():(directory/'stop').touch(exist_ok=False)
            for kind,(worker,directory) in workers.items():
                try:worker.wait(timeout=60)
                except subprocess.TimeoutExpired:
                    worker.terminate();worker.wait(timeout=10)
                state[kind+'_returncode']=worker.returncode
                if worker.returncode:state[kind+'_error']='Worker failed';state['state']='FAILED'
        except BaseException as e:state.update(consumer_cleanup_error=repr(e),state='FAILED')
        try:
            if video is not None:
                if video_dir.exists():(video_dir/'stop').touch(exist_ok=False)
                try:video.wait(timeout=60)
                except subprocess.TimeoutExpired:
                    video.terminate();video.wait(timeout=10)
                state['video_returncode']=video.returncode
                if video.returncode:state['video_error']='Video worker failed';state['state']='FAILED'
        except BaseException as e:state.update(video_cleanup_error=repr(e),state='FAILED')
        try:
            if p is not None and p.poll() is None:p.kill();p.wait(timeout=5)
            restore_drivers(recovery,ring_id,params,video_loaded,vp,changed)
            state['driver_restored']=True
        except BaseException as e:state.update(driver_restore_error=repr(e),state='FAILED')
        if shared.exists():
            # Native is stopped above; retain the frozen slots even on failure.
            try:
                with shared.open('rb') as src,(output/'slots.bin').open('xb') as dst:
                    while chunk:=src.read(1024*1024):dst.write(chunk)
            except FileExistsError:pass
            shared.unlink()
        if 'frames' in locals() and isinstance(frames,RowJournal) and not frames.closed:frames.close()
        state['fault_diagnostics']={key:decode_fault(state[key]) for key in ('hardware_fault_before_drain','after_drain','fault_registers') if key in state}
        b.close();state['binding']=binding
        if (output/'wire.fifo').is_fifo():(output/'wire.fifo').unlink()
        if (output/'record.fifo').is_fifo():(output/'record.fifo').unlink()
        if (output/'video.fifo').is_fifo():(output/'video.fifo').unlink()
        state['evidence']={str(q):sha(q) for q in output.iterdir() if q.is_file() and not q.is_fifo()}
        (output/'session.json').open('x').write(json.dumps(state,indent=2,default=journal_json));print(json.dumps(state,indent=2,default=journal_json))
    if state['state']=='FAILED' or not state['driver_restored'] or not state['cleanup_verified']:raise SystemExit(1)
if __name__=='__main__':
    with open('/run/lock/rxdiag712.lock','a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);main()
