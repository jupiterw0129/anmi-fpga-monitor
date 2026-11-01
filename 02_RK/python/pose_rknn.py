import argparse
import hashlib
import json
import os
import signal
import sys
import time
from collections import Counter
from pathlib import Path

import cv2
import numpy as np

from pose_fall import PoseFallMonitor
from pose_onnx import decode, prepare_rgb


def infer_pose(runtime, image, confidence=0.5, clock=time.perf_counter):
    started = clock()
    prepared, ratio, offset_x, offset_y = prepare_rgb(image)
    prepared_at = clock()
    outputs = runtime.inference(inputs=[prepared[None]], data_format=['nhwc'])
    inferred_at = clock()
    if outputs is None or len(outputs) != 4 or any(output is None for output in outputs):
        raise RuntimeError('RKNN pose returned invalid outputs')
    people = decode(outputs, image.shape, ratio, offset_x, offset_y, confidence)
    ended = clock()
    return people, dict(preprocess_ms=(prepared_at - started) * 1000,
                        npu_ms=(inferred_at - prepared_at) * 1000,
                        postprocess_ms=(ended - inferred_at) * 1000,
                        output_shapes=[list(output.shape) for output in outputs])


def infer_video(runtime, path, sample_fps=4, rotate180=False):
    capture = cv2.VideoCapture(str(path))
    monitor = PoseFallMonitor()
    frames = []
    try:
        fps = capture.get(cv2.CAP_PROP_FPS)
        if not capture.isOpened() or not np.isfinite(fps) or fps <= 0:
            raise ValueError('video with valid frame rate required')
        interval = max(1, round(fps / sample_fps))
        index = 0
        while capture.grab():
            if index % interval == 0:
                valid, image = capture.retrieve()
                if not valid:
                    raise RuntimeError('video frame decode failed')
                if rotate180:
                    image = cv2.rotate(image, cv2.ROTATE_180)
                people, timing = infer_pose(runtime, image)
                state = monitor.update(index / fps, people, image.shape[1], image.shape[0])
                frames.append(dict(frame=index, time_s=index / fps, people=people,
                                   fall_state=state, **timing))
            index += 1
    finally:
        capture.release()
    if not frames:
        raise ValueError('empty video')
    return dict(source='RKNN_VIDEO_REPLAY_NOT_FPGA_LIVE', video=str(path),
                sample_fps=fps / interval, frame_count=len(frames), frames=frames,
                frames_with_people=sum(bool(frame['people']) for frame in frames),
                states=dict(Counter(frame['fall_state']['state'] for frame in frames)),
                events=[frame['fall_state'] for frame in frames if frame['fall_state']['event']],
                scope='Existing recorded video; sampled NPU pose/state execution, not live FPGA or labeled accuracy evaluation')


def main():
    parser = argparse.ArgumentParser(description='RK3576 pose and candidate fall-state execution; no accuracy claim')
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--image', type=Path)
    source.add_argument('--video', type=Path)
    source.add_argument('--bar-resource', type=Path)
    parser.add_argument('--capture-dir', type=Path)
    parser.add_argument('--frames', type=int, default=120)
    parser.add_argument('--preprocess', type=int, choices=range(8), default=1)
    parser.add_argument('--rotate180', action='store_true')
    parser.add_argument('--sample-fps', type=float, default=4)
    parser.add_argument('--display', action='store_true')
    parser.add_argument('--snapshot', type=Path)
    args = parser.parse_args()
    if args.output.exists() or args.frames < 1 or not args.model.is_file() or not 2 <= args.sample_fps <= 30:
        parser.error('model, positive frames and unused output required')
    if args.bar_resource and not args.capture_dir:
        parser.error('--capture-dir required for live PCIe mode')
    if (args.display or args.snapshot) and not args.bar_resource:
        parser.error('--display and --snapshot require live FPGA mode')
    if args.snapshot and (args.snapshot.exists() or args.snapshot.resolve() == args.output.resolve()):
        parser.error('snapshot must be a new file distinct from output')

    from rknnlite.api import RKNNLite

    runtime = RKNNLite()
    display = None
    try:
        if runtime.load_rknn(str(args.model)) != 0 or runtime.init_runtime(core_mask=RKNNLite.NPU_CORE_0) != 0:
            raise RuntimeError('pose model/runtime initialization failed')
        if args.image:
            image = cv2.imread(str(args.image))
            if image is None:
                raise ValueError('cannot decode input image')
            if args.rotate180:
                image = cv2.rotate(image, cv2.ROTATE_180)
            people, timing = infer_pose(runtime, image)
            report = dict(source='RKNN_IMAGE_REPLAY_NOT_LIVE', people=people,
                          image_size=[image.shape[1], image.shape[0]], **timing)
        elif args.video:
            report = infer_video(runtime, args.video, args.sample_fps, args.rotate180)
        else:
            sys.path.insert(0, str(args.capture_dir.resolve()))
            from capture_jpeg import (REG_CTRL, REG_JPEG_MODE, REG_VERSION,
                                      read_transfer, validate_candidate)
            from live_jpeg import capture_live
            import mmap
            import struct

            monitor = PoseFallMonitor()
            states = []
            last_overlay = None
            if args.display:
                from pose_display import HdmiDisplay
                display = HdmiDisplay()

            def infer(image):
                nonlocal last_overlay
                if args.rotate180:
                    image = cv2.rotate(image, cv2.ROTATE_180)
                people, timing = infer_pose(runtime, image)
                states.append(monitor.update(time.monotonic(), people, image.shape[1], image.shape[0]))
                if display or args.snapshot:
                    from pose_display import annotate
                    last_overlay = annotate(image, people, states[-1], timing['npu_ms'])
                    if display:
                        display.push(last_overlay)
                timing.pop('output_shapes')
                return people, timing

            bar_fd = os.open(args.bar_resource, os.O_RDWR | os.O_SYNC)
            try:
                with mmap.mmap(bar_fd, 4096, access=mmap.ACCESS_WRITE) as registers:
                    def read(offset):
                        return struct.unpack_from('<I', registers, offset)[0]

                    def write(offset, value):
                        struct.pack_into('<I', registers, offset, value)

                    validate_candidate(read(REG_VERSION), read(REG_CTRL), read(REG_JPEG_MODE))
                    device = os.open('/dev/ANLOGIC-PCI0_c2h_0', os.O_RDONLY | os.O_TRUNC)
                    try:
                        report = capture_live(read, write, lambda: read_transfer(device),
                                              args.frames, args.preprocess, infer)
                    finally:
                        os.close(device)
            finally:
                os.close(bar_fd)
            report['source'] = 'LIVE_FPGA_JPEG_PCIE_RKNN_POSE_AND_FALL_STATE'
            report['fall_states'] = states
            if display:
                report['hdmi_frames'] = display.frames
                display.close()
                display = None
            if args.snapshot:
                if last_overlay is None or not cv2.imwrite(str(args.snapshot), last_overlay):
                    raise RuntimeError('cannot save explicitly requested overlay snapshot')
                report['snapshot'] = str(args.snapshot)
            report['scope'] = 'Live NPU keypoints and candidate temporal state execution; no fall accuracy or sensor-to-host latency claim'
        report['model_sha256'] = hashlib.sha256(args.model.read_bytes()).hexdigest()
        report['state_machine_sha256'] = hashlib.sha256(
            Path(__file__).with_name('pose_fall.py').read_bytes()).hexdigest()
        report['rotate180'] = args.rotate180
        report['fall_accuracy_validated'] = False
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(json.dumps({key: value for key, value in report.items() if key not in ('frames', 'fall_states')}, ensure_ascii=False))
    finally:
        try:
            if display:
                display.close()
        finally:
            runtime.release()


if __name__ == '__main__':
    def stop_on_signal(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, stop_on_signal)
    main()
