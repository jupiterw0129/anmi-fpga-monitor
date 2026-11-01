#!/usr/bin/env python3
"""Offline pose-model verification; this does not measure RK3576 NPU performance."""

import argparse
import json
from pathlib import Path

import cv2
import numpy as np


MODEL_SIZE = 640
KEYPOINT_COUNT = 17


def prepare_rgb(image):
    height, width = image.shape[:2]
    ratio = min(MODEL_SIZE / width, MODEL_SIZE / height)
    scaled_width, scaled_height = int(width * ratio), int(height * ratio)
    offset_x = (MODEL_SIZE - scaled_width) // 2
    offset_y = (MODEL_SIZE - scaled_height) // 2
    canvas = np.full((MODEL_SIZE, MODEL_SIZE, 3), 56, dtype=np.uint8)
    canvas[offset_y:offset_y + scaled_height, offset_x:offset_x + scaled_width] = cv2.cvtColor(
        cv2.resize(image, (scaled_width, scaled_height)), cv2.COLOR_BGR2RGB)
    return canvas, ratio, offset_x, offset_y


def prepare(image):
    canvas, ratio, offset_x, offset_y = prepare_rgb(image)
    tensor = np.ascontiguousarray(canvas.transpose(2, 0, 1)[None]).astype(np.float32) / 255
    return tensor, ratio, offset_x, offset_y


def decode(outputs, shape, ratio, offset_x, offset_y, confidence=0.5, iou_limit=0.4):
    if len(outputs) != 4 or outputs[3].shape != (1, KEYPOINT_COUNT, 3, 8400):
        raise ValueError('unexpected YOLOv8n-pose output shape')
    height, width = shape[:2]
    candidates = []
    offset = 0
    for feature, grid_size, stride in zip(outputs[:3], (80, 40, 20), (8, 16, 32)):
        if feature.shape != (1, 65, grid_size, grid_size):
            raise ValueError('unexpected pose detection feature shape')
        flat = feature[0].reshape(65, -1)
        scores = 1 / (1 + np.exp(-np.clip(flat[64], -80, 80)))
        for index in np.flatnonzero(scores >= confidence):
            logits = flat[:64, index].reshape(4, 16)
            weights = np.exp(logits - logits.max(axis=1, keepdims=True))
            distances = (weights * np.arange(16)).sum(axis=1) / weights.sum(axis=1)
            center_x = (index % grid_size + 0.5) * stride
            center_y = (index // grid_size + 0.5) * stride
            box = np.array([center_x - distances[0] * stride,
                            center_y - distances[1] * stride,
                            center_x + distances[2] * stride,
                            center_y + distances[3] * stride], dtype=np.float32)
            box[0::2] = np.clip((box[0::2] - offset_x) / ratio, 0, width)
            box[1::2] = np.clip((box[1::2] - offset_y) / ratio, 0, height)
            if box[2] <= box[0] or box[3] <= box[1]:
                continue
            points = outputs[3][0, :, :, offset + index].copy()
            points[:, 0] = np.clip((points[:, 0] - offset_x) / ratio, 0, width)
            points[:, 1] = np.clip((points[:, 1] - offset_y) / ratio, 0, height)
            candidates.append((float(scores[index]), box, points))
        offset += grid_size * grid_size
    selected = []
    for score, box, points in sorted(candidates, key=lambda item: item[0], reverse=True):
        if all(box_iou(box, accepted[1]) <= iou_limit for accepted in selected):
            selected.append((score, box, points))
    return [dict(confidence=score, box_xyxy=box.tolist(), keypoints_xyc=points.tolist())
            for score, box, points in selected]


def box_iou(first, second):
    overlap = np.maximum(np.minimum(first[2:], second[2:]) - np.maximum(first[:2], second[:2]), 0)
    intersection = float(np.prod(overlap))
    first_area = float(np.prod(first[2:] - first[:2]))
    second_area = float(np.prod(second[2:] - second[:2]))
    return intersection / (first_area + second_area - intersection)


def read_frame(image_path, video_path, seconds):
    if image_path is not None:
        image = cv2.imread(str(image_path))
    else:
        capture = cv2.VideoCapture(str(video_path))
        try:
            if not capture.isOpened():
                raise ValueError('cannot open video')
            capture.set(cv2.CAP_PROP_POS_MSEC, seconds * 1000)
            valid, image = capture.read()
            if not valid:
                raise ValueError('cannot read video at requested time')
        finally:
            capture.release()
    if image is None:
        raise ValueError('cannot decode image')
    return image


def run(model, image, confidence=0.5):
    import onnxruntime as ort

    session = ort.InferenceSession(str(model), providers=['CPUExecutionProvider'])
    tensor, ratio, offset_x, offset_y = prepare(image)
    outputs = session.run(None, {session.get_inputs()[0].name: tensor})
    return decode(outputs, image.shape, ratio, offset_x, offset_y, confidence)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', type=Path, default=Path(__file__).with_name('yolov8n-pose.onnx'))
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--image', type=Path)
    source.add_argument('--video', type=Path)
    parser.add_argument('--seconds', type=float, default=0)
    parser.add_argument('--confidence', type=float, default=0.5)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.seconds < 0 or not 0 < args.confidence <= 1 or args.output.exists():
        parser.error('nonnegative seconds, valid confidence and unused output required')
    image = read_frame(args.image, args.video, args.seconds)
    report = dict(source='HOST_ONNX_OFFLINE_NOT_RKNN_OR_FPGA',
                  image_size=[image.shape[1], image.shape[0]],
                  model=str(args.model.resolve()),
                  people=run(args.model, image, args.confidence))
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f"people={len(report['people'])} output={args.output}")


if __name__ == '__main__':
    main()
