"""Mode-local feedback windows, retaining the DQT and queue guards of 1466."""
from rate_control1466 import Controller as Previous


class Controller(Previous):
    def __init__(self,*args,**kwargs):
        super().__init__(*args,**kwargs)
        self.preprocess_mode=None

    def observe(self,index,size,actual_quality,preprocess_mode):
        if type(preprocess_mode) is not int or preprocess_mode not in range(4):
            raise ValueError('Invalid committed preprocessing mode')
        changed=self.preprocess_mode is not None and self.preprocess_mode!=preprocess_mode
        if changed:
            self.window.clear();self.burst.clear()
        # Do not reset last_index, requested/previous quality or last_change:
        # changing modes cannot excuse a missing frame or a late old DQT.
        row=super().observe(index,size,actual_quality)
        self.preprocess_mode=preprocess_mode
        row.update(preprocess_mode=preprocess_mode,mode_changed=changed)
        return row
