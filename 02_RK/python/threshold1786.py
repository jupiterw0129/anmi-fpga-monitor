"""Static FPGA binary threshold profile; changes apply on the next session."""
def options(value=None):
    if value is not None and (type(value) is not int or not 0<=value<=255):
        raise ValueError('二值化阈值必须为0～255的整数')
    return dict(advanced_mode=0 if value is None else 2,
                advanced_threshold=128 if value is None else value)


def control_word(preprocess,bayer_phase,value=None):
    config=options(value)
    return config['advanced_threshold']<<8 | bayer_phase<<4 | preprocess<<2 | config['advanced_mode']


def verify_active(bar,config):
    value=bar.read(0xd0)
    expected=config['advanced_threshold']<<8 | config['advanced_mode']
    if value&0xff03!=expected:
        raise RuntimeError(f'FPGA二值化配置未生效或在采集中改变：实际0x{value:08x}，期望掩码值0x{expected:04x}')
    return value


def audit_rows(records,remote):
    from evaluate_field1416 import require
    present=any('advanced_verified' in row for row in records)
    declared='advanced_config' in remote or 'binary_threshold' in remote
    if not present and not declared:return None
    expected=options(remote.get('binary_threshold'))
    require(remote.get('advanced_config')==expected,'高级预处理配置与会话报告不一致')
    for row in records:
        active=row.get('advanced_active_readback')
        require(row.get('advanced_verified') is True and
                all(type(row.get(k)) is int and row[k]==v for k,v in expected.items()) and
                type(active) is int and active&0xff03==expected['advanced_threshold']<<8|expected['advanced_mode'],
                '高级预处理逐帧配置或实际寄存器记录不一致')
    return dict(**expected,source_frames_verified=len(records),
                name='关闭' if expected['advanced_mode']==0 else '阈值二值化',
                scope='按源帧完成时实际寄存器核验；整段静态配置，作用于录像和模型输入')


def augment_controller(text):
    edits=[
        ('import signal\n','import signal\nfrom threshold1786 import options as threshold_options,control_word\n'),
        ("    ap.add_argument('--recordings',required=True)","    ap.add_argument('--binary-threshold',type=int,choices=range(256))\n    ap.add_argument('--recordings',required=True)"),
        ('    config=plan(a.name,a.frames,a.recordings)', '    config=plan(a.name,a.frames,a.recordings)\n    advanced_config=threshold_options(a.binary_threshold)'),
        ('0x8000 | (a.preprocess<<2) | (a.bayer_phase<<4)','control_word(a.preprocess,a.bayer_phase,a.binary_threshold)'),
        ("        state['compression_config']=compression", "        state['advanced_config']=advanced_config\n        state['compression_config']=compression"),
        ("RuntimeModes(b,output,ROOT/'field1382'/a.name,a.preprocess)","RuntimeModes(b,output,ROOT/'field1382'/a.name,a.preprocess,a.binary_threshold)"),
    ]
    for before,after in edits:
        assert text.count(before)==1,(before,text.count(before))
        text=text.replace(before,after)
    return text
