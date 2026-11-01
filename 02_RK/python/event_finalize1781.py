"""Capture post-window frames without waiting for clip EOS/fsync/hash finalization."""
from pathlib import Path
import json,os,queue,threading
from event_record1781 import CircularEventRecorder as BaseRecorder
from event_record837 import EventRecorder

class CircularEventRecorder(BaseRecorder):
    def __init__(self,*args,**kwargs):
        self.store_lock=threading.RLock();self.finalizing_bytes=0;self.finalize_error=None
        super().__init__(*args,**kwargs)
        self.finalize_queue=queue.Queue(maxsize=1)
        self.finalize_stats=dict(completed=0,pending_peak_jobs=0)
        original=self.factory
        def factory(*args,**kwargs):
            with self.store_lock:return original(*args,**kwargs)
        self.factory=factory
        self.finalizer=threading.Thread(target=self._finalize_worker,name='event-finalizer1264',daemon=True)
        self.finalizer.start()

    def _check(self):
        if self.finalize_error:raise RuntimeError('Event finalization failed: '+self.finalize_error)

    def frame(self,*args):
        self._check();return super().frame(*args)

    def alarm(self,*args):
        self._check();return super().alarm(*args)

    def _space(self,additional):
        with self.store_lock:
            active=self.active
            self.store.ensure_space(additional,pending=self.finalizing_bytes+(active['payload_bytes'] if active else 0),
                                    active=active['directory'] if active else None)

    def _close(self,reason,observed_ns):
        self._check();active=self.active
        with self.store_lock:
            self.finalizing_bytes+=active['payload_bytes']
            try:self.finalize_queue.put_nowait((active,reason,observed_ns))
            except queue.Full:
                self.finalizing_bytes-=active['payload_bytes']
                raise BufferError('Event finalizer queue exhausted')
            self.finalize_stats['pending_peak_jobs']=max(self.finalize_stats['pending_peak_jobs'],self.finalize_queue.qsize())
            self.active=None

    def _finalize_one(self,active,reason,observed_ns):
        report=active['clip'].close()
        event=dict(state='EVENT837_FINALIZED',incident_id=active['incident_id'],
            timestamp_basis='host_commit_CLOCK_MONOTONIC_not_camera_exposure',
            evidence_host_monotonic_ns=active['evidence_ns'],requested_start_ns=active['requested_start_ns'],
            requested_end_ns=active['deadline_ns'],first_recorded_ns=active['first_ns'],
            last_recorded_ns=report['frames'][-1]['source_monotonic_ns'],post_window_observed=observed_ns>=active['deadline_ns'],
            pre_window_truncated=active['pre_window_truncated'],completion_reason=reason,
            frame_ids=active['ids'],container_sha256=report['container_sha256'])
        # Do not hold the store lock during EOS, fsync or media hashing. Guard
        # event metadata publication against concurrent quota scans/reclamation.
        with self.store_lock:
            path=active['directory']/'event.json'
            with path.open('x') as stream:json.dump(event,stream,indent=2);stream.flush();os.fsync(stream.fileno())
            fd=os.open(active['directory'],os.O_RDONLY|os.O_DIRECTORY)
            try:os.fsync(fd)
            finally:os.close(fd)
            self.completed.append(dict(directory=str(active['directory']),**event))
            self.finalize_stats['completed']+=1

    def _finalize_worker(self):
        while True:
            job=self.finalize_queue.get()
            try:
                if job is None:return
                active,reason,observed_ns=job
                try:
                    if self.finalize_error:active['clip'].abort()
                    else:self._finalize_one(active,reason,observed_ns)
                except BaseException as error:
                    self.finalize_error=repr(error)
                    if not active['clip'].closed:active['clip'].abort()
                finally:
                    with self.store_lock:self.finalizing_bytes-=active['payload_bytes']
            finally:self.finalize_queue.task_done()

    def close(self):
        failure=None
        try:EventRecorder.close(self)
        except BaseException as error:
            failure=error
            if self.active:self.active['clip'].abort();self.active=None
        try:
            self.finalize_queue.put(None,timeout=30)
            self.finalizer.join(60)
            if self.finalizer.is_alive():raise TimeoutError('Event finalizer did not stop')
            if failure:raise failure
            self._check()
        finally:
            if not self.finalizer.is_alive():self.store.close()
