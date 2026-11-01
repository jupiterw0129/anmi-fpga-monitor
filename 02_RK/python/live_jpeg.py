#!/usr/bin/env python3
import argparse
import json
import os
import statistics
import time
from collections import deque
from pathlib import Path

import cv2
import numpy as np

from capture_jpeg import (REG_BUSY_DROP, REG_CAM_MODE, REG_CTRL, REG_INPUT_FAULT,
                          REG_INPUT_OVERFLOW, REG_JPEG_MODE, REG_OVERSIZE,
                          REG_MIPI_FIFO_OVERFLOW, REG_PREPROCESS, REG_PREPROCESS_ACTIVE, REG_VERSION,
                          jpeg_from_transfer, read_transfer, validate_candidate)
from infer_jpeg import infer_frame, load_detector


COUNTERS = (REG_INPUT_OVERFLOW, REG_OVERSIZE, REG_BUSY_DROP,
            REG_INPUT_FAULT, REG_MIPI_FIFO_OVERFLOW)


def capture_live(read, write, transfer, frames, preprocess, infer=None, clock=time.perf_counter,
                 duration_s=None, on_frame=None, retain_rows=True, on_fault=None):
    if frames < 1 or (duration_s is not None and (not np.isfinite(duration_s) or duration_s <= 0)):
        raise ValueError('positive frame limit and finite positive duration required')
    validate_candidate(read(REG_VERSION), read(REG_CTRL), read(REG_JPEG_MODE))
    original_mode = read(REG_CAM_MODE)
    original_preprocess = read(REG_PREPROCESS)
    rows = []
    processing_times = [] if retain_rows else deque(maxlen=4096)
    frame_count = 0
    completed_at = None
    first_frame_at = None
    last_frame_at = None
    try:
        write(REG_PREPROCESS, preprocess)
        write(REG_CAM_MODE, 2)
        write(REG_JPEG_MODE, 1)
        if (read(REG_PREPROCESS), read(REG_CAM_MODE), read(REG_JPEG_MODE)) != (preprocess, 2, 1):
            raise RuntimeError('candidate mode did not latch')
        before = [read(register) for register in COUNTERS]
        initial_counters = list(before)
        initial_busy_drops = before[2]
        write(REG_CTRL, 1)
        for index in range(frames):
            started = clock()
            payload = transfer()
            received_at = clock()
            if read(REG_PREPROCESS_ACTIVE) != preprocess:
                raise RuntimeError('preprocessing mask not active at frame boundary')
            after = [read(register) for register in COUNTERS]
            if any(after[position] != before[position] for position in (0, 1, 3, 4)):
                raise RuntimeError(f'FPGA overflow/fault at frame {index}: {before} -> {after}')
            try:
                jpeg = jpeg_from_transfer(payload)
                image = cv2.imdecode(np.frombuffer(jpeg, dtype=np.uint8), cv2.IMREAD_COLOR)
                if image is None or image.shape != (720, 1280, 3):
                    raise RuntimeError(f'bad JPEG image at frame {index}')
            except (ValueError, RuntimeError) as error:
                if on_fault is not None:
                    on_fault(index, payload, error)
                raise
            decoded_at = clock()
            row = dict(frame=index, jpeg_bytes=len(jpeg), dma_bytes=len(payload),
                       rgb24_to_jpeg_ratio=image.size / len(jpeg),
                       dma_wait_ms=(received_at - started) * 1000,
                       decode_ms=(decoded_at - received_at) * 1000,
                       counters=dict(zip(('input_overflow', 'oversize', 'busy_drop',
                                          'input_fault', 'mipi_fifo_overflow'), after)))
            if infer is not None:
                row['detections'], timing = infer(image)
                row.update(timing)
            row['processing_ms'] = (clock() - received_at) * 1000
            processing_times.append(row['processing_ms'])
            frame_count += 1
            if retain_rows:
                rows.append(row)
            if first_frame_at is None:
                first_frame_at = received_at
            last_frame_at = received_at
            before = after
            if on_frame is not None:
                on_frame(row)
            if duration_s is not None:
                completed_at = clock()
                if completed_at - first_frame_at >= duration_s:
                    break
        span = last_frame_at - first_frame_at
        final_counters = [read(register) for register in COUNTERS]
        if any(final_counters[position] != before[position] for position in (0, 1, 3, 4)):
            raise RuntimeError(f'FPGA overflow/fault during final inference: {before} -> {final_counters}')
        return dict(source='LIVE_PCIE_CANDIDATE_NOT_FILE_REPLAY',
                    frames=rows, frame_count=frame_count, rows_retained=retain_rows,
                    measurement_elapsed_s=(completed_at - first_frame_at) if completed_at is not None else span,
                    duration_target_met=duration_s is not None and completed_at - first_frame_at >= duration_s,
                    arrival_fps=(frame_count - 1) / span if frame_count > 1 and span > 0 else None,
                    median_processing_ms=statistics.median(processing_times),
                    processing_samples_retained=len(processing_times),
                    median_processing_scope='ALL_SAMPLES' if len(processing_times) == frame_count
                    else 'LATEST_WINDOW',
                    initial_counters=initial_counters, final_counters=final_counters,
                    observed_busy_drops=(final_counters[2] - initial_busy_drops) & 0xffffffff,
                    scope='Host DMA wait and processing only; no sensor-to-host timestamp, pose or fall claim')
    finally:
        write(REG_CTRL, 0)
        write(REG_JPEG_MODE, 0)
        write(REG_CAM_MODE, original_mode)
        write(REG_PREPROCESS, original_preprocess)


def main():
    parser = argparse.ArgumentParser(description='Measure live candidate PCIe JPEG capture and optional RKNN inference')
    parser.add_argument('--bar-resource', type=Path, required=True)
    parser.add_argument('--device', default='/dev/ANLOGIC-PCI0_c2h_0')
    parser.add_argument('--frames', type=int, default=120)
    parser.add_argument('--preprocess', type=int, choices=range(8), default=1)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--reference-dir', type=Path)
    parser.add_argument('--model', type=Path)
    args = parser.parse_args()
    if args.frames < 1 or args.output.exists() or bool(args.reference_dir) != bool(args.model):
        parser.error('positive frames, new output and both NPU paths (or neither) required')

    runtime = None
    bar_fd = os.open(args.bar_resource, os.O_RDWR | os.O_SYNC)
    try:
        import mmap
        import struct
        with mmap.mmap(bar_fd, 4096, access=mmap.ACCESS_WRITE) as registers:
            def read(offset):
                return struct.unpack_from('<I', registers, offset)[0]

            def write(offset, value):
                struct.pack_into('<I', registers, offset, value)

            validate_candidate(read(REG_VERSION), read(REG_CTRL), read(REG_JPEG_MODE))
            fd = os.open(args.device, os.O_RDONLY | os.O_TRUNC)
            try:
                validate_candidate(read(REG_VERSION), read(REG_CTRL), read(REG_JPEG_MODE))
                infer = None
                if args.model:
                    if not args.model.is_file():
                        raise FileNotFoundError(args.model)
                    reference = load_detector(args.reference_dir)
                    runtime = reference.RKNNLite()
                    if runtime.load_rknn(str(args.model)) != 0 or runtime.init_runtime(
                            core_mask=reference.RKNNLite.NPU_CORE_0) != 0:
                        raise RuntimeError('RKNN model/runtime initialization failed')
                    infer = lambda image: infer_frame(reference, runtime, image)
                result = capture_live(read, write, lambda: read_transfer(fd),
                                      args.frames, args.preprocess, infer)
            finally:
                os.close(fd)
    finally:
        if runtime is not None:
            runtime.release()
        os.close(bar_fd)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: value for key, value in result.items() if key != 'frames'}, ensure_ascii=False))


if __name__ == '__main__':
    main()
