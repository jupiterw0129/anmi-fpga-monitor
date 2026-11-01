"""Add explicit profile guards and completed-JPEG feedback to generated controller."""
def augment(text):
    def edit(before,after):
        nonlocal text
        assert text.count(before)==1,(before,text.count(before))
        text=text.replace(before,after)
    edit('import signal\n','import signal\nfrom compression1412 import options,board_support,Observer\n')
    start=text.index('def identity(b):');end=text.index('\ndef wait(',start)
    text=text[:start]+'''def identity(b):
    version=b.read(0x5c)
    if version not in (0x4a505134,0x4a505399):raise RuntimeError('Unknown FPGA profile')
    expected={0x1c0:0x3247504a,0x1c4:0x10000,0x1c8:15 if version==0x4a505134 else 31,0x1ec:1,0x1f0:1}
    for a,value in expected.items():
        if b.read(a)!=value:raise RuntimeError('JPG2 capability mismatch')
    if (version==0x4a505134 and b.read(0x1d0)!=50) or not 1<=b.read(0x1d0)<=100:
        raise RuntimeError('Unexpected JPEG quality')
''' +text[end:]
    edit("if registers['0x5c'] != 0x4a505134:","if registers['0x5c'] not in (0x4a505134,0x4a505399):")
    edit("    ap.add_argument('--recordings',required=True)","    ap.add_argument('--compression',choices=('quality','target'),default='quality')\n    ap.add_argument('--jpeg-quality',type=int,choices=(25,50,75),default=50)\n    ap.add_argument('--target-mbps',type=float,default=36)\n    ap.add_argument('--recordings',required=True)")
    edit("binding=json.loads((ROOT/'binding_field1382.json').read_text())","""with RESOURCE.open('rb',buffering=0) as fd,mmap.mmap(fd.fileno(),4096,access=mmap.ACCESS_READ) as view:
        version=struct.unpack_from('<I',view,0x5c)[0]
    compression=options(a.compression,a.jpeg_quality,a.target_mbps)
    board_support(version,compression)
    binding=json.loads((ROOT/('binding_quality1412.json' if version==0x4a505399 else 'binding_field1382.json')).read_text())""")
    edit('    workers={};video=None;', '    observer=None\n    workers={};video=None;')
    edit("        state['prepared']=snap(b)","        if version==0x4a505399:\n            b.write(0xc4,a.jpeg_quality);wait(b,0x1d0,a.jpeg_quality)\n        state['compression_config']=compression\n        state['prepared']=snap(b)")
    edit("str(ROOT/'reliable1326/publish1332')","str(Path('/userdata/quality1403_20261029/native/publish1403') if version==0x4a505399 else ROOT/'reliable1326/publish1332')")
    diagnostic_start=text.index('            import read_diag902\n')
    diagnostic_end=text.index('            wait(b,0xd0',diagnostic_start)
    text=text[:diagnostic_start]+"            # Consume FRAME notices immediately; delayed diagnostics would overwrite feedback slots.\n            state['raw_snapshot_deferred_for_frame_feedback']=True\n"+text[diagnostic_end:]
    edit("            state['consumer_exits']=[]","            observer=Observer(shared,output,generation,compression)\n            state['consumer_exits']=[]")
    edit("                if notice.startswith('FRAME '):frames.append(notice)","                if notice.startswith('FRAME '):\n                    frames.append(notice);observer.observe(notice,b)")
    edit("    finally:\n        try:","    finally:\n        if observer is not None:observer.close()\n        try:")
    edit("                idle(b)\n            state['cleanup_verified']", "                if version==0x4a505399:b.write(0xc4,50);wait(b,0x1d0,50)\n                idle(b)\n            state['cleanup_verified']")
    return text
