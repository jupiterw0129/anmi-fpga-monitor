"""Isolated preview sender: bounded batched writes and early graceful stop."""


def augment_controller(source):
    def replace(old,new):
        nonlocal source
        if source.count(old)!=1:raise ValueError('Preview transport hook changed: '+old)
        source=source.replace(old,new)
    replace("str(Path('/userdata/feedback1585_20261029/native/publish1585') if version==0x4a505399 else ROOT/'reliable1326/publish1332')",
            "str(Path('/userdata/preview_transport_fix_20261031/native/publish_preview') if a.preview_only and version==0x4a505399 else Path('/userdata/feedback1585_20261029/native/publish1585') if version==0x4a505399 else ROOT/'reliable1326/publish1332')")
    replace("                if notice.startswith('FRAME '):",
            "                if notice=='PRESSURE wire' and a.preview_only:\n"
            "                    state['transport_pressure']=True\n"
            "                    if not quiescing:\n"
            "                        state['operator_stop']=True;state['stop_reason']='wire_queue_pressure'\n"
            "                        request_stop1025(b,p,state);quiescing=True\n"
            "                elif notice.startswith('FRAME '):")
    replace("        if state['consumer_exits']:state['error']='Consumer exited during capture; early drain completed'",
            "        if state['consumer_exits']:state['error']='Consumer exited during capture; early drain completed'\n"
            "        if state.get('transport_pressure'):\n"
            "            state.update(state='FAILED',error='PC预览发送队列接近上限，已提前停止并排空；请检查串流处理与网络负载')")
    return source
