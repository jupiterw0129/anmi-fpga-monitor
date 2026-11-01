import sys
sys.path.insert(0,'/userdata/native_required1138_20261028')
sys.path.append('/userdata/native_required1138_20261028/reliable1326')
from long_journal1295 import RowJournal,journal_json
from sd_monitor1243 import RecorderMonitor
from session_config1301 import runtime_seconds
import sys
sys.path.append('/userdata/integrated1013_20261027')
"""Independent SD diagnostic clip plus real persistent-alarm event adapter."""
from pathlib import Path
import argparse,json,mmap,os,sqlite3,time,faulthandler
from fifo_sampler1326 import FifoSampler
from alarm_poll1287 import AlarmPoll
from segment_worker1752 import SegmentRecorder
from event_worker1267 import CircularEventRecorder as EventRecorder

def main():
    p=argparse.ArgumentParser()
    for name in ('shared','output','recordings','alarm-db','session'):p.add_argument('--'+name,required=True)
    p.add_argument('--frame-fifo',required=True)
    p.add_argument('--generation',type=int,required=True);p.add_argument('--max-seconds',type=runtime_seconds,required=True);a=p.parse_args()
    out=Path(a.output);out.mkdir();root=Path(a.recordings);root.mkdir()
    report=dict(state='FAILED',scope='Real camera diagnostic clip, not a synthetic fall alarm',events=[])
    fd=mm=sampler=clip=rec=db=monitor=poller=None;seen=set()
    costs={};slow=RowJournal(out/'slow_stages.jsonl');progress={'stage':'initialization','rows':0}
    def timed(stage,fn,*args):
        progress['stage']=stage;progress['stage_started_ns']=time.monotonic_ns()
        faulthandler.dump_traceback_later(1,repeat=True)
        begin=time.monotonic()
        try:return fn(*args)
        finally:
            elapsed=time.monotonic()-begin;faulthandler.cancel_dump_traceback_later()
            c=costs.setdefault(stage,{'calls':0,'total_s':0,'max_s':0})
            c['calls']+=1;c['total_s']+=elapsed;c['max_s']=max(c['max_s'],elapsed)
            if elapsed>.02:slow.append(dict(stage=stage,elapsed_s=elapsed,rows=progress['rows'],at=time.monotonic()))

    try:
        assert os.statvfs(root).f_bavail*os.statvfs(root).f_frsize>1024**3
        db=sqlite3.connect(Path(a.alarm_db).as_uri()+'?mode=ro',uri=True,timeout=0)
        db.row_factory=sqlite3.Row
        poller=AlarmPoll(db)
        while not poller.known:
            poller.read()
            if not poller.known:time.sleep(.005)
        clip=SegmentRecorder(root/'diagnostic',1920,1080,60,segment_frames=600,segment_bytes=128*1024**2,quota_bytes=512*1024**2)
        rec=EventRecorder(root/'events',1920,1080,60)
        fd=os.open(a.shared,os.O_RDONLY|os.O_NOFOLLOW);mm=mmap.mmap(fd,0,access=mmap.ACCESS_READ)
        sampler=FifoSampler(a.frame_fifo,a.generation);sampler.start()
        def current_clip():
            active=clip.core.active
            return active['clip'] if active else None
        monitor=RecorderMonitor(out,progress,current_clip,lambda:sampler);monitor.start()
        (out/'ready.tmp').open('x').write(json.dumps(dict(generation=a.generation,session=a.session)))
        os.replace(out/'ready.tmp',out/'ready.json')
        deadline=time.monotonic()+a.max_seconds
        while True:
            if monitor.error:raise RuntimeError('Recorder monitor failed: '+monitor.error)
            stopping=(out/'stop').exists()
            # Keep consuming until the native writer has closed its FIFO.
            for row in timed('take',sampler.take):
                timed('push',clip.frame,*row);timed('event_frame',rec.frame,*row);progress['rows']+=1
            alarm=timed('sqlite',poller.read)
            if alarm and alarm['id'] not in seen and alarm['opened_session']==a.session:
                if rec.last and alarm['opened_s']*1e9<=rec.last[1] and rec.active is None:
                    rec.alarm(alarm['id'],round(alarm['opened_s']*1e9));seen.add(alarm['id'])
            if stopping and poller.known and sampler.eof.is_set() and sampler.bytes==0:
                sampler.stop();break
            if time.monotonic()>deadline:raise TimeoutError('SD recorder exceeded bound')
            time.sleep(.002)
        timed('event_close',rec.close);timed('clip_close',clip.close)
        report.update(state='LIVE1012_REAL_SD_DIAGNOSTIC_CLIP_FINALIZED_ALARM_ADAPTER_RAN',
            frames=clip.stats['frames_processed'],segments=clip.completed,segment_worker=clip.stats,segment_finalizer=clip.finalize_stats,segment_evictions=clip.store.evicted,segment_recovery=clip.startup_recovery,segment_pending_bytes=clip.pending_bytes,segment_finalizing_bytes=clip.finalizing_bytes,
            container_bytes=sum(s['container_bytes'] for s in clip.completed),sampler=sampler.stats,queue_peak_bytes=sampler.peak_bytes,
            events=rec.completed,event_worker=rec.stats,event_finalizer=rec.finalize_stats,event_pending_bytes=rec.pending_bytes,event_finalizing_bytes=rec.finalizing_bytes,circular_store=True,evictions=rec.store.evicted,startup_recovery=rec.startup_recovery,real_alarm_ids_observed=sorted(seen),diagnostic_directory=str(root/'diagnostic'))
        assert sampler.stats['frame_id_gaps']==sampler.stats['queue_overflow_frames']==0
    except BaseException as e:
        report.update(state='FAILED',error=repr(e))
        if clip:
            report.update(segment_worker=clip.stats,segment_pending_bytes=clip.pending_bytes,
                segment_finalizer=clip.finalize_stats)
        if clip:
            try:clip.abort()
            except BaseException as cleanup:report['segment_cleanup_error']=repr(cleanup)
        if rec:
            try:rec.abort()
            except BaseException as cleanup:report['event_cleanup_error']=repr(cleanup)
        raise
    finally:
        faulthandler.cancel_dump_traceback_later()
        if sampler:
            sampler.stop_event.set();sampler.thread.join(5)
            report.update(sampler=sampler.stats,queue_peak_bytes=sampler.peak_bytes,sampler_error=repr(sampler.error),fifo_clean_eof=sampler.eof.is_set())
            sampler.close()
        if monitor:
            try:monitor.stop()
            except BaseException as e:report.update(state='FAILED',monitor_error=repr(e))
            report['kernel_samples']=monitor.count
        report.update(stage_costs=costs,slow_stages=slow,progress=progress,max_seconds=a.max_seconds) 
        if mm:mm.close()
        if fd is not None:os.close(fd)
        if poller:report['alarm_poll']=dict(known=poller.known,**poller.stats)
        if db:db.close()
        if not slow.closed:slow.close()
        (out/'report.json').open('x').write(json.dumps(report,indent=2,default=journal_json))
    if report['state']=='FAILED':raise RuntimeError(report.get('monitor_error','Recorder failed'))

if __name__=='__main__':main()
