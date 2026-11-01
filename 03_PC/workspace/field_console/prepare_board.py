"""Restore the accepted live1537 SRAM after cold boot; never writes Flash."""
from pathlib import Path
from datetime import datetime
import hashlib,json, socket,subprocess, sys,time,traceback
from recovery_support import progress,validate_status
from board_profile1415 import CAPABILITIES, verified_release, recovery_source
ROOT = Path(__file__).resolve().parent
ART = ROOT.parent/'artifacts'
SSH = ['ssh.exe', '-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', 'rk3576']


def remote(code):
    r = subprocess.run(SSH+['python3', '-B', '-'], input=code, text=True, capture_output=True, timeout=25)
    if r.returncode:
        raise RuntimeError(r.stderr or r.stdout)
    return json.loads(r.stdout)


def main():
    stamp = datetime.now().strftime('%Y%m%d_%H%M%S_%f')
    out = ROOT/('prepare_'+stamp)
    out.mkdir()
    progress(3,'检查板卡网络与PCIe状态')
    devices = remote("from pathlib import Path\nimport json\nprint(json.dumps([p.name for p in Path('/sys/bus/pci/devices').iterdir()]))")
    progress(8,'校验固件、历史证据与部署文件')
    verified_release(ROOT)
    # These are read by the legacy gated downloader. Check them before starting
    # the cable service, so missing archive inputs cannot fail halfway through.
    for manifest_path in (ART/'quiesce1145_20261028/status.json',verified_release(ROOT)):
        manifest=json.loads(manifest_path.read_text())
        for filename,digest in manifest.get('inputs',{}).items():
            path=Path(filename)
            if hashlib.sha256(path.read_bytes()).hexdigest()!=digest:
                raise ValueError('恢复依赖校验失败：'+str(path))
    for path in (ART/'probe_download881.py',ART/'gain1374_20261028/remote.py'):
        if not path.is_file():raise FileNotFoundError(str(path))
    scripts={filename:recovery_source(filename,(ART/filename).read_text()) for filename in
             ('program_sram1371.py','recover_endpoint1372.py','restore_driver1373.py')}
    for filename,code in scripts.items():compile(code,filename,'exec')
    if not devices:
        for name in ('hwserver.exe','bw_commands_prompt.exe'):
            path=Path('E:/Anlogic/TD_Release_2026.1_SP2.200.067/bin')/name
            if not path.is_file():raise FileNotFoundError(str(path))
    subprocess.run([sys.executable,'-B','-X','utf8',str(ROOT/'stage.py'),'--check-only'],check=True,timeout=90)
    if not devices:
        progress(18,'连接JTAG下载线并确认PH1A90')
        cable=subprocess.run(['powershell.exe','-NoProfile','-Command',
            "$p=Get-PnpDevice -PresentOnly -InstanceId 'USB\\VID_0403&PID_6042\\AL5B99F427' -ErrorAction SilentlyContinue; if ($p -and $p.Status -eq 'OK') {exit 0} else {exit 2}"],
            capture_output=True,text=True,timeout=20)
        if cable.returncode:raise ValueError('未识别到JTAG下载线 AL5B99F427；请连接FPGA烧录Type-C到电脑后重试，板子网线保持连接')
        # Validate and restart only a previously recorded task-owned Anlogic service.
        pid_files = [ART/'jtag1370_20261028/server.pid', ART/'quality1399_20261029/server.pid', *ROOT.glob('prepare_*/server.pid')]
        task_pid_file = max((p for p in pid_files if p.exists()), key=lambda p:p.stat().st_mtime_ns, default=None)
        previous = int(task_pid_file.read_text().strip()) if task_pid_file else 0
        executable = 'E:/Anlogic/TD_Release_2026.1_SP2.200.067/bin/hwserver.exe'
        ps = """$ErrorActionPreference='Stop'
$expected='EXE'
$prior=Get-CimInstance Win32_Process -Filter 'ProcessId=PRIOR'
if ($prior) {
 if ($prior.ExecutablePath -ne $expected -or $prior.CommandLine -notmatch 'AL5B99F427') { throw 'Recorded JTAG PID no longer matches this task; stop' }
 Stop-Process -Id $prior.ProcessId
}
$service=Start-Process -FilePath $expected -ArgumentList @('-r','-I','AL5B99F427') -WindowStyle Hidden -RedirectStandardOutput 'OUT/server.stdout' -RedirectStandardError 'OUT/server.stderr' -PassThru
$service.Id | Set-Content -LiteralPath 'OUT/server.pid' -Encoding Ascii
""".replace('EXE', executable.replace('/', '\\')).replace('PRIOR', str(previous)).replace('OUT', out.as_posix())
        subprocess.run(['powershell.exe', '-NoProfile', '-Command', ps], check=True, timeout=20)
        deadline=time.monotonic()+8
        while True:
            try:
                with socket.create_connection(('127.0.0.1',5555),timeout=.3):break
            except OSError:
                if time.monotonic()>=deadline:raise ValueError('JTAG服务未在8秒内就绪；请检查下载线与驱动，日志：'+str(out))
                time.sleep(.1)
        # One read-ID attempt, bounded. No download until exactPH1A90 is recognized.
        read = out/'read_id.tcl'
        read.write_text('if {[catch {\nconnect_cable -host_name 127.0.0.1:5555 -time_out 5000\nif {[read_device_id] ne "PH1A90"} {error "Expected PH1A90"}\nputs "FIELD_PH1A90_VERIFIED"\n} detail]} {puts "FIELD_JTAG_ERROR $detail"; exit 1}\nexit\n')
        with (out/'read_id.log').open('w') as f:
            subprocess.run(['E:/Anlogic/TD_Release_2026.1_SP2.200.067/bin/bw_commands_prompt.exe', read.as_posix()], stdout=f, stderr=subprocess.STDOUT, check=True, timeout=30)
        if 'FIELD_PH1A90_VERIFIED' not in (out/'read_id.log').read_text():
            raise ValueError('JTAG未确认PH1A90，未执行烧录；请检查下载线，日志：'+str(out/'read_id.log'))
        ids = {old: old+'_'+stamp for old in ('1371', '1372', '1373')}
        for filename in ('program_sram1371.py', 'recover_endpoint1372.py', 'restore_driver1373.py'):
            percent,message={'program_sram1371.py':(28,'加载FPGA SRAM，请保持供电和下载线连接'),
                             'recover_endpoint1372.py':(52,'重新枚举PCIe并核对接口'),
                             'restore_driver1373.py':(66,'恢复DMA驱动')}[filename]
            progress(percent,message)
            code = scripts[filename]
            if filename == 'program_sram1371.py':
                # This TD build accepts host_name on connect_cable, not read_device_id.
                old = 'set target [read_device_id -host_name 127.0.0.1:5555]'
                assert code.count(old) == 1
                code = code.replace(old, 'set target [read_device_id]')
            for old, new in ids.items():
                code = code.replace(old, new)
            target = ART/(Path(filename).stem+'_'+stamp+'.py')
            target.write_text(code)
            subprocess.run([sys.executable, '-B', '-X', 'utf8', str(target)], check=True, timeout=200)
    elif set(devices) != {'0000:20:00.0', '0000:21:00.0'}:
        raise RuntimeError('Unexpected PCIe topology; stop without reprogramming')
    progress(76,'检查相机初始化与采集通道空闲状态')
    status = remote("""from pathlib import Path
import mmap,struct,json
with open('/sys/bus/pci/devices/0000:21:00.0/resource0','rb',buffering=0) as f,mmap.mmap(f.fileno(),4096,access=mmap.ACCESS_READ) as m:
 print(json.dumps({hex(a):struct.unpack_from('<I',m,a)[0] for a in (0x5c,0x60,0x84,0x90,0x98,0xa4,0x1c8,0x1cc)}))
""")
    (out/'registers.json').write_text(json.dumps(status, indent=2))
    validate_status(status,CAPABILITIES)
    progress(79,'核对板端系统时间，避免云端证书校验失败')
    clock=remote("""import time,json,subprocess
pc_epoch=PC_EPOCH
if not 1704067200 < pc_epoch < 4102444800:raise ValueError('PC系统时间异常，请校准电脑时间')
before=time.time();adjusted=abs(pc_epoch-before)>300
rtc_returncode=None
if adjusted:
 time.clock_settime(time.CLOCK_REALTIME,pc_epoch)
 rtc_returncode=subprocess.run(['hwclock','--systohc','--utc'],capture_output=True,timeout=5).returncode
print(json.dumps(dict(before_unix=before,after_unix=time.time(),adjusted=adjusted,rtc_returncode=rtc_returncode)))
""".replace('PC_EPOCH',repr(time.time())))
    (out/'clock.json').write_text(json.dumps(clock,indent=2))
    if status['0x98'] == 80:
        gain = (ART/'gain1374_20261028/remote.py').read_text().replace('gain1374.json', 'field_gain_'+stamp+'.json')
        gain = gain.replace('0x4a505134', hex(status['0x5c']))
        result = remote(gain)
        (out/'gain.json').write_text(json.dumps(result, indent=2))
    else:
        assert status['0x98'] == 100, 'Unexpected sensor gain; stop rather than guessing'
    progress(84,'部署采集、检测和手机背景预览程序')
    subprocess.run([sys.executable, '-B', '-X', 'utf8', str(ROOT/'stage.py')], check=True, timeout=90)
    progress(96,'核对部署文件与预览功能')
    remote("from pathlib import Path\nimport ast,json\np=Path('/userdata/native_required1138_20261028/control_field1382.py')\nt=p.read_text();ast.parse(t)\nassert \"ap.add_argument('--preview-only'\" in t\nassert (p.parent/'field1382/preview_remote.py').is_file()\nprint('{}')")
    print('FIELD_BOARD_READY: SRAM only; no Flash; no capture and no2h test started.')
    progress(100,'设备恢复完成','done')


if __name__=='__main__':
    try:main()
    except BaseException as error:
        traceback.print_exc()
        if isinstance(error,FileNotFoundError):message='恢复所需文件缺失：'+str(error.filename or error)
        elif isinstance(error,subprocess.TimeoutExpired):message='恢复步骤超时：'+str(error.cmd)
        elif isinstance(error,subprocess.CalledProcessError):message='恢复步骤未通过：'+str(error.cmd)+'；请查看前面的错误详情'
        else:message=str(error) or type(error).__name__
        progress(0,message,'failed')
        print(message,file=sys.stderr,flush=True)
        raise SystemExit(1)
