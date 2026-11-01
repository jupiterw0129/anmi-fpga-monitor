"""Field compression options and DQT-verified feedback, shared by PC and RK."""
from pathlib import Path
import hashlib,json,os,struct,time

QUALITIES=(25,50,75)
TARGET_QUALITIES=(10,15,20,25,30,35,40,50,65,75)
def options(mode='quality',quality=50,target_mbps=36):
    if mode not in ('quality','target'):raise ValueError('请选择固定质量或目标码率')
    if type(quality) is not int or quality not in QUALITIES:raise ValueError('质量需选择25、50或75')
    if isinstance(target_mbps,bool) or not isinstance(target_mbps,(int,float)) or not 8<=target_mbps<=120:
        raise ValueError('目标码率范围为8..120 Mbps')
    return dict(compression=mode,jpeg_quality=quality,target_mbps=float(target_mbps))

def board_support(version,config):
    if version==0x4a505134:
        if config['compression']!='quality' or config['jpeg_quality']!=50:
            raise ValueError('当前FPGA仅支持Q50，请先恢复压缩控制版本')
    elif version!=0x4a505399:raise ValueError('未知FPGA版本')

class Observer:
    """Read the completed native slot under its publisher's shared flock."""
    def __init__(self,shared,output,generation,config):
        from rate_control1401 import Controller
        self.shared=Path(shared);self.output=Path(output);self.generation=generation
        self.config=config;self.count=0;self.total=0;self.started=None
        self.signatures=json.loads((Path(__file__).parent/'dqt1412.json').read_text())
        self.controller=Controller(config['target_mbps'],initial=config['jpeg_quality'],qualities=TARGET_QUALITIES) if config['compression']=='target' else None
        self.log=(self.output/'compression.frames.jsonl').open('x')
        self.quality=config['jpeg_quality'];self.window=[]

    def observe(self,notice,bar):
        import fcntl
        from rate_control1401 import dqt_signature
        fields=notice.split();frame,slot,size=map(int,fields[1:4]);completed=float(fields[4])
        if slot not in range(4) or not 4<=size<=1920*1080*6+65536:raise ValueError('Invalid JPEG slot notice')
        with self.shared.open('rb',buffering=0) as reader:
            fcntl.flock(reader,fcntl.LOCK_SH)
            reader.seek(slot*(1920*1080*6+65536+64));header=reader.read(64)
            identity,length=struct.unpack_from('<QQ',header,8)
            generation=struct.unpack_from('<I',header,56)[0]
            if identity!=frame or length!=size or generation!=self.generation:
                raise RuntimeError('压缩反馈未及时读取完整帧，停止并排空')
            jpeg=reader.read(size)
            if len(jpeg)!=size:raise ValueError('Truncated feedback JPEG')
            fcntl.flock(reader,fcntl.LOCK_UN)
        signature=dqt_signature(jpeg)
        if signature not in self.signatures:raise RuntimeError('未知JPEG量化表')
        actual=self.signatures[signature]
        row=self.controller.observe(frame,size,actual) if self.controller else dict(index=frame,actual_quality=actual,requested_quality=None,status='fixed_quality')
        if self.controller is None and actual!=self.config['jpeg_quality']:raise RuntimeError('输出JPEG质量与请求不一致')
        if row['requested_quality'] is not None:
            self.quality=row['requested_quality'];bar.write(0xc4,self.quality)
            if bar.read(0x1d0)!=self.quality:raise RuntimeError('FPGA拒绝压缩质量请求')
        row.update(frame_bytes=size,jpeg_sha256=hashlib.sha256(jpeg).hexdigest(),completed_s=completed)
        self.log.write(json.dumps(row)+'\n');self.log.flush()
        self.count+=1;self.total+=size
        if self.started is None:self.started=completed
        self.window.append(size)
        if len(self.window)>60:self.window.pop(0)
        latest=dict(**self.config,actual_quality=actual,requested_quality=self.quality,
                    frame_id=frame,completed_frames=self.count,jpeg_payload_mbps=sum(self.window)/len(self.window)*60*8/1e6,
                    measured_source_fps=(self.count-1)/(completed-self.started) if completed>self.started else None,
                    feedback_status=row['status'],host_ns=time.monotonic_ns(),exact_cbr=False)
        temporary=self.output/'compression.latest.tmp';temporary.write_text(json.dumps(latest))
        os.replace(temporary,self.output/'compression.latest.json')
        return latest

    def close(self):self.log.close()
