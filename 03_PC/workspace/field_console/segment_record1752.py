"""Finite JPEG segments; one queued finalization and one running finalization.

Only the input worker calls frame/close. Media finalization stays outside the
store lock; publication and reclamation are serialized. Retained media is
owned, complete, hash-checked and unpinned before any quota eviction.
"""
from pathlib import Path
import hashlib,json,os,queue,threading,uuid
from jpeg_event1752 import JpegClip
from segment_store1752 import SegmentStore

class SegmentCore:
    def __init__(self,root,width,height,fps=60,segment_frames=600,
                 segment_bytes=256*1024**2,quota_bytes=4*1024**3,reserve_bytes=512*1024**2):
        if not 1<=segment_frames<=3600 or not 8*1024**2<=segment_bytes<=512*1024**2:
            raise ValueError('Invalid segment bounds')
        if quota_bytes<3*segment_bytes:raise ValueError('Quota must fit active and two finalizing segments')
        self.root=Path(root);self.width=width;self.height=height;self.fps=fps
        self.segment_frames=segment_frames;self.segment_bytes=segment_bytes
        self.store=SegmentStore(root,quota_bytes,reserve_bytes);self.startup_recovery=self.store.recover()
        self.lock=threading.RLock();self.active=None;self.last=None;self.closed=False
        self.finalizing_bytes=0;self.error=None;self.completed=[];self.sequence=0;self.run_id=uuid.uuid4().hex
        self.finalize_queue=queue.Queue(maxsize=1);self.finalize_stats=dict(completed=0,pending_peak_jobs=0)
        self.ledger=os.fdopen(os.open(self.root/'segments.jsonl',os.O_WRONLY|os.O_CREAT|os.O_APPEND|os.O_NOFOLLOW,0o600),'a',encoding='utf-8')
        self.finalizer=threading.Thread(target=self._finalize,name='segment-finalizer1277',daemon=True);self.finalizer.start()

    def _check(self):
        if self.error:raise RuntimeError('Segment finalization failed: '+self.error)

    def _open(self):
        with self.lock:
            self.store.ensure_space(self.segment_bytes,pending=self.finalizing_bytes)
            directory=self.root/('segment_'+uuid.uuid4().hex)
            clip=JpegClip(directory,self.width,self.height,self.fps,limit_bytes=self.segment_bytes)
            try:self.store.register(directory)
            except BaseException:clip.abort();raise
            self.active=dict(clip=clip,directory=directory,payload_bytes=0,sequence=self.sequence)
            self.sequence+=1

    def _rotate(self):
        self._check();active=self.active
        with self.lock:
            self.finalizing_bytes+=active['payload_bytes']
            try:self.finalize_queue.put_nowait(active)
            except queue.Full:
                self.finalizing_bytes-=active['payload_bytes'];raise BufferError('Segment finalizer queue exhausted')
            self.finalize_stats['pending_peak_jobs']=max(self.finalize_stats['pending_peak_jobs'],self.finalize_queue.qsize())
            self.active=None

    def frame(self,frame_id,time_ns,data):
        self._check()
        if self.closed:raise RuntimeError('Segment recorder closed')
        if self.last and (frame_id!=self.last[0]+1 or time_ns<=self.last[1]):raise ValueError('Segment source gap or nonmonotonic time')
        # Keep room for Matroska headers/index and refuse an oversized single frame.
        if len(data)+65536>self.segment_bytes:raise ValueError('Frame exceeds finite segment')
        if self.active and (len(self.active['clip'].rows)>=self.segment_frames or self.active['payload_bytes']+len(data)+65536>self.segment_bytes):self._rotate()
        if self.active is None:self._open()
        with self.lock:
            self.store.ensure_space(len(data),pending=self.finalizing_bytes+self.active['payload_bytes'],active=self.active['directory'])
        self.active['clip'].push(frame_id,time_ns,data);self.active['payload_bytes']+=len(data);self.last=(frame_id,time_ns)

    def _finalize_one(self,active):
        m=active['clip'].close();rows=m['frames']
        summary=dict(state='SEGMENT1277_FINALIZED',run_id=self.run_id,sequence=active['sequence'],frames=len(rows),
            first_frame_id=rows[0]['frame_id'],last_frame_id=rows[-1]['frame_id'],
            first_source_ns=rows[0]['source_monotonic_ns'],last_source_ns=rows[-1]['source_monotonic_ns'],
            container_bytes=m['container_bytes'],container_sha256=m['container_sha256'],
            frames_sha256=hashlib.sha256(json.dumps(rows,sort_keys=True,separators=(',',':')).encode()).hexdigest())
        with self.lock:
            self.store._json(active['directory']/'segment.json',summary)
            record=dict(directory=active['directory'].name,**summary)
            self.ledger.write(json.dumps(record)+'\n');self.ledger.flush();os.fsync(self.ledger.fileno())
            self.completed.append(record);self.finalize_stats['completed']+=1

    def _finalize(self):
        while True:
            active=self.finalize_queue.get()
            try:
                if active is None:return
                try:
                    if self.error:active['clip'].abort()
                    else:self._finalize_one(active)
                except BaseException as e:
                    self.error=repr(e)
                    if not active['clip'].closed:active['clip'].abort()
                finally:
                    with self.lock:self.finalizing_bytes-=active['payload_bytes']
            finally:self.finalize_queue.task_done()

    def close(self):
        self.closed=True;failure=None
        try:
            if self.active:self._rotate()
        except BaseException as e:
            failure=e
            if self.active:self.active['clip'].abort();self.active=None
        try:
            self.finalize_queue.put(None,timeout=30);self.finalizer.join(60)
            if self.finalizer.is_alive():raise TimeoutError('Segment finalizer did not stop')
            if failure:raise failure
            self._check()
        finally:
            if not self.finalizer.is_alive():self.ledger.close();self.store.close()
