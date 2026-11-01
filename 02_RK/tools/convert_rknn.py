import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

from rknn.api import RKNN


def main():
    root = Path(__file__).resolve().parent
    model = root / 'yolov8n-pose.onnx'
    output = root / 'yolov8n_pose_rk3576_fp16.rknn'
    expected = '308495ebe4416b40adf376485252a7b8ba7933a169368b31e74e0f977ded8663'
    if hashlib.sha256(model.read_bytes()).hexdigest() != expected:
        raise RuntimeError('unexpected pose ONNX source')
    if output.exists():
        raise FileExistsError(output)
    runtime = RKNN(verbose=True)
    try:
        runtime.config(mean_values=[[0, 0, 0]], std_values=[[255, 255, 255]],
                       target_platform='rk3576')
        for step, result in [('load_onnx', runtime.load_onnx(model=str(model))),
                             ('build', None)]:
            if step == 'build':
                result = runtime.build(do_quantization=False)
            if result != 0:
                raise RuntimeError(f'RKNN {step} failed: {result}')
        if runtime.export_rknn(str(output)) != 0:
            raise RuntimeError('RKNN export failed')
    finally:
        runtime.release()
    evidence = dict(status='CONVERTED_NOT_NPU_VALIDATED', platform='rk3576',
                    quantized=False, input_rgb_uint8=True,
                    created_utc=datetime.now(timezone.utc).isoformat(),
                    source_sha256=expected,
                    output_sha256=hashlib.sha256(output.read_bytes()).hexdigest(),
                    output_bytes=output.stat().st_size)
    (root / 'rknn_conversion_evidence.json').write_text(
        json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(evidence, indent=2))


if __name__ == '__main__':
    main()
