"""Event837 with owned circular storage and startup interrupted-write isolation."""
from event_record837 import EventRecorder
from circular_store1053 import CircularStore
from jpeg_event1781 import JpegClip

class CircularEventRecorder(EventRecorder):
    def __init__(self,root,width,height,fps=60,**limits):
        self.store=CircularStore(root,limits.get('quota_bytes',24*1024**3),limits.get('reserve_bytes',256*1024**2))
        try:
            self.startup_recovery=self.store.recover()
            super().__init__(root,width,height,fps,**limits)
            original_factory=JpegClip
            def factory(directory,*args,**kwargs):
                clip=original_factory(directory,*args,**kwargs)
                try:self.store.register(directory)
                except BaseException:clip.abort();raise
                return clip
            self.factory=factory
        except BaseException:self.store.close();raise

    def _space(self,additional):
        active=self.active
        self.store.ensure_space(additional,pending=active['payload_bytes'] if active else 0,
                                active=active['directory'] if active else None)

    def close(self):
        try:super().close()
        finally:self.store.close()
