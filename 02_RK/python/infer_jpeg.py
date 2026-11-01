#!/usr/bin/env python3
import argparse
import importlib.util
import json
import time
from pathlib import Path

import cv2
import numpy as np

from capture_jpeg import jpeg_from_transfer


def load_detector(reference_dir):
    helper_path = Path(__file__).resolve().parents[2] / 'gray_integration_20261004/offline_video_demo.py'
    spec = importlib.util.spec_from_file_location('existing_detector_helpers', helper_path)
    helpers = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helpers)
    reference = helpers.load_reference(reference_dir)
    reference.filter_boxes = lambda boxes, confidences, probabilities: helpers.safe_filter_boxes(
        reference, boxes, confidences, probabilities)
    return reference


def decode_packet(payload):
    encoded = jpeg_from_transfer(payload)
    image = cv2.imdecode(np.frombuffer(encoded, dtype=np.uint8), cv2.IMREAD_COLOR)
    if image is None or image.shape != (720, 1280, 3):
        raise ValueError('expected a decodable 1280x720 candidate JPEG')
    return image, len(encoded)


def infer_frame(reference, runtime, image):
    started = time.perf_counter()
    rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
    prepared, ratio, offset_x, offset_y = reference.letterbox(rgb, reference.IMG_SIZE)
    prepared_at = time.perf_counter()
    outputs = runtime.inference(inputs=[np.expand_dims(prepared, axis=0)])
    inferred_at = time.perf_counter()
    if not outputs or any(output is None for output in outputs):
        raise RuntimeError('RKNN returned no valid inference outputs')
    boxes, scores, class_ids = reference.postprocess_yolov5s(
        outputs, ratio, offset_x, offset_y, image.shape[1], image.shape[0])
    detections = [dict(class_id=int(class_id), confidence=float(score),
                       box_xyxy=[float(coordinate) for coordinate in box])
                  for box, score, class_id in zip(boxes, scores, class_ids)]
    ended = time.perf_counter()
    return detections, {
        'preprocess_ms': (prepared_at - started) * 1000,
        'npu_ms': (inferred_at - prepared_at) * 1000,
        'postprocess_ms': (ended - inferred_at) * 1000,
    }


def run(inputs, output_dir, reference=None, model=None):
    paths = [Path(path).resolve() for path in inputs]
    if not paths or any(not path.is_file() for path in paths):
        raise FileNotFoundError('all JPEG input files must exist')
    if reference is not None and (model is None or not Path(model).is_file()):
        raise FileNotFoundError('RKNN model not found')
    output_dir = Path(output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=False)
    runtime = None
    rows = []
    try:
        if reference is not None:
            runtime = reference.RKNNLite()
            if runtime.load_rknn(str(model)) != 0:
                raise RuntimeError('load_rknn failed')
            if runtime.init_runtime(core_mask=reference.RKNNLite.NPU_CORE_0) != 0:
                raise RuntimeError('RK3576 NPU initialization failed')
        for index, path in enumerate(paths):
            started = time.perf_counter()
            payload = path.read_bytes()
            read_at = time.perf_counter()
            image, encoded_bytes = decode_packet(payload)
            decoded_at = time.perf_counter()
            row = dict(index=index, input=str(path), jpeg_bytes=encoded_bytes,
                       width=image.shape[1], height=image.shape[0],
                       rgb24_to_jpeg_ratio=image.size / encoded_bytes,
                       file_read_ms=(read_at - started) * 1000,
                       decode_ms=(decoded_at - read_at) * 1000)
            if runtime is not None:
                row['detections'], timing = infer_frame(reference, runtime, image)
                row.update(timing)
            row['processing_ms'] = (time.perf_counter() - started) * 1000
            target = output_dir / f'decoded_{index:04d}.png'
            if not cv2.imwrite(str(target), image):
                raise RuntimeError(f'cannot save decoded image: {target}')
            rows.append(row)
        report = dict(source='JPEG_FILE_REPLAY_NOT_LIVE',
                      mode='DECODE_ONLY_NO_NPU' if runtime is None else 'RKNN_OBJECT_DETECTION',
                      scope='File replay only; no camera FPS, PCIe latency, pose or fall detection claim',
                      frames=rows)
        (output_dir / 'metrics.json').write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        return report
    finally:
        if runtime is not None:
            runtime.release()


def main():
    parser = argparse.ArgumentParser(description='Decode FPGA JPEG files and optionally run the existing RKNN detector')
    parser.add_argument('--input', type=Path, nargs='+', required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--decode-only', action='store_true')
    parser.add_argument('--reference-dir', type=Path)
    parser.add_argument('--model', type=Path)
    args = parser.parse_args()
    if not args.decode_only and (args.reference_dir is None or args.model is None):
        parser.error('NPU mode requires --reference-dir and --model; use --decode-only for host validation')
    reference = None if args.decode_only else load_detector(args.reference_dir.resolve())
    report = run(args.input, args.output_dir, reference, args.model)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
