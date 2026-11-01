"""Keep the checked overlap augmentation, replacing only its decoder scheduler."""
from pose_pipeline1723 import augment_pose as original_augment


def augment_pose(source):
    source = original_augment(source)
    old = 'from latest_decode1722 import LatestDecode'
    assert source.count(old) == 1
    return source.replace(old, 'from latest_decode1790 import LatestDecode')
