"""Bounded recovery subprocesses and stage progress shared by CLI and desktop."""
from pathlib import Path
import json,os,subprocess,time

PREFIX='FIELD_RECOVERY '


def progress(percent,message,state='running'):
    print(PREFIX+json.dumps(dict(percent=percent,message=message,state=state),ensure_ascii=False),flush=True)


def run_recovery(root,callback,timeout=480):
    import sys
    root=Path(root)
    output=root/'output';output.mkdir(exist_ok=True)
    log=output/('recovery_'+str(time.time_ns())+'.log')
    hidden=dict(creationflags=subprocess.CREATE_NO_WINDOW) if os.name=='nt' else {}
    # JTAG's background service can inherit stdout handles through PowerShell.
    # Tail a regular log file and watch the parent exit, never wait for pipe EOF.
    stream=log.open('wb')
    proc=subprocess.Popen([sys.executable,'-u','-B','-X','utf8',str(root/'prepare_board.py')],
        stdout=stream,stderr=subprocess.STDOUT,**hidden)
    tail=[];started=time.monotonic()
    try:
        with log.open('r',encoding='utf-8',errors='replace') as reader:
            while True:
                if time.monotonic()-started>timeout:
                    raise TimeoutError('设备恢复超过限定时间；请查看日志 '+str(log))
                line=reader.readline()
                if not line:
                    if proc.poll() is not None:break
                    time.sleep(.1);continue
                tail=(tail+[line.rstrip()])[-25:]
                if line.startswith(PREFIX):
                    try:row=json.loads(line[len(PREFIX):])
                    except ValueError:continue
                    callback(row)
        proc.wait(timeout=10)
        if proc.returncode:
            message=next((x for x in reversed(tail) if x and not x.startswith(PREFIX)),'恢复程序异常退出')
            raise RuntimeError(message+'；日志：'+str(log))
        return log
    finally:
        if proc.poll() is None:
            if os.name=='nt':subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],capture_output=True,timeout=15,**hidden)
            else:proc.kill()
            proc.wait(timeout=15)
        stream.close()


def validate_status(status,capabilities):
    if status['0x5c'] not in capabilities:raise ValueError('FPGA版本无法识别，已停止恢复')
    if status['0x1c8']!=capabilities[status['0x5c']]:raise ValueError('FPGA能力标识不匹配，已停止恢复')
    if any(status[key] for key in ('0x60','0x90','0xa4')) or status['0x1cc']&7:
        raise ValueError('FPGA采集/JPEG通道未退出；请停止测试，完整断电后上电，接好JTAG下载线，再恢复设备')
    if status['0x84']&9!=1:raise ValueError('摄像头初始化失败；请断电检查10cm排线及供电后重新上电')
