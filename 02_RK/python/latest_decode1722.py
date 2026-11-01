"""One decoded latest-frame slot; the NPU/scene remains a single consumer."""
import threading


class LatestDecode:
    def __init__(self, source, decode):
        self.source = source
        self.decode = decode
        self.condition = threading.Condition()
        self.stopping = threading.Event()
        self.slot = None
        self.error = None
        self.last = None
        self.decoded = self.taken = self.replaced = self.discarded = 0
        self.thread = threading.Thread(target=self._run, name='latest-jpeg-decode', daemon=True)

    def start(self):
        self.thread.start()
        return self

    def _run(self):
        try:
            while not self.stopping.is_set():
                row = self.source(self.last)
                if row is None:
                    self.stopping.wait(.002)
                    continue
                if self.last is not None and row[0] <= self.last:
                    raise ValueError('Decoded source frame IDs must strictly increase')
                result = self.decode(row)
                if result[0] != row[0]:
                    raise ValueError('Decoder changed source frame identity')
                with self.condition:
                    self.last = row[0]
                    self.decoded += 1
                    if self.stopping.is_set():
                        self.discarded += 1
                    else:
                        if self.slot is not None:
                            self.replaced += 1
                        self.slot = result
                    self.condition.notify_all()
        except BaseException as error:
            with self.condition:
                self.error = error
                self.condition.notify_all()

    def take(self, timeout=.01):
        with self.condition:
            self.condition.wait_for(lambda:self.slot is not None or self.error is not None or self.stopping.is_set(), timeout)
            if self.error is not None:
                raise RuntimeError('Latest-frame JPEG decoder failed') from self.error
            row, self.slot = self.slot, None
            if row is not None:
                self.taken += 1
            return row

    def close(self):
        self.stopping.set()
        with self.condition:
            self.condition.notify_all()
        self.thread.join(timeout=5)
        if self.thread.is_alive():
            raise RuntimeError('JPEG decoder did not stop; leave shared mapping open until process exit')
        with self.condition:
            if self.slot is not None:
                self.discarded += 1
                self.slot = None
            if self.error is not None:
                raise RuntimeError('Latest-frame JPEG decoder failed before close') from self.error
            return dict(decoded=self.decoded, taken=self.taken, replaced_latest=self.replaced,
                        discarded_on_stop=self.discarded, maximum_pending_decoded_frames=1,
                        scope='Latest-frame AI sampling; replacements are not capture/recording drops')
