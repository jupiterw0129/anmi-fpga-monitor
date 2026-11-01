import cv2
import numpy as np


def raw_bgr_to_bgr(raw, width=1920, height=1080, rotate180=True):
    if width <= 0 or height <= 0 or len(raw) != width * height * 3:
        raise ValueError('Expected exactly one full packed BGR888 frame')
    image = np.frombuffer(raw, dtype=np.uint8).reshape(height, width, 3)
    if rotate180:
        image = cv2.rotate(image, cv2.ROTATE_180)
    return np.ascontiguousarray(image)

