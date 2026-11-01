"""Bounded recorder and kernel observations; no writeback/queue tuning."""
from pathlib import Path
import json,threading,time

def process_sample(pid,start_ticks):
    root=Path('/proc')/str(pid)
    try:
        stat=(root/'stat').read_text()
        if stat.rsplit(')',1)[1].split()[19]!=str(start_ticks):
            return dict(pid=pid,state='PID_REUSED')
        row=dict(pid=pid,state='PRESENT',stat=stat,tasks=[])
        for name in ('io','status','syscall'):
            try:row[name]=(root/name).read_text()
            except (FileNotFoundError,ProcessLookupError,PermissionError) as e:row[name+'_error']=type(e).__name__
        for task in (root/'task').iterdir():
            try:row['tasks'].append(dict(tid=task.name,name=(task/'comm').read_text().strip(),wchan=(task/'wchan').read_text().strip()))
            except (FileNotFoundError,ProcessLookupError):pass
        return row
    except (FileNotFoundError,ProcessLookupError):return dict(pid=pid,state='EXITED')

class RecorderMonitor:
    def __init__(self,output,progress,get_clip,get_sampler):
        self.output=Path(output);self.progress=progress
        self.get_clip=get_clip;self.get_sampler=get_sampler
        self.stop_event=threading.Event();self.error=None;self.count=0
        self.thread=threading.Thread(target=self.run,name='SD-diagnostic-monitor',daemon=True)
    def start(self):self.thread.start()
    def run(self):
        try:
            with (self.output/'kernel_samples.jsonl').open('x') as journal:
                while not self.stop_event.is_set():
                    row=dict(host_ns=time.monotonic_ns(),progress=dict(self.progress),tasks=[],memory={})
                    for line in Path('/proc/meminfo').read_text().splitlines():
                        key,value=line.split(':',1)
                        if key in ('MemAvailable','Dirty','Writeback'):row['memory'][key]=value.strip()
                    row['disks']=[line for line in Path('/proc/diskstats').read_text().splitlines() if 'mmcblk' in line]
                    for task in Path('/proc/self/task').iterdir():
                        try:row['tasks'].append(dict(tid=task.name,name=(task/'comm').read_text().strip(),wchan=(task/'wchan').read_text().strip(),stat=(task/'stat').read_text()))
                        except (FileNotFoundError,ProcessLookupError):pass
                    identity=self.output.parent/'native_identity.json'
                    if identity.exists():
                        native=json.loads(identity.read_text())
                        row['native']=process_sample(native['pid'],native['start_ticks'])
                    clip=self.get_clip();sampler=self.get_sampler()
                    if clip:
                        row['appsrc_bytes']=int(clip.source.get_property('current-level-bytes'))
                        row['written_extent_bytes']=getattr(clip,'high_water',None)
                        try:row['partial_bytes']=clip.partial.stat().st_size
                        except (FileNotFoundError,ProcessLookupError):pass
                    if sampler:
                        with sampler.lock:
                            row.update(sampler_pending_bytes=sampler.bytes,sampler_peak_bytes=sampler.peak_bytes,
                                sampler_limit_bytes=sampler.limit,sampler_stats=dict(sampler.stats))
                    journal.write(json.dumps(row)+'\n');journal.flush();self.count+=1
                    self.stop_event.wait(.2)
        except BaseException as e:self.error=repr(e)
    def stop(self):
        self.stop_event.set();self.thread.join(5)
        if self.thread.is_alive():raise TimeoutError('Diagnostic monitor did not stop')
        if self.error:raise RuntimeError(self.error)
