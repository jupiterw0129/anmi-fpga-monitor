"""Use the existing record-only DMA path when HDMI is disabled."""


def augment_controller(source):
    def replace(old, new):
        nonlocal source
        assert source.count(old) == 1, old
        source = source.replace(old, new)

    replace("    ap.add_argument('--preflight-only',action='store_true')",
            "    ap.add_argument('--headless',action='store_true')\n    ap.add_argument('--preflight-only',action='store_true')")
    replace("    os.mkfifo(output/'video.fifo',0o600)",
            "    if not a.headless:os.mkfifo(output/'video.fifo',0o600)")
    replace("    state['runtime_config']=config",
            "    state['runtime_config']=config\n    state['hdmi_enabled']=not a.headless")
    start = source.index('            video=subprocess.Popen(')
    end = source.index("            for kind in ('pose','overlay','sd'):", start)
    block = source[start:end]
    source = source[:start] + '            if not a.headless:\n' + ''.join('    '+line for line in block.splitlines(keepends=True)) + source[end:]
    replace("            for kind in ('pose','overlay','sd'):",
            "            for kind in (('pose','sd') if a.headless else ('pose','overlay','sd')):")
    replace("'--stream-av-dma','/dev/ANLOGIC-PCI0_c2h_0'",
            "('--stream-rec-dma' if a.headless else '--stream-av-dma'),'/dev/ANLOGIC-PCI0_c2h_0'")
    replace("str(output/'record.fifo'),str(output/'video.fifo')],stdin=subprocess.PIPE",
            "str(output/'record.fifo'),*([] if a.headless else [str(output/'video.fifo')])],stdin=subprocess.PIPE")
    replace("for kind,worker in [('video',video),*[(k,v[0]) for k,v in workers.items()]]:",
            "for kind,worker in [*([('video',video)] if video is not None else []),*[(k,v[0]) for k,v in workers.items()]]:")
    return source
