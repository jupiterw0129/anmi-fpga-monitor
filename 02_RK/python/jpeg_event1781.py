"""Wake failed alarm appsrc without changing its direct sink or mux format."""
from jpeg_event1256 import JpegClip as DirectClip, Gst


class JpegClip(DirectClip):
    def __init__(self,*args,**kwargs):
        if Gst.version()[:3]<(1,16,3):
            raise RuntimeError('Thread-safe bus handler teardown requires GStreamer >=1.16.3')
        self.bus=None
        super().__init__(*args,**kwargs)
        self.bus=self.pipeline.get_bus()
        self.bus.set_sync_handler(self._on_bus,None)

    def _on_bus(self,bus,message,unused):
        if message.type==Gst.MessageType.ERROR:
            self.write_error=str(message.parse_error())
            # Wake blocked push-buffer; the sticky error prevents publication.
            # Pipeline state changes remain on producer/finalizer threads.
            self.source.emit('end-of-stream')
        return Gst.BusSyncReply.PASS

    def _check_write(self):
        if self.write_error or self.sink.get_property('failed'):
            raise RuntimeError('Alarm recording failed: '+str(self.write_error or 'sticky write error'))

    def push(self,*args):
        self._check_write()
        result=super().push(*args)
        self._check_write()
        return result

    def close(self):
        try:
            self._check_write()
            return super().close()
        finally:
            if self.fd is not None:self.abort()
            elif self.bus:self.bus.set_sync_handler(None,None)

    def abort(self):
        try:super().abort()
        finally:
            if self.bus:self.bus.set_sync_handler(None,None)
