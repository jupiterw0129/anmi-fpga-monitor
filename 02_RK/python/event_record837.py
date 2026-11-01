"""Committed-JPEG event recording engine. Call only from a recording worker.

Frame timestamps and alarm evidence timestamps must share host CLOCK_MONOTONIC.
These timestamps do not measure camera exposure or physical end-to-end latency.
The live publication/AI adapter must provide a bounded nonblocking worker queue;
this module itself can block on SD writes and must never run on the DMA thread.
"""
from collections import deque
from pathlib import Path
import json,os,shutil,uuid

class EventRecorder:
    def __init__(self,root,width,height,fps=60,pre_ns=3_000_000_000,
                 post_ns=3_000_000_000,buffer_bytes=64*1024**2,
                 quota_bytes=24*1024**3,reserve_bytes=256*1024**2,alarm_lag_ns=2_000_000_000):
        from jpeg_clip809 import JpegClip
        if min(width,height,fps,buffer_bytes,quota_bytes)<=0 or min(pre_ns,post_ns,reserve_bytes,alarm_lag_ns)<0:
            raise ValueError('Invalid recording limits')
        self.root=Path(root);self.root.mkdir(exist_ok=True)
        self.width=width;self.height=height;self.fps=fps;self.pre=pre_ns;self.post=post_ns
        self.history=pre_ns+alarm_lag_ns
        self.limit=buffer_bytes;self.quota=quota_bytes;self.reserve=reserve_bytes
        self.factory=JpegClip;self.buffer=deque();self.buffer_size=0;self.last=None
        self.active=None;self.seen=set();self.completed=[];self.evicted_bytes=0
        self.peak_buffer_bytes=0;self.closed=False

    def _space(self,additional):
        used=sum(p.stat().st_size for p in self.root.rglob('*') if p.is_file())
        # Pending Gst writes may not yet appear in stat(). Include all admitted
        # JPEG payloads conservatively, plus64KiB for container/metadata overhead.
        pending=self.active['payload_bytes'] if self.active else 0
        if used+pending+additional+65536>self.quota:
            raise OSError('Event recording quota exhausted; existing recordings preserved')
        if shutil.disk_usage(self.root).free<pending+additional+self.reserve+65536:
            raise OSError('Insufficient free space for event recording')

    def _push(self,row):
        self._space(len(row[2]));a=self.active
        a['clip'].push(*row);a['payload_bytes']+=len(row[2]);a['ids'].append(row[0])

    def frame(self,frame_id,host_commit_monotonic_ns,jpeg):
        if self.closed:raise RuntimeError('Recorder closed')
        t=host_commit_monotonic_ns
        if not isinstance(frame_id,int) or not isinstance(t,int) or frame_id<0 or t<0:
            raise ValueError('Invalid frame identity/time')
        if self.last and (frame_id<=self.last[0] or t<=self.last[1]):
            raise ValueError('Committed frame identity/time must advance')
        data=bytes(jpeg)
        if len(data)>self.limit:raise ValueError('Frame exceeds recording memory budget')
        if not(data[:2]==b'\xff\xd8' and data[-2:]==b'\xff\xd9'):raise ValueError('Invalid JPEG boundaries')
        row=(frame_id,t,data)
        if self.active:
            try:
                if t<=self.active['deadline_ns']:self._push(row)
                if t>=self.active['deadline_ns']:self._close('post_window_elapsed',t)
            except BaseException:
                if self.active:
                    self.active['clip'].abort();self.active=None
                raise
        self.last=(frame_id,t)
        self.buffer.append(row);self.buffer_size+=len(data)
        while self.buffer and (self.buffer[0][1]<t-self.history or self.buffer_size>self.limit):
            removed=self.buffer.popleft();self.buffer_size-=len(removed[2]);self.evicted_bytes+=len(removed[2])
        self.peak_buffer_bytes=max(self.peak_buffer_bytes,self.buffer_size)

    def alarm(self,incident_id,evidence_host_monotonic_ns):
        if self.closed:raise RuntimeError('Recorder closed')
        if not isinstance(incident_id,(str,int)) or not str(incident_id):raise ValueError('Incident ID missing')
        key=str(incident_id)
        if key in self.seen:return False
        if self.active:raise RuntimeError('Another incident recording is active')
        t=evidence_host_monotonic_ns
        if not isinstance(t,int) or not self.last or t>self.last[1] or t<0:
            raise ValueError('Alarm requires a committed evidence frame timestamp')
        rows=[r for r in self.buffer if t-self.pre<=r[1]<=t+self.post]
        if not rows:raise ValueError('Alarm evidence window no longer buffered')
        self._space(sum(len(r[2]) for r in rows))
        directory=self.root/('event_'+uuid.uuid4().hex)
        clip=self.factory(directory,self.width,self.height,self.fps,incident_id=key)
        self.active=dict(clip=clip,directory=directory,incident_id=key,evidence_ns=t,
                         deadline_ns=t+self.post,payload_bytes=0,ids=[],
                         requested_start_ns=t-self.pre,first_ns=rows[0][1],
                         pre_window_truncated=self.buffer[0][1]>t-self.pre)
        try:
            for row in rows:self._push(row)
            self.seen.add(key)
            if self.last[1]>=self.active['deadline_ns']:self._close('post_window_elapsed',self.last[1])
        except BaseException:
            clip.abort();self.active=None;raise
        return True

    def _close(self,reason,observed_ns):
        a=self.active
        try:
            report=a['clip'].close()
            event=dict(state='EVENT837_FINALIZED',incident_id=a['incident_id'],
                       timestamp_basis='host_commit_CLOCK_MONOTONIC_not_camera_exposure',
                       evidence_host_monotonic_ns=a['evidence_ns'],
                       requested_start_ns=a['requested_start_ns'],requested_end_ns=a['deadline_ns'],
                       first_recorded_ns=a['first_ns'],last_recorded_ns=report['frames'][-1]['source_monotonic_ns'],
                       post_window_observed=observed_ns>=a['deadline_ns'],
                       pre_window_truncated=a['pre_window_truncated'],completion_reason=reason,
                       frame_ids=a['ids'],container_sha256=report['container_sha256'])
            path=a['directory']/'event.json'
            with path.open('x') as f:json.dump(event,f,indent=2);f.flush();os.fsync(f.fileno())
            fd=os.open(a['directory'],os.O_RDONLY|os.O_DIRECTORY)
            try:os.fsync(fd)
            finally:os.close(fd)
            self.completed.append(dict(directory=str(a['directory']),**event))
            return event
        except BaseException:
            if not a['clip'].closed:a['clip'].abort()
            raise
        finally:self.active=None

    def close(self):
        if self.closed:raise RuntimeError('Recorder closed')
        self.closed=True
        if self.active:self._close('recording_shutdown',self.last[1])
