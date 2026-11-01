import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path

import cv2

from pose_fall import PoseFallMonitor


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def evaluate(source, video_dir):
    data = json.loads(source.read_text(encoding='utf-8'))
    if data['source'] != 'RKNN_VIDEO_REPLAY_NOT_FPGA_LIVE':
        raise ValueError('recorded RKNN pose sequence required')
    video = video_dir / Path(data['video']).name
    capture = cv2.VideoCapture(str(video))
    try:
        if not capture.isOpened():
            raise ValueError(f'cannot open matching video: {video}')
        width, height = int(capture.get(3)), int(capture.get(4))
        duration = capture.get(cv2.CAP_PROP_FRAME_COUNT) / capture.get(cv2.CAP_PROP_FPS)
    finally:
        capture.release()
    monitor = PoseFallMonitor()
    rows = [monitor.update(frame['time_s'], frame['people'], width, height)
            for frame in data['frames']]
    return dict(source=str(source), source_sha256=digest(source),
                video=str(video), video_sha256=digest(video),
                image_size=[width, height], duration_s=duration,
                frame_count=len(rows), frames_with_people=data['frames_with_people'],
                original_events=data['events'],
                replay_states=dict(Counter(row['state'] for row in rows)),
                replay_events=[row for row in rows if row['event']])


def main():
    parser = argparse.ArgumentParser(description='Replay existing NPU poses; no new inference or accuracy claim')
    parser.add_argument('--input', type=Path, nargs='+', required=True)
    parser.add_argument('--video-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('new output path required')
    report = dict(scope='Recorded NPU keypoint replay, not live FPGA or held-out labeled accuracy evaluation',
                  state_machine_sha256=digest(Path(__file__).with_name('pose_fall.py')),
                  fall_accuracy_validated=False,
                  sequences=[evaluate(source, args.video_dir) for source in args.input])
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
