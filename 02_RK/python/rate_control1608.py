"""Feedback against a hypothetical fixed-rate queue; no output shaper implied."""
import math
from rate_control1605 import Controller as Previous


class Controller(Previous):
    LOWER=.995
    UPPER=1.005

    def __init__(self,*args,**kwargs):
        super().__init__(*args,**kwargs)
        self.nominal_bytes=self.target_bytes
        self.fps=kwargs.get('fps',60)
        self.output_bytes_per_s=self.nominal_bytes*self.fps
        self.virtual_queue_bytes=0.
        self.previous_completion=None

    def observe(self,index,size,actual_quality,preprocess_mode,completed_s):
        # Validate before advancing queue accounting. Invalid metadata remains
        # fatal; it cannot be used to invent elapsed service or discard debt.
        if type(index) is not int or index!=self.last_index+1:
            raise ValueError('Frame gap: restart feedback after transport recovery')
        if type(size) is not int or not 4<=size<=self.max_frame_bytes:
            raise ValueError('Invalid completed JPEG size')
        if type(completed_s) not in (int,float) or not math.isfinite(completed_s) or completed_s<0:
            raise ValueError('Invalid board-local completion timestamp')
        if self.previous_completion is not None and completed_s<=self.previous_completion:
            raise ValueError('Non-increasing completion timestamp')
        if actual_quality not in self.qualities or type(preprocess_mode) is not int or preprocess_mode not in range(4):
            raise ValueError('Invalid committed quality or preprocessing mode')
        interval=0 if self.previous_completion is None else completed_s-self.previous_completion
        queue=max(0.,self.virtual_queue_bytes-self.output_bytes_per_s*interval)+size
        # Three nominal frames cover natural complete-JPEG burstiness. Repay
        # excess over a two-second horizon, at most 10% below the configured
        # payload target. This budget never resets at a mode change.
        excess=max(0.,queue-3*self.nominal_bytes)
        adjusted=max(self.nominal_bytes*.9,self.nominal_bytes-excess/(2*self.fps))
        self.target_bytes=adjusted
        try:
            row=super().observe(index,size,actual_quality,preprocess_mode)
        finally:
            self.target_bytes=self.nominal_bytes
        self.virtual_queue_bytes=queue;self.previous_completion=completed_s
        row.update(nominal_target_bytes=self.nominal_bytes,effective_target_bytes=adjusted,
            virtual_queue_bytes=queue,virtual_queue_delay_ms=queue/self.output_bytes_per_s*1000,
            excess_queue_bytes=excess,queue_budget_reference_bytes=3*self.nominal_bytes,
            board_completion_interval_s=interval,
            step_policy='measured_adjacent_quality_with_timestamped_queue_debt',
            hardware_shaper_implemented=False)
        return row
