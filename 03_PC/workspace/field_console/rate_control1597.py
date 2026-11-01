"""Short measured acquisition with confirmed-response spike control; not CBR."""
from collections import deque
from rate_control1585 import Controller as Previous


class Controller(Previous):
    def __init__(self,*args,**kwargs):
        kwargs.setdefault('window',6)
        kwargs.setdefault('dwell',8)
        super().__init__(*args,**kwargs)
        self.samples={}
        self.mixture=None
        self.balance=0.
        self.rate_window=deque(maxlen=60)
        self.confirmed=True

    def _plan(self,mean,lower):
        # Measurements are local to one committed mode and expire after six
        # seconds. Never retain a bracket across a preprocessing switch.
        self.samples={q:v for q,v in self.samples.items() if self.last_index-v[1]<=360}
        lows=[q for q,(v,_) in self.samples.items() if v<self.target_bytes*self.LOWER]
        highs=[q for q,(v,_) in self.samples.items() if v>self.target_bytes*self.UPPER]
        pairs=[(a,b) for a in lows for b in highs if a<b]
        if pairs:
            a,b=min(pairs,key=lambda p:p[1]-p[0])
            ia,ib=self.qualities.index(a),self.qualities.index(b)
            if ib-ia==1:
                self.mixture=(a,b)
                self.balance=0.
                return b if mean<self.target_bytes else a
            # Probe inside the observed bracket before assuming the quantizer
            # scale predicts bytes across a Huffman table discontinuity.
            return self.qualities[(ia+ib)//2]
        return super().next_quality(mean,lower)

    def observe(self,index,size,actual_quality,preprocess_mode):
        if type(index) is not int or index!=self.last_index+1:
            raise ValueError('Frame gap: restart feedback after transport recovery')
        if type(size) is not int or not 4<=size<=self.max_frame_bytes:
            raise ValueError('Invalid completed JPEG size')
        if actual_quality not in self.qualities:
            raise ValueError('Unrecognized DQT quality')
        if type(preprocess_mode) is not int or preprocess_mode not in range(4):
            raise ValueError('Invalid committed preprocessing mode')
        settled=actual_quality==self.quality
        if not settled and not (not self.confirmed and actual_quality==self.previous_quality
                                and index<=self.last_change+self.transition):
            raise ValueError('Requested quality not applied within allowed frame queue')
        if settled:self.confirmed=True
        changed=self.preprocess_mode is not None and self.preprocess_mode!=preprocess_mode
        if changed:
            self.window.clear();self.burst.clear();self.rate_window.clear()
            self.samples.clear();self.mixture=None;self.balance=0.
        self.preprocess_mode=preprocess_mode;self.last_index=index
        self.rate_window.append(size)
        if settled:self.window.append(size)
        high=settled and size>self.target_bytes*1.5
        if high:self.burst.append(size)
        else:self.burst.clear()
        ready=settled and len(self.window)==self.window.maxlen
        mean=sum(self.window)/len(self.window) if self.window else None
        burst_mean=sum(self.burst)/len(self.burst) if self.burst else None
        request=None;reason=None;status='settling';emergency=False
        position=self.qualities.index(self.quality)
        if self.mixture:
            # Integrate actual bytes, including queued old-quality frames.
            # One request must be confirmed before another can be issued.
            self.balance+=self.target_bytes-size
            previous=self.samples[actual_quality][0] if actual_quality in self.samples else size
            self.samples[actual_quality]=(previous*.875+size*.125,index)
            lo,hi=self.mixture
            low_mean=self.samples[lo][0];high_mean=self.samples[hi][0]
            if low_mean>self.target_bytes*self.UPPER or high_mean<self.target_bytes*self.LOWER:
                # A changed scene invalidates the old pair; acquire a fresh
                # bracket rather than mixing qualities measured elsewhere.
                self.mixture=None;self.samples.clear();self.balance=0.
                self.window.clear();self.burst.clear();ready=False
                status='reacquiring_after_scene_change'
            else:
                wanted=hi if self.balance>0 else lo
                if settled and wanted!=self.quality:
                    request=wanted;reason='measured_pair_byte_budget'
                rate_mean=sum(self.rate_window)/len(self.rate_window)
                status=('within_band' if len(self.rate_window)==self.rate_window.maxlen
                        and self.target_bytes*self.LOWER<=rate_mean<=self.target_bytes*self.UPPER
                        else 'mixing_toward_band')
        if not self.mixture:
            if ready:
                self.samples[actual_quality]=(mean,index)
                status='within_band'
                if mean>self.target_bytes*self.UPPER:
                    status='over_target_at_minimum' if position==0 else 'above_band'
                    if position and index-self.last_change>=self.dwell:
                        request=self._plan(mean,True);reason='measured_bracket_above_band'
                elif mean<self.target_bytes*self.LOWER:
                    status='below_target_at_maximum' if position==len(self.qualities)-1 else 'below_band'
                    if position<len(self.qualities)-1 and index-self.last_change>=self.dwell:
                        request=self._plan(mean,False);reason='measured_bracket_below_band'
            if high:
                if len(self.burst)==3 and position and self.confirmed:
                    request=super().next_quality(burst_mean,True)
                    reason='three_frame_spike';status='above_band';emergency=True
                elif len(self.burst)<3:request=None;reason=None
        if request==self.quality:request=None;reason=None
        result=dict(index=index,actual_quality=actual_quality,requested_quality=request,reason=reason,status=status,
            mean_bytes=mean,target_bytes=self.target_bytes,window_count=len(self.window),
            target_lower_bytes=self.target_bytes*self.LOWER,target_upper_bytes=self.target_bytes*self.UPPER,
            quality_settled=settled,exact_cbr=False,step_policy='six_frame_bracket_and_confirmed_response_byte_budget',
            burst_count=len(self.burst),burst_mean_bytes=burst_mean,emergency_decrease=emergency,
            preprocess_mode=preprocess_mode,mode_changed=changed,command_commit_frontier=self.last_change,
            mix_qualities=list(self.mixture) if self.mixture else None,
            byte_budget_balance=self.balance if self.mixture else None,
            rate_window_count=len(self.rate_window),rate_window_mean_bytes=sum(self.rate_window)/len(self.rate_window))
        if request is not None:
            self.previous_quality=self.quality;self.quality=request;self.last_change=index
            self.confirmed=False;self.window.clear();self.burst.clear()
        return result
