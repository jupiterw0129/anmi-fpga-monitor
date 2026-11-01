"""Live inference throughput from producer counts, independent of journal flushes."""
from collections import deque


class ObservationRate:
    def __init__(self, window_ns=2_000_000_000):
        self.window_ns=window_ns
        self.samples=deque()

    def update(self, count, finished_ns, now_ns):
        if any(type(value) is not int for value in (count,finished_ns,now_ns)) or count<1 or not 0<finished_ns<=now_ns:
            raise ValueError('Positive producer count and monotonic completion clock required')
        if self.samples:
            old_count,old_time=self.samples[-1]
            if count<old_count or finished_ns<old_time or (count==old_count)!=(finished_ns==old_time):
                raise ValueError('Producer counter and completion timestamp must advance together')
        if not self.samples or count>self.samples[-1][0]:
            self.samples.append((count,finished_ns))
        while len(self.samples)>2 and self.samples[1][1]<=finished_ns-self.window_ns:
            self.samples.popleft()
        if now_ns-finished_ns>self.window_ns:
            return 0.0
        if len(self.samples)<2:
            return None
        first,last=self.samples[0],self.samples[-1]
        return (last[0]-first[0])*1e9/(last[1]-first[1])
