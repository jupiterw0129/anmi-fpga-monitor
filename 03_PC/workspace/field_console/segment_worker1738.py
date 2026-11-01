"""Isolate event pre-roll feeding and finalization from continuous diagnostic intake."""
from collections import deque
import threading,time
from segment_record1738 import SegmentCore as CoreRecorder

class SegmentRecorder:
    def __init__(self,*args,input_limit=64*1024**2,**kwargs):
        if input_limit<=0:raise ValueError('Invalid event input byte limit')
        self.args=args;self.kwargs=kwargs;self.input_limit=input_limit
        self.condition=threading.Condition();self.jobs=deque();self.pending_bytes=0;self.processing=False
        self.closing=False;self.aborting=False;self.error=None;self.core=None;self.last=None;self.seen=set();self.pending_alarms=0
        self.ready=threading.Event();self.done=threading.Event()
        self.stats=dict(frames_enqueued=0,frames_processed=0,alarms_enqueued=0,alarms_processed=0,
                        queue_peak_bytes=0,queue_overflows=0,discarded_jobs_on_abort=0,max_core_call_ns=0)
        self.worker=threading.Thread(target=self._run,name='segment-intake1277',daemon=True);self.worker.start()
        if not self.ready.wait(30):raise TimeoutError('Event worker initialization timeout')
        self._check()

    def _check(self):
        if self.error:raise RuntimeError('Event worker failed: '+self.error)

    def _enqueue(self,kind,args,size):
        with self.condition:
            self._check()
            if self.closing or self.aborting:raise RuntimeError('Event worker closed')
            if self.pending_bytes+size>self.input_limit or len(self.jobs)>=4096:
                self.stats['queue_overflows']+=1
                raise BufferError('Event worker bounded command/byte queue overflow')
            self.jobs.append((kind,args,size));self.pending_bytes+=size
            self.stats['queue_peak_bytes']=max(self.stats['queue_peak_bytes'],self.pending_bytes)
            self.condition.notify_all()

    def frame(self,frame_id,time_ns,data):
        if self.last and (frame_id<=self.last[0] or time_ns<=self.last[1]):raise ValueError('Event source identity/time must advance')
        payload=bytes(data)
        if not(payload[:2]==b'\xff\xd8' and payload[-2:]==b'\xff\xd9'):raise ValueError('Event source JPEG boundaries missing')
        self._enqueue('frame',(frame_id,time_ns,payload),len(payload))
        self.last=(frame_id,time_ns);self.stats['frames_enqueued']+=1

    def alarm(self,incident_id,evidence_ns):
        key=str(incident_id)
        if key in self.seen:return False
        if not self.last or evidence_ns>self.last[1]:raise ValueError('Alarm requires accepted source timestamp')
        self.pending_alarms+=1
        try:self._enqueue('alarm',(incident_id,evidence_ns),0)
        except BaseException:self.pending_alarms-=1;raise
        self.seen.add(key);self.stats['alarms_enqueued']+=1;return True

    @property
    def active(self):
        if self.pending_alarms:return {'pending':True}
        return self.core.active
    @property
    def store(self):return self.core.store
    @property
    def startup_recovery(self):return self.core.startup_recovery
    @property
    def completed(self):return self.core.completed
    @property
    def finalize_stats(self):return self.core.finalize_stats
    @property
    def finalizing_bytes(self):return self.core.finalizing_bytes

    def _run(self):
        try:
            self.core=CoreRecorder(*self.args,**self.kwargs);self.ready.set()
            while True:
                with self.condition:
                    while not self.jobs and not self.closing and not self.aborting:self.condition.wait()
                    if self.aborting:
                        self.stats['discarded_jobs_on_abort']+=len(self.jobs);self.jobs.clear();self.pending_bytes=0;break
                    if not self.jobs and self.closing:break
                    kind,args,size=self.jobs.popleft();self.pending_bytes-=size;self.processing=True
                started=time.monotonic_ns()
                try:
                    getattr(self.core,kind)(*args)
                    self.stats['frames_processed' if kind=='frame' else 'alarms_processed']+=1
                finally:
                    self.stats['max_core_call_ns']=max(self.stats['max_core_call_ns'],time.monotonic_ns()-started)
                    with self.condition:
                        if kind=='alarm':self.pending_alarms-=1
                        self.processing=False;self.condition.notify_all()
        except BaseException as error:self.error=repr(error)
        finally:
            self.ready.set()
            if self.core:
                try:
                    if (self.error or self.aborting) and self.core.active:
                        self.core.active['clip'].abort();self.core.active=None
                    self.core.close()
                except BaseException as error:
                    self.error=self.error or repr(error)
            self.done.set()
            with self.condition:self.condition.notify_all()

    def wait_idle(self,timeout=30):
        with self.condition:
            if not self.condition.wait_for(lambda:self.error or (not self.jobs and not self.processing),timeout):raise TimeoutError('Event worker idle deadline')
            self._check()

    def close(self):
        with self.condition:self.closing=True;self.condition.notify_all()
        self.worker.join(60)
        if self.worker.is_alive():raise TimeoutError('Event worker did not close')
        self._check()
        assert self.stats['frames_enqueued']==self.stats['frames_processed']
        assert self.stats['alarms_enqueued']==self.stats['alarms_processed']

    def abort(self):
        with self.condition:self.aborting=True;self.condition.notify_all()
        self.worker.join(15)
        if self.worker.is_alive():raise TimeoutError('Event worker did not abort')
