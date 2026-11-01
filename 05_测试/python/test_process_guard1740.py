"""A real blocking pipe must close after controller failure; normal exit survives."""
import subprocess,sys,threading,time
from process_guard1740 import guard_reader
for code in (7,0):
    reader=subprocess.Popen([sys.executable,'-B','-c','import time;time.sleep(20)'],stdout=subprocess.PIPE)
    control=subprocess.Popen([sys.executable,'-B','-c',f'raise SystemExit({code})'])
    done=threading.Event();watch=guard_reader(control,reader,done)
    try:
        control.wait(timeout=3)
        if code:
            reader.wait(timeout=3);assert reader.stdout.read(1)==b''
        else:
            watch.join(timeout=2);assert not watch.is_alive() and reader.poll() is None
    finally:
        done.set();watch.join(timeout=2)
        if reader.poll() is None:reader.terminate()
        reader.wait(timeout=3);reader.stdout.close()
assert not watch.is_alive()
print('PROCESS1740_REAL_BLOCKED_PIPE_FAILURE_AND_NORMAL_EXIT_PASS')
