"""Preserve source diagnostics before cleanup resets the receiver evidence."""


def capture(state,bar):
    registers=state.get('fault_registers',{})
    if not registers.get('0x1e0'):return
    from preprocess_runtime1520 import source_verdict_reason
    reason=source_verdict_reason(registers.get('0x134',0))
    state['source_failure']=reason
    state['original_error']=state.get('error')
    state['error']='FPGA源帧中止：'+str(reason['source_verdict_reason'] or 'unknown')+'；已停止本次测试，保留故障诊断'
    try:
        state['source_raster_at_fault']={hex(x):bar.read(x) for x in range(0x140,0x164,4)}
        import read_diag902
        read_diag902.VERSION=bar.read(0x5c)
        state['source_byte_snapshot_at_fault']=read_diag902.collect(bar.read,bar.write)
    except Exception as error:state['source_snapshot_error']=repr(error)


def augment_controller(source):
    old="        state['error']=repr(e);state['fault_registers']=snap(b)"
    if source.count(old)!=1:raise ValueError('Source failure diagnostic hook changed')
    return source.replace(old,old+"\n        from source_fault_diagnostics import capture\n        capture(state,b)")
