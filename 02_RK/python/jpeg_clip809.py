"""Mux accepted JPEG frames without re-encoding; finish only after EOS and fsync.

Caller supplies committed frames in increasing identity/source-time order.
Use from a recording worker, since disk backpressure can block push().
"""
from pathlib import Path
import hashlib,json,os
import gi
gi.require_version('Gst','1.0')
from gi.repository import Gst
Gst.init(None)

class JpegClip:
    def __init__(self,directory,width,height,fps=60,incident_id=None):
        self.directory=Path(directory);self.directory.mkdir()
        self.width=width;self.height=height;self.fps=fps;self.incident_id=incident_id
        self.rows=[];self.start=None;self.closed=False
        self.partial=self.directory/'video.mkv.partial'
        self.pipeline=Gst.parse_launch('appsrc name=source block=true max-bytes=4194304 format=time ! jpegparse ! matroskamux timecodescale=1000 ! filesink name=file sync=false')
        self.source=self.pipeline.get_by_name('source')
        self.source.set_property('caps',Gst.Caps.from_string(f'image/jpeg,width={width},height={height},framerate={fps}/1'))
        self.pipeline.get_by_name('file').set_property('location',str(self.partial))
        assert self.pipeline.set_state(Gst.State.PLAYING)!=Gst.StateChangeReturn.FAILURE

    def push(self,frame_id,source_monotonic_ns,data):
        if self.closed:raise RuntimeError('Clip is closed')
        if not (data[:2]==b'\xff\xd8' and data[-2:]==b'\xff\xd9'):raise ValueError('JPEG boundary missing')
        if self.rows and (frame_id<=self.rows[-1]['frame_id'] or source_monotonic_ns<=self.rows[-1]['source_monotonic_ns']):
            raise ValueError('Frame identity and source time must advance')
        if self.start is None:self.start=source_monotonic_ns
        pts=source_monotonic_ns-self.start
        b=Gst.Buffer.new_allocate(None,len(data),None);b.fill(0,data)
        b.pts=pts;b.dts=pts;b.duration=Gst.SECOND//self.fps
        if self.source.emit('push-buffer',b)!=Gst.FlowReturn.OK:raise RuntimeError('Recording pipeline rejected frame')
        self.rows.append(dict(frame_id=frame_id,source_monotonic_ns=source_monotonic_ns,pts_ns=pts,bytes=len(data),sha256=hashlib.sha256(data).hexdigest()))

    def close(self):
        if self.closed:raise RuntimeError('Clip is already closed')
        self.closed=True
        try:
            if not self.rows:raise ValueError('Cannot finalize empty clip')
            assert self.source.emit('end-of-stream')==Gst.FlowReturn.OK
            msg=self.pipeline.get_bus().timed_pop_filtered(30*Gst.SECOND,Gst.MessageType.EOS|Gst.MessageType.ERROR)
            if msg is None:raise TimeoutError('Recording EOS timed out')
            if msg.type==Gst.MessageType.ERROR:raise RuntimeError(str(msg.parse_error()))
        finally:self.pipeline.set_state(Gst.State.NULL)
        with self.partial.open('rb') as f:os.fsync(f.fileno())
        target=self.directory/'video.mkv';self.partial.rename(target)
        report=dict(state='JPEG_CLIP809_FINALIZED',width=self.width,height=self.height,nominal_fps=self.fps,incident_id=self.incident_id,
                    frames=self.rows,container_bytes=target.stat().st_size,container_sha256=hashlib.sha256(target.read_bytes()).hexdigest())
        path=self.directory/'manifest.json'
        with path.open('x') as f:json.dump(report,f,indent=2);f.flush();os.fsync(f.fileno())
        fd=os.open(self.directory,os.O_RDONLY|os.O_DIRECTORY)
        try:os.fsync(fd)
        finally:os.close(fd)
        return report

    def abort(self):
        self.closed=True;self.pipeline.set_state(Gst.State.NULL)
        # Preserve partial output for diagnosis; never publish a complete manifest.
