"""Single-owner mode requests and per-COMMIT provenance for field recordings."""
from pathlib import Path
import json,os,re,time
from live_preprocess1518 import supported,request,acknowledge
from threshold1786 import options as threshold_options,verify_active


def source_verdict_reason(code):
    """Old bitstreams leave these reserved bits zero; never infer a cause."""
    reason=(code>>9)&15 if code&32 else None
    names={0:'unknown_or_unavailable',1:'decoder_abort',2:'missing_frame_end',
           3:'invalid_geometry_config',4:'sof_mismatch',5:'line_length_mismatch',
           6:'too_many_lines',7:'short_frame'}
    return dict(source_verdict_reason_code=reason,
                source_verdict_reason=names.get(reason,'unknown_reason') if reason is not None else None)

def atomic(path,value):
    temporary=path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value,ensure_ascii=False),encoding='utf-8')
    os.replace(temporary,path)

class RuntimeModes:
    def __init__(self,bar,output,inbox,initial_mode,binary_threshold=None):
        self.bar=bar;self.output=Path(output);self.inbox=Path(inbox)
        self.supported=supported(bar);self.initial=initial_mode;self.pending=None
        self.advanced=threshold_options(binary_threshold)
        self.last_request=None;self.transitions=[];self.last_frame=None
        self.events=(self.output/'preprocess.events.jsonl').open('x',encoding='utf-8')
        self.frames=(self.output/'preprocess.frames.jsonl').open('x',encoding='utf-8')
        self.latest=dict(supported=self.supported,phase='idle' if self.supported else 'unsupported',
                         actual_mode=initial_mode,request_id=None,initial_mode=initial_mode,advanced_config=self.advanced)
        self.publish()

    def publish(self):
        self.latest['board_monotonic_ns']=time.monotonic_ns()
        atomic(self.output/'preprocess.latest.json',self.latest)

    def event(self,kind,**values):
        self.events.write(json.dumps(dict(kind=kind,board_monotonic_ns=time.monotonic_ns(),**values))+'\n');self.events.flush()

    def poll(self):
        path=self.inbox/'preprocess.request.json'
        if self.pending is None and path.exists():
            command=json.loads(path.read_text(encoding='utf-8'));key=command.get('request_id')
            if key!=self.last_request:
                if not isinstance(key,str) or not re.fullmatch('[0-9a-f]{32}',key):raise ValueError('Invalid preprocessing request identity')
                self.last_request=key
                pending=request(self.bar,command.get('mode'))
                self.pending=dict(**pending,request_id=key,ack=None)
                self.latest.update(phase='pending',request_id=key,requested_mode=pending['mode'],sequence=pending['sequence'])
                self.event('request',**pending,request_id=key);self.publish()
        if self.pending:
            pending=self.pending
            if pending['ack'] is None:
                ack=acknowledge(self.bar,{k:pending[k] for k in ('sequence','mode','requested_host_ns')})
                if ack:
                    if self.last_frame is not None and ack['first_wire_frame_id']<=self.last_frame:
                        raise RuntimeError('模式回执晚于已记录帧，停止以免错误标注录像')
                    pending['ack']=ack;self.transitions.append(ack)
                    self.latest.update(phase='awaiting_commit',first_wire_frame_id=ack['first_wire_frame_id'])
                    self.event('rgb_accepted',**ack,request_id=pending['request_id']);self.publish()
            if time.monotonic_ns()-pending['requested_host_ns']>2_000_000_000:
                raise TimeoutError('预处理切换两秒内未提交完整帧')
        if time.monotonic_ns()-self.latest['board_monotonic_ns']>500_000_000:self.publish()

    def observe(self,frame):
        self.poll()
        if type(frame) is not int or (self.last_frame is not None and frame!=self.last_frame+1):
            raise RuntimeError('预处理逐帧记录序号不连续')
        mode=self.initial
        for transition in self.transitions:
            if frame>=transition['first_wire_frame_id']:mode=transition['mode']
        active=verify_active(self.bar,self.advanced)
        row=dict(frame_id=frame,mode=mode,committed=True,**self.advanced,
                 advanced_active_readback=active,advanced_verified=True)
        self.frames.write(json.dumps(row)+'\n');self.frames.flush();self.last_frame=frame
        if self.pending and self.pending['ack']:
            ack=self.pending['ack']
            if frame==ack['first_wire_frame_id']:
                self.event('committed',**row,sequence=ack['sequence'],request_id=self.pending['request_id'])
                self.latest.update(phase='applied',actual_mode=mode,first_wire_frame_id=frame)
                self.pending=None;self.publish()
            elif frame>ack['first_wire_frame_id']:raise RuntimeError('切换帧没有提交')
        return row

    def close(self):
        try:
            if self.pending:
                self.latest.update(phase='cancelled',error='会话结束前尚未确认切换帧提交')
                self.publish()
        finally:self.events.close();self.frames.close()

def augment(source):
    compression_module=next((name for name in ('compression1564','compression1558','compression1466') if 'from '+name+' import Observer' in source),'compression1466')
    replacements=[
        ('from '+compression_module+' import Observer','from '+compression_module+' import Observer\nfrom preprocess_runtime1520 import RuntimeModes,source_verdict_reason'),
        ('return dict(cause_bits=code&511,group_index=code>>13,',
         'return dict(**source_verdict_reason(code),cause_bits=code&511,group_index=code>>13,'),
        ('    observer=None','    observer=None\n    runtime_modes=None'),
        ("    elif notice=='FAULT':state['hardware_fault_before_drain']=snap(b)",
         "    elif notice=='FAULT':\n        state['hardware_fault_before_drain']=snap(b)\n        try:\n            state['source_raster_at_fault']={hex(x):b.read(x) for x in range(0x140,0x164,4)}\n            import read_diag902\n            read_diag902.VERSION=b.read(0x5c)\n            state['source_byte_snapshot_at_fault']=read_diag902.collect(b.read,b.write)\n        except BaseException as error:state['source_snapshot_error']=repr(error)"),
        ('            observer=Observer(shared,output,generation,compression)',
         "            observer=Observer(shared,output,generation,compression)\n            runtime_modes=RuntimeModes(b,output,ROOT/'field1382'/a.name,a.preprocess)"),
        ('                notice=line(p,tick=observe_consumers);','                if not quiescing:runtime_modes.poll()\n                notice=line(p,tick=observe_consumers);'),
        ('                    frames.append(notice);observer.observe(notice,b)',
         ('                    frames.append(notice)\n                    mode_row=runtime_modes.observe(int(notice.split()[1]))\n                    observer.observe(notice,b,mode_row[\'mode\'])' if compression_module!='compression1466' else
          '                    frames.append(notice);observer.observe(notice,b)\n                    runtime_modes.observe(int(notice.split()[1]))')),
        ('        if observer is not None:observer.close()',
         "        if runtime_modes is not None:\n            try:\n                runtime_modes.close();state['runtime_preprocess']=runtime_modes.latest\n            except BaseException as error:\n                state.update(state='FAILED',error='Preprocess journal finalization: '+repr(error))\n        if observer is not None:observer.close()"),
    ]
    for old,new in replacements:
        if source.count(old)!=1:raise ValueError('Capture controller hook changed: '+old)
        source=source.replace(old,new)
    return source
