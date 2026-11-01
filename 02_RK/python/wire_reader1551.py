"""FIFO -> SSH; lost delivery requests scoped stop and drains without EPIPE."""
from pathlib import Path
import argparse,hashlib,json,os,re,select,signal,stat,time

BASE=Path('/userdata/native_required1138_20261028')


def paths(directory,base=BASE):
    root=Path(directory)
    if root.parent!=base/'evidence' or not re.fullmatch(r'field_[0-9_]+',root.name):
        raise ValueError('Reader is restricted to one field evidence directory')
    stop=base/'field1382'/root.name/'stop_requested'
    for directory in (root,stop.parent):
        if not directory.is_dir() or any(p.is_symlink() for p in (directory,*directory.parents)):
            raise ValueError('Missing or symlinked session directory')
    if not (stop.parent/'identity.json').is_file():
        raise ValueError('Missing field session identity')
    return root,stop


def run(root,stop,output=1,write_timeout=2,drain_timeout=30):
    fifo=root/'wire.fifo';report=root/'wire_reader.report.json'
    s=fifo.lstat()
    if not (stat.S_ISFIFO(s.st_mode) and s.st_uid==os.getuid() and s.st_mode&0o777==0o600):
        raise ValueError('Unexpected FIFO type, owner or permissions')
    fd=os.open(fifo,os.O_RDONLY|os.O_NONBLOCK|os.O_NOFOLLOW)
    h=hashlib.sha256();count=sent=0;started=last=time.monotonic()
    failure=None;drain_started=None;error=None;state='FAILED';pending_signal=None
    max_stall=0.0;stall_count=0;stall_started=None
    previous={};was_blocking=os.get_blocking(output)

    def interrupted(signum,frame):
        nonlocal pending_signal
        pending_signal=signum

    def lose_delivery(reason):
        nonlocal failure,drain_started
        if failure is not None:return
        failure=reason;drain_started=time.monotonic()
        try:
            stop_fd=os.open(stop,os.O_CREAT|os.O_EXCL|os.O_WRONLY|os.O_NOFOLLOW,0o600)
        except FileExistsError:
            if stop.is_symlink() or not stop.is_file():raise ValueError('Invalid existing stop request')
        else:os.close(stop_fd)

    try:
        for signum in (signal.SIGHUP,signal.SIGTERM,signal.SIGINT):
            previous[signum]=signal.signal(signum,interrupted)
        os.set_blocking(output,False)
        (root/'wire_reader.ready.json').open('x').write(json.dumps(dict(pid=os.getpid(),
            start_ticks=Path('/proc/self/stat').read_text().rsplit(')',1)[1].split()[19])))
        while True:
            now=time.monotonic()
            if pending_signal is not None:lose_delivery('signal '+str(pending_signal))
            if now-started>7500 or now-last>(15 if count else 120):raise TimeoutError('Wire reader deadline')
            if drain_started is not None and now-drain_started>drain_timeout:
                raise TimeoutError('Disconnected FIFO did not drain within bound')
            if not select.select([fd],[],[],.05)[0]:continue
            data=os.read(fd,1024*1024)
            if not data:
                if count:break
                if (root/'session.json').exists():raise RuntimeError('Controller stopped before any wire data')
                time.sleep(.01);continue
            count+=len(data);h.update(data);last=now
            if count>70*1024**3:raise BufferError('External wire exceeded70GiB bound')
            if failure is not None:continue
            view=memoryview(data);write_progress=now
            while view and failure is None:
                if pending_signal is not None:
                    lose_delivery('signal '+str(pending_signal));break
                try:
                    n=os.write(output,view)
                    if n<=0:raise BrokenPipeError('SSH stdout write failed')
                    sent+=n;view=view[n:];write_progress=time.monotonic()
                    if stall_started is not None:
                        max_stall=max(max_stall,write_progress-stall_started);stall_started=None
                except BlockingIOError:
                    if stall_started is None:stall_started=time.monotonic();stall_count+=1
                    max_stall=max(max_stall,time.monotonic()-stall_started)
                    if time.monotonic()-write_progress>write_timeout:
                        lose_delivery('SSH stdout stalled')
                    else:select.select([],[output],[],.05)
                except OSError as e:lose_delivery(repr(e))
        state=('WIRE1551_DELIVERY_FAILED_FIFO_DRAINED' if failure is not None else
               'WIRE1551_FIFO_EOF_STREAM_SENT_PENDING_PC_FSYNC_HASH')
    except BaseException as e:
        error=repr(e)
        try:lose_delivery(error)
        except BaseException as stop_error:error+='; stop failed: '+repr(stop_error)
    finally:
        os.close(fd)
        for signum,handler in previous.items():signal.signal(signum,handler)
        os.set_blocking(output,was_blocking)
        result=dict(state=state,bytes=count,delivered_bytes=sent,discarded_bytes=count-sent,
            sha256=h.hexdigest(),delivery_error=failure,error=error,stop_requested=failure is not None and stop.is_file(),
            elapsed_s=time.monotonic()-started,write_timeout_s=write_timeout,stdout_stall_count=stall_count,max_stdout_stall_s=max_stall)
        report.open('x').write(json.dumps(result,indent=2))
    return result


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--directory',required=True)
    args=parser.parse_args();root,stop=paths(args.directory)
    result=run(root,stop)
    return 0 if result['state']=='WIRE1551_FIFO_EOF_STREAM_SENT_PENDING_PC_FSYNC_HASH' else 1


if __name__=='__main__':raise SystemExit(main())
