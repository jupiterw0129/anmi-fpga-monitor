"""Stage bounded sequential diagnostic recording without changing alarm media."""
from pathlib import Path

def sources(root):
    candidate=root.parent/'artifacts/pose_pipeline1722_20261030'
    backup=candidate/'backup/board'
    result={
        'segment_store1752.py':(candidate/'candidate1749/segment_store1277.py').read_text(),
        'jpeg_event1752.py':(candidate/'candidate1749/jpeg_event1256.py').read_text(),
        'segment_record1752.py':(backup/'segment_record1277.py').read_text().replace('from jpeg_event1256 import','from jpeg_event1752 import').replace('from segment_store1277 import','from segment_store1752 import'),
        'segment_worker1752.py':(backup/'segment_worker1277.py').read_text().replace('from segment_record1277 import','from segment_record1752 import'),
        'live_record1752.py':(backup/'reliable1326/live_record1328.py').read_text().replace('from segment_worker1277 import','from segment_worker1752 import'),
    }
    old="        report.update(state='FAILED',error=repr(e))\n        if clip:\n"
    new="""        report.update(state='FAILED',error=repr(e))
        if clip:
            report.update(segment_worker=clip.stats,segment_pending_bytes=clip.pending_bytes,
                segment_finalizer=clip.finalize_stats)
        if clip:
"""
    assert result['live_record1752.py'].count(old)==1
    result['live_record1752.py']=result['live_record1752.py'].replace(old,new)
    result['live_record1752.py']=result['live_record1752.py'].replace("sys.path.insert(0,'/userdata/native_required1138_20261028')", "sys.path.insert(0,'/userdata/native_required1138_20261028')\nsys.path.append('/userdata/native_required1138_20261028/reliable1326')",1)
    for name,text in result.items():
        compile(text,name,'exec');(root/name).write_text(text,encoding='utf-8')
    if not (root/'libgstdirect1749.so').is_file():raise FileNotFoundError('Validated sink1749 binary missing')
    return (*result,'libgstdirect1749.so')

def augment_controller(text):
    old="'reliable1326/live_record1328.py'"
    assert text.count(old)==1
    return text.replace(old,"'live_record1752.py'")
