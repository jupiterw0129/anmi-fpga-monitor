#!/usr/bin/env python3
"""Keypoint-only fall candidate state machine; alarms require on-device validation."""

import argparse
import json
import math
from collections import deque
from pathlib import Path
from statistics import median


class PoseFallMonitor:
    def __init__(self, candidate_seconds=0.8, recovery_seconds=0.5,
                 missing_seconds=0.5, drop_fraction=0.12):
        self.candidate_seconds = candidate_seconds
        self.recovery_seconds = recovery_seconds
        self.missing_seconds = missing_seconds
        self.drop_fraction = drop_fraction
        self.upright = deque()
        self.last_seen = None
        self.last_time = None
        self.candidate_since = None
        self.recovery_since = None
        self.state = 'NO_PERSON'

    def update(self, time_s, people, width, height):
        if width <= 0 or height <= 0 or (self.last_time is not None and time_s <= self.last_time):
            raise ValueError('dimensions and strictly increasing timestamps required')
        self.last_time = time_s
        if len(people) != 1 or people[0]['confidence'] < 0.5:
            self.candidate_since = None
            self.recovery_since = None
            if self.last_seen is None or time_s - self.last_seen > self.missing_seconds:
                self.upright.clear()
                self.state = 'AMBIGUOUS' if len(people) > 1 else 'NO_PERSON'
            return dict(time_s=time_s, state=self.state, event=None, reason='person_count_or_confidence')

        person = people[0]
        points = person['keypoints_xyc']
        box = person['box_xyxy']
        if len(points) != 17 or len(box) != 4:
            raise ValueError('expected 17 COCO keypoints and xyxy person box')
        if self.last_seen is not None and time_s - self.last_seen > self.missing_seconds:
            self.upright.clear()
            self.candidate_since = None
            self.recovery_since = None
            self.state = 'WAIT_BASELINE'
        self.last_seen = time_s
        required = (5, 6, 11, 12)
        visible = all(len(points[index]) == 3 and points[index][2] >= 0.4 for index in required)
        edge = (box[0] <= width * 0.02 or box[2] >= width * 0.98 or
                box[3] >= height * 0.98)
        if not visible or edge:
            self.candidate_since = None
            self.recovery_since = None
            self.state = 'UNCERTAIN'
            return dict(time_s=time_s, state=self.state, event=None,
                        reason='occluded_joints_or_frame_edge')

        shoulder_x = (points[5][0] + points[6][0]) / 2
        shoulder_y = (points[5][1] + points[6][1]) / 2
        hip_x = (points[11][0] + points[12][0]) / 2
        hip_y = (points[11][1] + points[12][1]) / 2
        torso_angle = math.degrees(math.atan2(abs(hip_y - shoulder_y),
                                               abs(hip_x - shoulder_x)))
        baseline_ready = self.upright and time_s - self.upright[0][0] >= 0.4
        baseline = median(value for _, value in self.upright) if baseline_ready else None
        hip_drop = hip_y / height - baseline if baseline is not None else 0.0
        box_height = box[3] - box[1]
        if box_height <= 0 or box[2] <= box[0]:
            raise ValueError('positive person box dimensions required')
        body_aspect = (box[2] - box[0]) / box_height
        fallen_posture = (torso_angle <= 40 and hip_drop >= self.drop_fraction and
                          body_aspect >= 1.5)
        upright_posture = torso_angle >= 60 and hip_drop < self.drop_fraction / 2
        event = None
        if not baseline_ready:
            self.state = 'WAIT_BASELINE'
        elif fallen_posture:
            if self.candidate_since is None:
                self.candidate_since = time_s
            if time_s - self.candidate_since >= self.candidate_seconds:
                if self.state != 'SUSPECTED_FALL':
                    event = 'SUSPECTED_FALL'
                self.state = 'SUSPECTED_FALL'
            else:
                self.state = 'CANDIDATE'
            self.recovery_since = None
        elif self.state in ('SUSPECTED_FALL', 'RECOVERING'):
            if upright_posture:
                if self.recovery_since is None:
                    self.recovery_since = time_s
                if time_s - self.recovery_since >= self.recovery_seconds:
                    event = 'RECOVERED'
                    self.state = 'UPRIGHT'
                    self.candidate_since = None
                    self.recovery_since = None
                else:
                    self.state = 'RECOVERING'
            else:
                self.state = 'SUSPECTED_FALL'
                self.recovery_since = None
        else:
            self.state = 'UPRIGHT' if upright_posture else 'POSTURE_CHANGED'
            self.candidate_since = None

        if (self.state in ('UPRIGHT', 'WAIT_BASELINE') and torso_angle >= 60 and
                (not baseline_ready or upright_posture)):
            self.upright.append((time_s, hip_y / height))
            while self.upright and time_s - self.upright[0][0] > 1.0:
                self.upright.popleft()
        return dict(time_s=time_s, state=self.state, event=event,
                    hip_drop=round(hip_drop, 4), torso_angle_deg=round(torso_angle, 2),
                    body_aspect=round(body_aspect, 3))


def replay(source, output):
    monitor = PoseFallMonitor()
    with Path(source).open(encoding='utf-8') as input_stream, \
            Path(output).open('x', encoding='utf-8') as output_stream:
        for line in input_stream:
            frame = json.loads(line)
            result = monitor.update(frame['time_s'], frame['people'],
                                    *frame['image_size'])
            output_stream.write(json.dumps(result) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.input.resolve() == args.output.resolve() or args.output.exists():
        parser.error('input and new output must be different')
    replay(args.input, args.output)
