"""Conditional upside-down person rescue; frozen model/package stay unchanged."""
import copy
import time

VERSION='pose-remedy1806'


def restore180(people,width,height):
    restored=copy.deepcopy(people)
    for person in restored:
        x1,y1,x2,y2=person['box_xyxy']
        # 两角恢复后交换次序；关键点只变换坐标，置信度保持原值。
        person['box_xyxy']=[width-1-x2,height-1-y2,width-1-x1,height-1-y1]
        person['keypoints_xyc']=[[width-1-x,height-1-y,c] for x,y,c in person['keypoints_xyc']]
    return restored


def infer_pose(runtime,image,confidence=0.5,clock=time.perf_counter,primary=None,rotate=None):
    if primary is None:
        from pose_rknn import infer_pose as primary
    if rotate is None:
        import cv2
        rotate=lambda image:cv2.rotate(image,cv2.ROTATE_180)
    people,timing=primary(runtime,image,confidence=confidence,clock=clock)
    timing=dict(timing)
    timing.update(remedy_version=VERSION,remedy_fallback_used=False,
                  remedy_primary_npu_ms=timing['npu_ms'],remedy_fallback_npu_ms=0.0)
    # 主方向已有结果时直接返回，避免每帧都支付第二次NPU调用的开销。
    if people:return people,timing
    began=clock();rotated=rotate(image);rotation_ms=(clock()-began)*1000
    extra,cost=primary(runtime,rotated,confidence=confidence,clock=clock)
    began=clock();people=restore180(extra,image.shape[1],image.shape[0]);restore_ms=(clock()-began)*1000
    for key in ('preprocess_ms','npu_ms','postprocess_ms'):timing[key]+=cost[key]
    timing['preprocess_ms']+=rotation_ms;timing['postprocess_ms']+=restore_ms
    timing.update(remedy_fallback_used=True,remedy_fallback_npu_ms=cost['npu_ms'],
                  remedy_rotation_ms=rotation_ms,remedy_restore_ms=restore_ms)
    return people,timing


def configure_scene(enabled=True):
    """Set class used both at session start and after observation-gap resets."""
    import scene741
    if enabled:
        from pose_fall1806 import PoseFallMonitor
    else:
        from pose_fall import PoseFallMonitor
    scene741.PoseFallMonitor=PoseFallMonitor
