"""Unblock PC stream reads when the independent board controller has failed."""
import threading

def guard_reader(control, reader, done):
    def watch():
        while not done.wait(.1):
            code=control.poll()
            if code is None:continue
            if code!=0 and reader.poll() is None:
                try:reader.terminate()
                except ProcessLookupError:pass
            return
    worker=threading.Thread(target=watch,name='board-failure-stream-guard',daemon=True)
    worker.start()
    return worker
