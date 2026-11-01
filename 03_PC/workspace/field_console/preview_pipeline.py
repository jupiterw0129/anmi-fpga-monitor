"""Preserve preview-only capture when regenerating the field controller."""


def augment_controller(source):
    def replace(old,new):
        nonlocal source
        if source.count(old)!=1:raise ValueError('Preview controller hook changed: '+old)
        source=source.replace(old,new)
    replace("    ap.add_argument('--headless',action='store_true')",
            "    ap.add_argument('--headless',action='store_true')\n    ap.add_argument('--preview-only',action='store_true')")
    replace("    config=validate_directories(config,ROOT/'evidence')",
            "    if a.preview_only:\n"
            "        if not a.headless or a.frames>36000:raise ValueError('Preview requires headless mode and at most ten minutes')\n"
            "        output=ROOT/'evidence'/a.name\n"
            "        if output.exists() or output.parent.is_symlink():raise ValueError('Preview output already exists or is unsafe')\n"
            "        if os.statvfs(output.parent).f_bavail*os.statvfs(output.parent).f_frsize<1024**3:raise OSError('Insufficient evidence space')\n"
            "        config=dict(**config,output=str(output),preview_only=True)\n"
            "    else:config=validate_directories(config,ROOT/'evidence')")
    replace("    state['hdmi_enabled']=not a.headless",
            "    state['hdmi_enabled']=not a.headless\n    state['preview_only']=a.preview_only")
    replace("for kind in (('pose','sd') if a.headless else ('pose','overlay','sd')):",
            "for kind in (() if a.preview_only else ('pose','sd') if a.headless else ('pose','overlay','sd')):")
    replace("('--stream-rec-dma' if a.headless else '--stream-av-dma')",
            "('--stream-dma' if a.preview_only else '--stream-rec-dma' if a.headless else '--stream-av-dma')")
    replace("str(output/'record.fifo'),*([] if a.headless else [str(output/'video.fifo')])",
            "*([str(output/'record.fifo')] if not a.preview_only else []),*([] if a.headless else [str(output/'video.fifo')])")
    return source
