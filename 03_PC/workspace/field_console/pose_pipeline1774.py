"""Bound OpenCV CPU workers while overlapping decode with the unchanged NPU."""
from pose_pipeline1723 import augment_pose as original_augment

def augment_pose(source):
    source=original_augment(source)
    old='    package=check_package();runtime=RKNNLite();'
    assert source.count(old)==1
    source=source.replace(old,'    cv2.setNumThreads(2)\n    report["opencv_threads"]=cv2.getNumThreads()\n'+old)
    compile(source,'live_pose1774.py','exec')
    return source
