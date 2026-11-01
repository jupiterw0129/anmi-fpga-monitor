"""Target average JPEG payload rate feedback; does not promise exact CBR.

Only completed, DQT-verified frames enter feedback. A request affects later
frames; up to eight frames may retain the preceding Q. No frame dropping or
padding is hidden in this controller. Field use requires pose accuracy checks.
"""
from collections import deque

def dqt_signature(jpeg):
    if jpeg[:2]!=b'\xff\xd8':raise ValueError('Missing JPEG SOI')
    pos=2;tables={}
    while pos<len(jpeg):
        if jpeg[pos]!=255:raise ValueError('Malformed JPEG header')
        while pos<len(jpeg) and jpeg[pos]==255:pos+=1
        if pos>=len(jpeg):raise ValueError('Truncated marker')
        marker=jpeg[pos];pos+=1
        if marker==0xda:break
        if marker in (0xd8,0xd9,0x01) or 0xd0<=marker<=0xd7:continue
        length=int.from_bytes(jpeg[pos:pos+2],'big')
        if length<2 or pos+length>len(jpeg):raise ValueError('Truncated segment')
        payload=jpeg[pos+2:pos+length];pos+=length
        if marker==0xdb:
            offset=0
            while offset<len(payload):
                info=payload[offset];offset+=1
                if info>>4:raise ValueError('Only 8-bit DQT supported')
                if offset+64>len(payload) or (info&15) in tables:raise ValueError('Invalid DQT')
                tables[info&15]=payload[offset:offset+64];offset+=64
    if set(tables)!={0,1}:raise ValueError('Missing JPEG quantization tables')
    return b''.join(bytes([key])+tables[key] for key in sorted(tables)).hex()

class Controller:
    def __init__(self,target_mbps,*,fps=60,qualities=(25,50,75),initial=50,
                 window=30,dwell=60,transition_frames=8,max_frame_bytes=12*1024*1024):
        if not (target_mbps>0 and fps>0 and 1<=window<=dwell and transition_frames>0):
            raise ValueError('Invalid rate configuration')
        if tuple(sorted(set(qualities)))!=qualities or initial not in qualities or not all(1<=q<=100 for q in qualities):
            raise ValueError('Invalid quality range')
        self.target_bytes=target_mbps*1_000_000/8/fps
        self.qualities=qualities;self.quality=initial;self.previous_quality=initial
        self.window=deque(maxlen=window);self.dwell=dwell;self.transition=transition_frames
        self.last_change=-dwell;self.last_index=-1;self.max_frame_bytes=max_frame_bytes

    def observe(self,index,size,actual_quality):
        if type(index) is not int or index!=self.last_index+1:raise ValueError('Frame gap: restart feedback after transport recovery')
        if type(size) is not int or not 4<=size<=self.max_frame_bytes:raise ValueError('Invalid completed JPEG size')
        if actual_quality not in self.qualities:raise ValueError('Unrecognized DQT quality')
        settled=actual_quality==self.quality
        if not settled and not (0<index-self.last_change<=self.transition and actual_quality==self.previous_quality):
            raise ValueError('Requested quality not applied within allowed frame queue')
        self.last_index=index
        if settled:self.window.append(size)
        ready=settled and len(self.window)==self.window.maxlen
        mean=sum(self.window)/len(self.window) if self.window else None
        position=self.qualities.index(self.quality);request=None;reason=None;status='settling'
        if ready:
            status='within_band'
            if mean>self.target_bytes*1.1:
                status='over_target_at_minimum' if position==0 else 'above_band'
                if position and index-self.last_change>=self.dwell:request=self.qualities[position-1];reason='above_band'
            elif mean<self.target_bytes*.8:
                status='below_target_at_maximum' if position==len(self.qualities)-1 else 'below_band'
                if position<len(self.qualities)-1 and index-self.last_change>=self.dwell:request=self.qualities[position+1];reason='below_band'
        result=dict(index=index,actual_quality=actual_quality,requested_quality=request,
                    reason=reason,status=status,mean_bytes=mean,target_bytes=self.target_bytes,
                    window_count=len(self.window),quality_settled=settled,exact_cbr=False)
        if request is not None:
            self.previous_quality=self.quality;self.quality=request;self.last_change=index;self.window.clear()
        return result
