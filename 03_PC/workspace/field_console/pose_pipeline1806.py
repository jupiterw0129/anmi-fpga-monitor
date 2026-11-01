"""Add the measured rescue/rule overlay to the existing decode pipeline."""
from pose_pipeline1790 import augment_pose as original_augment


def augment_pose(source):
    source=original_augment(source)
    old='from pose_rknn import infer_pose'
    assert source.count(old)==1
    source=source.replace(old,'from pose_remedy1806 import infer_pose, configure_scene, VERSION as REMEDY_VERSION')
    old='        store,scene,startup=open_monitor(a.alarm_db,a.session);'
    assert source.count(old)==1
    source=source.replace(old,"        configure_scene()\n        report['pose_remedy']=dict(version=REMEDY_VERSION,files_sha256={name:hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest() for name in ('pose_remedy1806.py','pose_fall1806.py')})\n"+old)
    compile(source,'live_pose1420.py','exec')
    return source
