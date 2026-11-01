"""Fall-scene timing and persistent alarms for a latest-frame AI consumer."""
import math

from alarm723 import AlarmMonitor
from pose_fall import PoseFallMonitor


def alarm_banner(active):
    if active is None:
        return None
    return f"FALL ALERT #{active['id']} {active['status']} - CHECK PERSON"


class FallScene:
    """Single inference-thread owner; source timestamps share host monotonic clock."""
    def __init__(self, store, session):
        self.store, self.session = store, session
        self.monitor = AlarmMonitor(PoseFallMonitor(), store, session)
        self.last_frame = None
        self.last_source = None
        self.expired = False

    @staticmethod
    def valid_time(value):
        if not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
            raise ValueError('finite nonnegative monotonic timestamp required')

    def expire(self, now):
        self.valid_time(now)
        if self.last_source is None or now - self.last_source <= self.monitor.detector.missing_seconds:
            return None
        self.expired = True
        self.monitor.owns_incident = False
        return self.store.apply('HOLD', self.session, now, 'AI observation gap exceeds 0.5 seconds')

    def update(self, frame_id, source_time, people, width, height):
        self.valid_time(source_time)
        if (not isinstance(frame_id, int) or isinstance(frame_id, bool) or frame_id < 0
                or (self.last_frame is not None and frame_id <= self.last_frame)
                or (self.last_source is not None and source_time <= self.last_source)
                or width <= 0 or height <= 0):
            raise ValueError('increasing frame ID/source timestamp and positive dimensions required')
        gap_transition = self.expire(source_time)
        if self.expired:
            # A gap must not join a pre-gap candidate/recovery to a different person.
            self.monitor = AlarmMonitor(PoseFallMonitor(), self.store, self.session)
        result = self.monitor.update(source_time, people, width, height)
        self.last_frame, self.last_source, self.expired = frame_id, source_time, False
        result.update(source_frame_id=frame_id, source_completed_monotonic=source_time,
                      observation_gap_transition=gap_transition)
        return result

    def stop(self, now):
        self.valid_time(now)
        self.monitor.owns_incident = False
        return self.store.apply('HOLD', self.session, now, 'AI consumer stopped; verify person manually')
