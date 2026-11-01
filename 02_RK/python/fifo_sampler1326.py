"""Sequential JPEG recorder input; no dependence on overwritable display slots."""
from collections import deque
import math,os,select,stat,struct,threading,time
HEADER=struct.Struct('<8sQQdQQIIII')
CAP=1920*1080*6+65536
class Cancelled(Exception):pass

class FifoSampler:
    def __init__(self,path,generation,limit=16*1024**2):
        st=os.lstat(path)
        if not stat.S_ISFIFO(st.st_mode) or st.st_uid!=os.getuid() or stat.S_IMODE(st.st_mode)!=0o600:
            raise ValueError('Recorder FIFO identity/permissions mismatch')
        if limit<CAP:raise ValueError('Recorder queue must fit one maximum frame')
        self.fd=os.open(path,os.O_RDONLY|os.O_NONBLOCK|os.O_NOFOLLOW)
        self.generation=generation;self.limit=limit;self.bytes=0;self.peak_bytes=0
        self.last=None;self.last_ns=None;self.pending=deque();self.lock=threading.Condition()
        self.stop_event=threading.Event();self.eof=threading.Event();self.error=None
        self.stats=dict(frames_copied=0,frame_id_gaps=0,slot_lock_busy=0,queue_overflow_frames=0,
            reordered_frames=0,reorder_peak_frames=0,queue_backpressure_waits=0,transport='reliable_fifo1326')
        self.thread=threading.Thread(target=self._run,name='JPEG-fifo1326',daemon=True)
    def start(self):self.thread.start()
    def _exact(self,size,allow_eof=False):
        parts=[];got=0;deadline=time.monotonic()+(120 if self.last is None else 15)
        while got<size:
            if self.stop_event.is_set():raise Cancelled()
            if time.monotonic()>deadline:raise TimeoutError('Recorder FIFO read deadline')
            if not select.select([self.fd],[],[],.05)[0]:continue
            data=os.read(self.fd,size-got)
            if not data:
                if self.last is None and not got:
                    self.stop_event.wait(.01);continue
                if allow_eof and got==0:return None
                raise EOFError('Truncated recorder FIFO frame')
            parts.append(data);got+=len(data)
        return b''.join(parts)
    def _run(self):
        try:
            while True:
                raw=self._exact(64,True)
                if raw is None:self.eof.set();return
                magic,frame,length,completed,packets,encoded,w,h,generation,flags=HEADER.unpack(raw)
                if magic!=b'JPGS755\0' or generation!=self.generation or flags!=1 or not 0<length<=CAP or length!=encoded or (w,h)!=(1920,1080) or packets<=0 or not math.isfinite(completed) or completed<=0:
                    raise ValueError('Recorder FIFO frame metadata mismatch')
                expected=0 if self.last is None else self.last+1
                if frame!=expected:
                    self.stats['frame_id_gaps']+=1;raise ValueError(f'Recorder FIFO sequence gap: expected {expected}, got {frame}')
                ns=round(completed*1e9)
                if self.last_ns is not None and ns<=self.last_ns:raise ValueError('Recorder FIFO nonmonotonic completion time')
                data=self._exact(length)
                if data[:2]!=b'\xff\xd8' or data[-2:]!=b'\xff\xd9':raise ValueError('Recorder FIFO JPEG boundary mismatch')
                with self.lock:
                    while self.bytes+length>self.limit:
                        if self.stop_event.is_set():raise Cancelled()
                        self.stats['queue_backpressure_waits']+=1;self.lock.wait(.05)
                    self.pending.append((frame,ns,data));self.bytes+=length
                    self.peak_bytes=max(self.peak_bytes,self.bytes);self.stats['frames_copied']+=1
                self.last=frame;self.last_ns=ns
        except Cancelled:pass
        except BaseException as error:self.error=error
    def take(self):
        if self.error:raise self.error
        with self.lock:
            rows=list(self.pending);self.pending.clear();self.bytes=0;self.lock.notify_all()
        return rows
    def stop(self):
        self.thread.join(5)
        if self.thread.is_alive():raise TimeoutError('Recorder FIFO thread did not reach EOF')
        if self.error:raise self.error
        if not self.eof.is_set():raise RuntimeError('Recorder FIFO stopped without clean EOF')
    def close(self):
        self.stop_event.set()
        with self.lock:self.lock.notify_all()
        self.thread.join(5)
        if self.thread.is_alive():raise TimeoutError('Recorder FIFO thread cleanup timeout')
        os.close(self.fd)
