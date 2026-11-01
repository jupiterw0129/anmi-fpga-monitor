"""Read-only Pi geometry hints for PC presentation; never alter fall state/events.

Angles are measured FROM VERTICAL, unlike pose_fall1806's horizontal angle.
Features and raw classify follow Pi/scripts/pose_features.py. Display requires
consistent body/leg evidence; no learned classifier or fall decision is added.
"""
import math

VERSION = 'pi-posture-hints-pc-v1'


def features(person, confidence=.4):
    points = person.get('keypoints_xyc', [])
    box = person.get('box_xyxy', [])
    if len(points) != 17 or len(box) != 4:
        return None
    if (not all(len(p) == 3 and all(isinstance(v, (int, float)) and math.isfinite(v) for v in p) for p in points)
            or not all(isinstance(v, (int, float)) and math.isfinite(v) for v in box)):
        return None
    width, height = box[2]-box[0], box[3]-box[1]
    if width <= 0 or height <= 0:
        return None

    def midpoint(a, b):
        if min(points[a][2], points[b][2]) < confidence:
            return None
        return ((points[a][0]+points[b][0])/2, (points[a][1]+points[b][1])/2)

    def vertical_angle(a, b):
        if a is None or b is None or math.hypot(b[0]-a[0], b[1]-a[1]) < 1e-7:
            return None
        return math.degrees(math.atan2(abs(b[0]-a[0]), abs(b[1]-a[1])))

    def knee(a, b, c):
        if min(points[i][2] for i in (a, b, c)) < confidence:
            return None
        u = (points[a][0]-points[b][0], points[a][1]-points[b][1])
        v = (points[c][0]-points[b][0], points[c][1]-points[b][1])
        den = math.hypot(*u)*math.hypot(*v)
        if den < 1e-7:
            return None
        return math.degrees(math.acos(max(-1, min(1, (u[0]*v[0]+u[1]*v[1])/den))))

    shoulder, hip, ankle = midpoint(5, 6), midpoint(11, 12), midpoint(15, 16)
    knees = [v for v in (knee(11, 13, 15), knee(12, 14, 16)) if v is not None]
    return dict(box_aspect_ratio=width/height, torso_angle_deg=vertical_angle(shoulder, hip),
                body_angle_deg=vertical_angle(shoulder, ankle),
                knee_angle_deg=sum(knees)/len(knees) if knees else None,
                visible_keypoints=sum(p[2] >= confidence for p in points))


def classify(value):
    if value is None or value['torso_angle_deg'] is None:
        return 'insufficient_keypoints'
    torso, body, knee, aspect = (value[k] for k in
        ('torso_angle_deg', 'body_angle_deg', 'knee_angle_deg', 'box_aspect_ratio'))
    if torso >= 55 and aspect >= .9:
        return 'horizontal_candidate'
    if knee is not None and knee <= 135 and torso <= 45:
        return 'seated_candidate'
    if knee is not None and knee >= 145 and torso <= 20 and aspect >= .48:
        return 'bending_candidate'
    if torso <= 30 and aspect < .48 and (body is None or body <= 35):
        return 'upright_candidate'
    return 'uncertain_pose'


def display_classify(value):
    """Conservative display adaptation; raw Pi hint is retained for audit only."""
    if value is None or value['torso_angle_deg'] is None:
        return 'insufficient_keypoints'
    torso, body, knee, aspect = (value[k] for k in
        ('torso_angle_deg', 'body_angle_deg', 'knee_angle_deg', 'box_aspect_ratio'))
    # A horizontal torso alone also occurs when crouching. Require the body
    # axis and extended legs to support a horizontal posture description.
    if torso >= 55 and aspect >= .9:
        return ('horizontal_candidate' if body is not None and body >= 55
                and knee is not None and knee >= 145 else 'uncertain_pose')
    if knee is not None and knee <= 135 and torso <= 45:
        return 'seated_candidate'
    # Pi's wide-box + near-vertical rule could label sitting as bending.
    # For this display, require an inclined torso and extended legs instead.
    if 30 < torso < 55 and knee is not None and knee >= 145:
        return 'bending_candidate'
    if torso <= 30 and aspect < .48 and (body is None or body <= 35):
        return 'upright_candidate'
    return 'uncertain_pose'


LABELS = dict(upright_candidate='疑似直立', seated_candidate='疑似坐姿',
              bending_candidate='疑似弯腰', horizontal_candidate='疑似躺卧',
              insufficient_keypoints='关键点不足', uncertain_pose='姿态不明确')


class PostureHints:
    """Require three distinct observations over 0.4 s; resets on uncertainty."""
    def __init__(self):
        self.session = None
        self.last_frame = None
        self.pending = None
        self.since = None
        self.count = 0
        self.text = '姿态提示：—'

    def update(self, session, phase, pose, fresh, replay=False):
        raw = describe(phase, pose, fresh, replay)
        if session != self.session:
            self.__init__();self.session = session
        if '疑似' not in raw:
            self.pending = None;self.since = None;self.count = 0;self.last_frame = None
            self.text = raw
            return raw
        frame = pose.get('frame_id')
        stamp = pose.get('completed_ns')
        if not isinstance(frame, int) or not isinstance(stamp, int):
            return '姿态提示：等待有效帧'
        if frame == self.last_frame:
            return self.text
        if self.last_frame is not None and frame < self.last_frame:
            self.pending = None
        self.last_frame = frame
        if raw != self.pending or self.since is None or stamp < self.since:
            self.pending = raw;self.since = stamp;self.count = 0
        self.count += 1
        self.text = raw if self.count >= 3 and stamp-self.since >= 400_000_000 else '姿态提示：变化中'
        return self.text


def describe(phase, pose, fresh, replay=False):
    if replay:
        return '姿态提示：回放不作实时判断'
    if phase != 'RUNNING':
        return '姿态提示：—'
    if not fresh or not pose:
        return '姿态提示：等待新结果'
    state = pose.get('fall_state', {}).get('state')
    people = pose.get('people', [])
    if len(people) > 1 or state == 'AMBIGUOUS':
        return '姿态提示：多人，无法判断'
    if not people:
        return '姿态提示：未见人体'
    if people[0].get('confidence', 0) < .5:
        return '姿态提示：人体置信度不足'
    if state == 'UNCERTAIN':
        return '姿态提示：遮挡或边缘，无法判断'
    return '姿态提示：'+LABELS[display_classify(features(people[0]))]
