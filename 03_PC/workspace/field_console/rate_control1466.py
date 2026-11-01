"""DQT-confirmed average control with three-frame spike protection; not CBR."""
from collections import deque
import math
from rate_control1401 import dqt_signature


class Controller:
    LOWER=.95
    UPPER=1.05

    def __init__(self,target_mbps,*,fps=60,qualities=tuple(range(10,76)),initial=50,
                 window=30,dwell=60,transition_frames=8,max_frame_bytes=12*1024*1024):
        if not (math.isfinite(target_mbps) and target_mbps>0 and math.isfinite(fps) and fps>0
                and 1<=window<=dwell and transition_frames>0):
            raise ValueError('Invalid rate configuration')
        if tuple(sorted(set(qualities)))!=qualities or initial not in qualities or not all(1<=q<=100 for q in qualities):
            raise ValueError('Invalid quality range')
        self.target_bytes=target_mbps*1_000_000/8/fps
        self.qualities=qualities;self.quality=initial;self.previous_quality=initial
        self.window=deque(maxlen=window);self.dwell=dwell;self.transition=transition_frames
        self.burst=deque(maxlen=3)
        self.last_change=-dwell;self.last_index=-1;self.max_frame_bytes=max_frame_bytes

    def next_quality(self,mean,lower):
        # JPEG quantizer scale predicts a useful first step. Actual later DQT
        # and completed JPEG bytes always decide whether that step succeeded.
        scale=5000/self.quality if self.quality<50 else 200-2*self.quality
        desired_scale=max(1,scale)*mean/self.target_bytes
        estimate=5000/desired_scale if desired_scale>=100 else (200-desired_scale)/2
        candidates=[q for q in self.qualities if (q<self.quality if lower else q>self.quality)]
        return min(candidates,key=lambda q:abs(q-estimate))

    def observe(self,index,size,actual_quality):
        if type(index) is not int or index!=self.last_index+1:
            raise ValueError('Frame gap: restart feedback after transport recovery')
        if type(size) is not int or not 4<=size<=self.max_frame_bytes:
            raise ValueError('Invalid completed JPEG size')
        if actual_quality not in self.qualities:raise ValueError('Unrecognized DQT quality')
        settled=actual_quality==self.quality
        if not settled and not (0<index-self.last_change<=self.transition and actual_quality==self.previous_quality):
            raise ValueError('Requested quality not applied within allowed frame queue')
        self.last_index=index
        if settled:self.window.append(size)
        high=settled and self.window.maxlen>=3 and size>self.target_bytes*1.5
        if high:self.burst.append(size)
        else:self.burst.clear()
        burst_mean=sum(self.burst)/len(self.burst) if self.burst else None
        ready=settled and len(self.window)==self.window.maxlen
        mean=sum(self.window)/len(self.window) if self.window else None
        position=self.qualities.index(self.quality);request=None;reason=None;status='settling'
        if ready:
            status='within_band'
            if mean>self.target_bytes*self.UPPER:
                status='over_target_at_minimum' if position==0 else 'above_band'
                if position and index-self.last_change>=self.dwell:
                    request=self.next_quality(mean,True);reason='above_band'
            elif mean<self.target_bytes*self.LOWER:
                status='below_target_at_maximum' if position==len(self.qualities)-1 else 'below_band'
                if position<len(self.qualities)-1 and index-self.last_change>=self.dwell:
                    request=self.next_quality(mean,False);reason='below_band'
        # A sudden large frame must not make the mixed old/new mean request a
        # token one-Q step. Confirm three consecutive current-Q large frames,
        # then decrease using their size, including during the normal dwell.
        # Old queued DQTs never count as confirmation. Increasing Q still uses
        # the full mean window and dwell, preserving the former recovery guard.
        emergency=False
        if high:
            if len(self.burst)==3 and position and index-self.last_change>=self.transition+3:
                request=self.next_quality(burst_mean,True);reason='three_frame_spike'
                status='above_band';emergency=True
            elif len(self.burst)<3:
                request=None;reason=None
        result=dict(index=index,actual_quality=actual_quality,requested_quality=request,reason=reason,status=status,
                    mean_bytes=mean,target_bytes=self.target_bytes,window_count=len(self.window),
                    target_lower_bytes=self.target_bytes*self.LOWER,target_upper_bytes=self.target_bytes*self.UPPER,
                    quality_settled=settled,exact_cbr=False,step_policy='quantizer_scale_with_three_frame_spike',burst_count=len(self.burst),burst_mean_bytes=burst_mean,emergency_decrease=emergency)
        if request is not None:
            self.previous_quality=self.quality;self.quality=request;self.last_change=index;self.window.clear();self.burst.clear()
        return result
