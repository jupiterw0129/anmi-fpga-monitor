"""Grow a finite direct event file; keep EOS/fsync publication gates."""
from pathlib import Path
import hashlib,json,os,time
from jpeg_clip809 import JpegClip as OriginalClip,Gst

class JpegClip(OriginalClip):
    def __init__(self,directory,width,height,fps=60,incident_id=None,limit_bytes=2*1024**3):
        if not 8*1024**2<=limit_bytes<=2*1024**3:raise ValueError('Invalid finite clip limit')
        self.directory=Path(directory);self.directory.mkdir()
        self.width=width;self.height=height;self.fps=fps;self.incident_id=incident_id
        self.rows=[];self.start=None;self.closed=False;self.fd=None;self.pipeline=None
        self.sink=None;self.write_error=None;self.bus=None
        self.partial=self.directory/'video.mkv.partial';self.limit_bytes=limit_bytes
        started=time.monotonic()
        try:
            self.fd=os.open(self.partial,os.O_RDWR|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
            self.initialization_seconds=time.monotonic()-started
            Gst.Plugin.load_file(str(Path(__file__).with_name('libgstdirect1749.so')))
            self.pipeline=Gst.parse_launch('appsrc name=source block=true max-bytes=4194304 format=time ! jpegparse ! matroskamux streamable=true timecodescale=1000 ! direct1749sink name=file sync=false')
            self.source=self.pipeline.get_by_name('source')
            self.source.set_property('caps',Gst.Caps.from_string(f'image/jpeg,width={width},height={height},framerate={fps}/1'))
            self.sink=self.pipeline.get_by_name('file');self.sink.set_property('fd',self.fd);self.sink.set_property('reserve',limit_bytes)
            # The error handler only wakes appsrc; state transitions stay with
            # the producer/finalizer, outside the streaming thread.
            if Gst.version()[:3]<(1,16,3):raise RuntimeError('Thread-safe bus handler teardown requires GStreamer >=1.16.3')
            self.bus=self.pipeline.get_bus();self.bus.set_sync_handler(self._on_bus,None)
            assert self.pipeline.set_state(Gst.State.PLAYING)!=Gst.StateChangeReturn.FAILURE
        except BaseException:
            if self.pipeline:self.pipeline.set_state(Gst.State.NULL)
            if self.bus:self.bus.set_sync_handler(None,None)
            if self.fd is not None:os.close(self.fd);self.fd=None
            raise

    def _on_bus(self,bus,message,unused):
        if message.type==Gst.MessageType.ERROR:
            self.write_error=str(message.parse_error())
            # Mark the failed source EOS, which broadcasts its queue condition
            # and rejects blocked/future pushes. This is not successful media
            # EOS: close() checks write_error and never publishes a clip.
            self.source.emit('end-of-stream')
        return Gst.BusSyncReply.PASS

    def _check_write(self):
        if self.write_error or (self.sink is not None and self.sink.get_property('failed')):
            raise RuntimeError('Recording pipeline failed: '+str(self.write_error or 'sticky sink write error'))

    @property
    def high_water(self):return 0 if self.sink is None else self.sink.get_property('extent')

    def push(self,*args):
        self._check_write()
        result=super().push(*args)
        self._check_write()
        return result

    def close(self):
        if self.closed:raise RuntimeError('Clip is already closed')
        self.closed=True
        try:
            self._check_write()
            if not self.rows:raise ValueError('Cannot finalize empty clip')
            assert self.source.emit('end-of-stream')==Gst.FlowReturn.OK
            msg=self.pipeline.get_bus().timed_pop_filtered(30*Gst.SECOND,Gst.MessageType.EOS|Gst.MessageType.ERROR)
            if msg is None:raise TimeoutError('Recording EOS timed out')
            if msg.type==Gst.MessageType.ERROR:raise RuntimeError(str(msg.parse_error()))
            self.pipeline.set_state(Gst.State.NULL)
            if self.write_error or (self.sink is not None and self.sink.get_property('failed')):raise RuntimeError('Aligned sink has a sticky write error')
            end=self.high_water
            if not 0<end<=self.limit_bytes:raise RuntimeError('Recording exceeded reserve or has no final extent')
            os.ftruncate(self.fd,end);os.fsync(self.fd)
        finally:
            self.pipeline.set_state(Gst.State.NULL)
            if self.bus:self.bus.set_sync_handler(None,None)
            if self.fd is not None:os.close(self.fd);self.fd=None
        target=self.directory/'video.mkv';self.partial.rename(target)
        digest=hashlib.sha256()
        with target.open('rb') as f:
            while block:=f.read(1024*1024):digest.update(block)
        report=dict(state='JPEG_CLIP809_FINALIZED',writer='buffered_sync1749',aligned_writes=self.sink.get_property('writes'),max_write_ns=self.sink.get_property('max-write-ns'),written_extent_bytes=self.high_water,
            limit_bytes=self.limit_bytes,initialization_seconds=self.initialization_seconds,preallocated=False,
            width=self.width,height=self.height,nominal_fps=self.fps,incident_id=self.incident_id,
            frames=self.rows,container_bytes=target.stat().st_size,container_sha256=digest.hexdigest())
        report.update(periodic_syncs=self.sink.get_property('syncs'),max_sync_ns=self.sink.get_property('max-sync-ns'),checkpoint_bytes=16*1024**2)
        with (self.directory/'manifest.json').open('x') as f:json.dump(report,f,indent=2);f.flush();os.fsync(f.fileno())
        fd=os.open(self.directory,os.O_RDONLY|os.O_DIRECTORY)
        try:os.fsync(fd)
        finally:os.close(fd)
        return report

    def abort(self):
        self.closed=True
        if self.pipeline:self.pipeline.set_state(Gst.State.NULL)
        if self.bus:self.bus.set_sync_handler(None,None)
        if self.fd is not None:os.close(self.fd);self.fd=None
        # The preallocated partial remains diagnostic evidence, never a finalized clip.
