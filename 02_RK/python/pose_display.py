import os
import shutil
import subprocess

import cv2


SKELETON = ((5, 6), (5, 7), (7, 9), (6, 8), (8, 10), (5, 11),
            (6, 12), (11, 12), (11, 13), (13, 15), (12, 14), (14, 16))


def annotate(image, people, state, npu_ms,
             source_label='LIVE FPGA JPEG -> PCIe -> RK3576 NPU'):
    output = image.copy()
    height, width = output.shape[:2]
    for person in people:
        box = person['box_xyxy']
        left, right = [max(0, min(width - 1, round(box[index]))) for index in (0, 2)]
        top, bottom = [max(0, min(height - 1, round(box[index]))) for index in (1, 3)]
        cv2.rectangle(output, (left, top), (right, bottom), (60, 230, 100), 2)
        points = person['keypoints_xyc']
        for first, second in SKELETON:
            if points[first][2] >= 0.4 and points[second][2] >= 0.4:
                start = tuple(round(value) for value in points[first][:2])
                end = tuple(round(value) for value in points[second][:2])
                cv2.line(output, start, end, (0, 210, 255), 2)
        for point_x, point_y, confidence in points:
            if confidence >= 0.4:
                cv2.circle(output, (round(point_x), round(point_y)), 3, (255, 120, 0), -1)
    cv2.rectangle(output, (0, 0), (width, 88), (20, 20, 20), -1)
    lines = (source_label,
             f"People: {len(people)}  State: {state['state']}  NPU: {npu_ms:.1f} ms",
             'Candidate fall state only - accuracy NOT validated')
    for index, text in enumerate(lines):
        cv2.putText(output, text, (12, 24 + index * 27), cv2.FONT_HERSHEY_SIMPLEX,
                    0.65, (230, 230, 230), 1, cv2.LINE_AA)
    return output


class HdmiDisplay:
    def __init__(self):
        if not os.environ.get('DISPLAY') or not os.environ.get('XAUTHORITY'):
            raise RuntimeError('DISPLAY and XAUTHORITY required for HDMI desktop')
        if not shutil.which('gst-launch-1.0'):
            raise RuntimeError('gst-launch-1.0 not found')
        self.process = subprocess.Popen(
            ['gst-launch-1.0', '-q', 'fdsrc', 'fd=0', 'blocksize=262144',
             '!', 'rawvideoparse', 'format=bgr', 'width=960', 'height=540',
             'framerate=30/1', '!', 'videoconvert', '!', 'ximagesink',
             'handle-events=false', 'sync=false'],
            stdin=subprocess.PIPE, stdout=subprocess.DEVNULL)
        self.frames = 0
        self.closed = False

    def push(self, image):
        if self.closed or self.process.poll() is not None:
            raise RuntimeError('HDMI display process exited early')
        scaled = cv2.resize(image, (960, 540), interpolation=cv2.INTER_AREA)
        self.process.stdin.write(scaled.tobytes())
        self.process.stdin.flush()
        self.frames += 1

    def close(self):
        if self.closed:
            return
        self.closed = True
        try:
            self.process.stdin.close()
        except BrokenPipeError:
            pass
        try:
            result = self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
            raise RuntimeError('HDMI display did not shut down after EOF')
        if result != 0:
            raise RuntimeError(f'HDMI display failed with exit code {result}')
