import hashlib
import json
import sys
import time
from pathlib import Path

import cv2
import numpy as np

from raw_npu_adapter import raw_bgr_to_bgr


BASE = Path('/home/anmi/lossless710_board_20261020')
PACKAGE = Path('/home/anmi/quality_runtime_20261018/package')
MODEL = PACKAGE / 'yolov8n_pose_rk3576_fp16.rknn'
EXPECTED = {
    'yolov8n_pose_rk3576_fp16.rknn': '04a7677835281317d47dc42406b0556a47279e02c504ad97810c629a77e9e538',
    'pose_rknn.py': 'f0db685449f7ae2e12030702e2bed509692d948371b35f505404c3078a616bd0',
    'pose_onnx.py': '1c9a503be10863fccb7acebdb0846ab4607fef658f20873b35f7880fd82abf12',
    'pose_fall.py': 'be744ddb9af631a15e16a7403e70f28cc7d93ded3ceb5bff45e05c1cc0d2bfea',
    'pose_display.py': '857bd949a93c93e33d3f88bc261d4ddfe48ccfef45a81592e820ef080d0866c5',
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_package():
    actual = {name: digest(PACKAGE / name) for name in EXPECTED}
    if actual != EXPECTED:
        raise ValueError('Frozen model or NPU package differs')
    return actual


def main():
    output = Path('/home/anmi/lossless710_colorfix_board_20261020/npu_replay60')
    if output.exists():
        raise FileExistsError(output)
    package_hashes = check_package()
    session = json.loads((BASE / 'burst60/session.json').read_text())
    driver = json.loads((BASE / 'burst60.driver.json').read_text())
    decoded = json.loads((BASE / 'burst60_decode.json').read_text())
    if not session['cleanup_verified'] or not driver['rollback_verified'] or decoded['frames'] != 60:
        raise ValueError('Real capture/decode/rollback incomplete')
    if session['status'] != 'NATIVE_REAL_EOP_CRC_REASSEMBLED_PENDING_RGB_SOURCE_COMPARISON':
        raise ValueError('Capture not committed')
    for register in ('0xc0', '0xf0', '0xf4', '0xe8'):
        if session['after'][register]:
            raise ValueError('Capture contains hardware faults or dropped frames')
    native = json.loads(session['native_stdout'])
    timestamps = native['frame_end_s']
    if len(timestamps) != 60 or any(after <= before for before, after in zip(timestamps, timestamps[1:])):
        raise ValueError('Invalid captured frame timestamps')
    files = sorted((BASE / 'burst60_decoded').glob('*.rgb'))
    if [path.name for path in files] != [f'frame_{index:06d}.rgb' for index in range(60)]:
        raise ValueError('Unexpected decoded frame inventory')
    source_hashes = {path.name: digest(path) for path in files}
    output.mkdir()
    sys.path.insert(0, str(PACKAGE))
    from rknnlite.api import RKNNLite
    from pose_display import annotate
    from pose_fall import PoseFallMonitor
    from pose_onnx import prepare_rgb
    from pose_rknn import infer_pose

    runtime = RKNNLite()
    monitor = PoseFallMonitor()
    records = []
    started = time.perf_counter()
    try:
        if runtime.load_rknn(str(MODEL)) != 0 or runtime.init_runtime(core_mask=RKNNLite.NPU_CORE_0_1) != 0:
            raise RuntimeError('NPU initialization failed')
        with (output / 'frames.jsonl').open('x') as journal:
            for index, path in enumerate(files):
                raw = path.read_bytes()
                if hashlib.sha256(raw).hexdigest() != source_hashes[path.name]:
                    raise ValueError('Source RGB changed during replay')
                image = raw_bgr_to_bgr(raw)
                bgr = np.frombuffer(raw, dtype=np.uint8).reshape(1080, 1920, 3)
                reference = cv2.rotate(bgr, cv2.ROTATE_180)
                if not np.array_equal(image, reference):
                    raise ValueError('BGR layout or rotation mismatch')
                prepared = prepare_rgb(image)[0]
                if prepared.shape != (640, 640, 3) or prepared.dtype != np.uint8:
                    raise ValueError('NPU tensor contract changed')
                people, timing = infer_pose(runtime, image)
                state = monitor.update(timestamps[index], people, 1920, 1080)
                record = dict(frame_id=index, captured_completion_s=timestamps[index],
                              raw_sha256=source_hashes[path.name], tensor_sha256=hashlib.sha256(prepared.tobytes()).hexdigest(),
                              people=people, fall_state=state, **timing)
                records.append(record)
                journal.write(json.dumps(record) + '\n')
                if index in (0, 29, 59):
                    overlay = annotate(image, people, state, timing['npu_ms'],
                                       source_label='CAPTURED FPGA710 LOSSLESS BGR -> NPU REPLAY (NOT LIVE)')
                    if not cv2.imwrite(str(output / f'frame_{index:06d}_overlay.png'), overlay):
                        raise RuntimeError('Overlay save failed')
    finally:
        runtime.release()
    report = dict(status='REAL_710_CAPTURED_RGB_60_FRAME_NPU_REPLAY_PASSED_NOT_LIVE',
                  frame_count=len(records), frames_with_people=sum(bool(record['people']) for record in records),
                  source_hashes=source_hashes, package_hashes=package_hashes,
                  journal_sha256=digest(output / 'frames.jsonl'),
                  elapsed_s=time.perf_counter() - started, rotate180=True,
                  tensor_contract='uint8 NHWC [1,640,640,3] RGB via unchanged prepare_rgb; no JPEG conversion',
                  median_npu_ms=float(np.median([record['npu_ms'] for record in records])),
                  p95_npu_ms=float(np.percentile([record['npu_ms'] for record in records], 95)),
                  live_npu_pipeline_verified=False, fall_accuracy_verified=False,
                  source_side_raw_comparison=False, production_files_changed=False)
    if len(records) != 60 or check_package() != package_hashes:
        raise ValueError('Incomplete replay or frozen package changed')
    with (output / 'report.json').open('x') as stream:
        json.dump(report, stream, indent=2)
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

