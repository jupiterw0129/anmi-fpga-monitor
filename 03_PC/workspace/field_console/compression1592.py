"""Field compression options and DQT-verified feedback, shared by PC and RK."""
from pathlib import Path
import hashlib,json,os,struct,time

from compression1412 import options,board_support,QUALITIES
TARGET_QUALITIES=tuple(range(1,76))

class Observer:
    """Consume immutable metadata copied by the native COMMIT publisher."""
    def __init__(self,shared,output,generation,config):
        from rate_control1592 import Controller
        self.shared=Path(shared);self.output=Path(output);self.generation=generation
        self.config=config;self.count=0;self.total=0;self.started=None
        self.signatures=json.loads((Path(__file__).parent/'dqt1564.json').read_text())
        self.controller=Controller(config['target_mbps'],initial=config['jpeg_quality'],qualities=TARGET_QUALITIES) if config['compression']=='target' else None
        self.log=(self.output/'compression.frames.jsonl').open('x')
        self.quality=config['jpeg_quality'];self.window=[];self.preprocess_mode=None

    def observe(self,notice,bar,preprocess_mode):
        import math,re
        fields=notice.split()
        if len(fields)!=7 or fields[0]!='FRAME':raise ValueError('Missing native COMMIT feedback metadata')
        frame,slot,size=map(int,fields[1:4]);completed=float(fields[4])
        if slot not in range(4) or not 4<=size<=1920*1080*6+65536 or not math.isfinite(completed):
            raise ValueError('Invalid native COMMIT metadata')
        if not re.fullmatch('[0-9a-f]{64}',fields[5]) or not re.fullmatch('[0-9a-f]{260}',fields[6]):
            raise ValueError('Invalid native JPEG digest or DQT')
        if type(preprocess_mode) is not int or preprocess_mode not in range(4):raise ValueError('Invalid committed preprocessing mode')
        signature=fields[6]
        if signature not in self.signatures:raise RuntimeError('未知JPEG量化表')
        actual=self.signatures[signature]
        changed=self.preprocess_mode is not None and self.preprocess_mode!=preprocess_mode
        row=self.controller.observe(frame,size,actual,preprocess_mode) if self.controller else dict(index=frame,actual_quality=actual,requested_quality=None,status='fixed_quality',preprocess_mode=preprocess_mode,mode_changed=changed)
        if self.controller is None and actual!=self.config['jpeg_quality']:raise RuntimeError('输出JPEG质量与请求不一致')
        if row['requested_quality'] is not None:
            frontier=max(frame,bar.read(0x1d8)-1)
            self.quality=row['requested_quality'];bar.write(0xc4,self.quality)
            if bar.read(0x1d0)!=self.quality:raise RuntimeError('FPGA拒绝压缩质量请求')
            self.controller.issued_frontier(frontier)
            row['request_commit_frontier']=frontier
        row.update(frame_bytes=size,jpeg_sha256=fields[5],completed_s=completed,feedback_source='native_commit_metadata',feedback_age_ms=(time.monotonic()-completed)*1000)
        self.log.write(json.dumps(row)+'\n');self.log.flush()
        self.count+=1;self.total+=size
        if self.started is None:self.started=completed
        if changed:self.window.clear()
        self.preprocess_mode=preprocess_mode
        self.window.append(size)
        if len(self.window)>60:self.window.pop(0)
        latest=dict(**self.config,actual_quality=actual,requested_quality=self.quality,
                    frame_id=frame,completed_frames=self.count,jpeg_payload_mbps=sum(self.window)/len(self.window)*60*8/1e6,
                    measured_source_fps=(self.count-1)/(completed-self.started) if completed>self.started else None,
                    feedback_status=row['status'],host_ns=time.monotonic_ns(),exact_cbr=False,
                    rate_controller_version=1592,target_band_percent=5 if self.controller else None,
                    quality_min=1 if self.controller else self.config['jpeg_quality'],quality_max=75 if self.controller else self.config['jpeg_quality'],
                    preprocess_mode=preprocess_mode,mode_changed=changed,payload_window_frames=len(self.window),
                    mix_qualities=row.get('mix_qualities'),byte_budget_balance=row.get('byte_budget_balance'),
                    step_policy=row.get('step_policy'),control_rate_window_mbps=row.get('rate_window_mean_bytes',0)*60*8/1e6)
        temporary=self.output/'compression.latest.tmp';temporary.write_text(json.dumps(latest))
        os.replace(temporary,self.output/'compression.latest.json')
        return latest

    def close(self):self.log.close()
