"""Decode the newest JPEG near the next consumer opportunity; one pending image."""
import time
from latest_decode1722 import LatestDecode as ContinuousDecode


class LatestDecode(ContinuousDecode):
    def __init__(self, source, decode):
        super().__init__(source, decode)
        self.last_take = None
        self.period = .065
        self.decode_seconds = .030

    def _run(self):
        try:
            while not self.stopping.is_set():
                with self.condition:
                    # Never spend CPU decoding replacements while an image waits.
                    while not self.stopping.is_set():
                        if self.slot is not None:
                            self.condition.wait()
                            continue
                        target = (self.last_take + self.period - self.decode_seconds - .002
                                  if self.last_take is not None else time.monotonic())
                        delay = target - time.monotonic()
                        if delay <= 0:
                            break
                        self.condition.wait(delay)
                    if self.stopping.is_set():
                        break
                # Select the raw source only after the scheduling wait.
                row = self.source(self.last)
                if row is None:
                    self.stopping.wait(.002)
                    continue
                if self.last is not None and row[0] <= self.last:
                    raise ValueError('Decoded source frame IDs must strictly increase')
                started = time.monotonic()
                result = self.decode(row)
                duration = time.monotonic() - started
                if result[0] != row[0]:
                    raise ValueError('Decoder changed source frame identity')
                with self.condition:
                    self.decode_seconds = .8*self.decode_seconds + .2*duration
                    self.last = row[0]
                    self.decoded += 1
                    if self.stopping.is_set():
                        self.discarded += 1
                    else:
                        assert self.slot is None
                        self.slot = result
                    self.condition.notify_all()
        except BaseException as error:
            with self.condition:
                self.error = error
                self.condition.notify_all()

    def take(self, timeout=.01):
        with self.condition:
            row = super().take(timeout)
            if row is not None:
                now = time.monotonic()
                if self.last_take is not None:
                    # Clamp only the predictor, never timestamps or reported latency.
                    observed = min(.150, max(.020, now-self.last_take))
                    self.period = .8*self.period + .2*observed
                self.last_take = now
                self.condition.notify_all()
            return row

    def close(self):
        stats = super().close()
        stats.update(scheduling='consumer_period_minus_decode_duration',
                     predicted_period_ms=self.period*1000,
                     predicted_decode_ms=self.decode_seconds*1000)
        return stats
