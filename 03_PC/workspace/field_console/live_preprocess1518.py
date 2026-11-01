"""Runtime mode control for LPP1 hardware; called by the owning capture loop."""
import time

MARKER=0x3150504c
def supported(bar):
    return bar.read(0x204)==MARKER

def request(bar,mode):
    if type(mode) is not int or mode not in range(4):
        raise ValueError('预处理模式必须是0至3的整数')
    if not supported(bar):
        raise RuntimeError('当前FPGA不支持运行中切换，请停止后设置')
    status=bar.read(0x208)
    if not status&16:raise RuntimeError('当前链路状态不允许切换')
    if status&2:raise RuntimeError('上一次预处理切换尚未确认')
    before=bar.read(0x20c);denied=bar.read(0x21c)
    bar.write(0x200,mode)
    after=bar.read(0x20c)
    if after!=((before+1)&0xffffffff) or bar.read(0x21c)!=denied or bar.read(0x200)!=mode:
        raise RuntimeError('FPGA未接受预处理切换请求')
    return dict(sequence=after,mode=mode,requested_host_ns=time.monotonic_ns())

def acknowledge(bar,pending):
    if not supported(bar):raise RuntimeError('预处理切换期间FPGA身份发生变化')
    if bar.read(0x20c)!=pending['sequence']:raise RuntimeError('预处理请求被其他控制者覆盖')
    status=bar.read(0x208)
    if not status&4:return None
    sequence=bar.read(0x210);frame=bar.read(0x214);mode=bar.read(0x218)
    # Stable FPGA ack remains latched; check sequence/status again after reading.
    if sequence!=pending['sequence'] or bar.read(0x210)!=sequence or not bar.read(0x208)&4:
        raise RuntimeError('预处理切换回执失效')
    if mode!=pending['mode']:raise RuntimeError('预处理切换回执模式不符')
    return dict(**pending,first_wire_frame_id=frame,ack_host_ns=time.monotonic_ns(),
                committed=False,meaning='first accepted RGB frame; verify JPG2 COMMIT separately')

def committed(ack,frame_id):
    if frame_id==ack['first_wire_frame_id']:
        return dict(**{k:v for k,v in ack.items() if k!='committed'},committed=True)
    return None
