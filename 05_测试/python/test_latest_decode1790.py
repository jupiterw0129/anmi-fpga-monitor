"""Check bounded scheduling, latest-source selection, errors and stop wake-up."""
import queue,threading,time
from latest_decode1790 import LatestDecode


def until(pipeline,predicate):
    with pipeline.condition:
        assert pipeline.condition.wait_for(predicate,2)


def failed(pipeline):
    try:pipeline.close()
    except RuntimeError as error:assert isinstance(error.__cause__,(OSError,ValueError))
    else:raise AssertionError('late decoder error swallowed')


current=[(1,)];calls=[]
def latest(last):
    calls.append(current[0][0])
    return current[0] if last is None or current[0][0]>last else None
p=LatestDecode(latest,lambda row:row).start()
until(p,lambda:p.decoded==1)
# A pending image suppresses further source reads and decode work.
current[0]=(2,)
time.sleep(.04)
assert calls==[1] and p.decoded==1
with p.condition:
    p.period=.120;p.decode_seconds=.005
assert p.take()==(1,)
time.sleep(.020)
assert calls==[1], 'source sampled before scheduled decode start'
current[0]=(3,)
assert p.take(2)==(3,), 'scheduled decoder did not select newest raw source'
stats=p.close();assert stats['taken']==2 and stats['replaced_latest']==0
assert not p.thread.is_alive()

# Closing while the scheduler waits must wake it immediately.
p=LatestDecode(lambda last:(1,) if last is None else None,lambda row:row).start()
assert p.take(2)==(1,)
started=time.monotonic();p.close();assert time.monotonic()-started<1

for decoder in (lambda row:(row[0]+1,),lambda row:(_ for _ in ()).throw(OSError('bad JPEG'))):
    p=LatestDecode(lambda last:(1,),decoder).start()
    until(p,lambda:p.error is not None)
    try:p.take()
    except RuntimeError:pass
    else:raise AssertionError('decoder error swallowed by take')
    failed(p)

pending=queue.Queue();pending.put((1,));pending.put((1,))
def source(last):
    try:return pending.get_nowait()
    except queue.Empty:return None
p=LatestDecode(source,lambda row:row).start();assert p.take(2)==(1,)
until(p,lambda:p.error is not None);failed(p)

entered=threading.Event();release=threading.Event()
def blocked(row):
    entered.set();assert release.wait(2);return row
p=LatestDecode(lambda last:(1,),blocked).start();assert entered.wait(2)
assert p.take(.001) is None
p.stopping.set();release.set();stats=p.close()
assert stats['discarded_on_stop']==1 and stats['taken']==0
print('SCHEDULE1790_LATEST_SOURCE_PENDING_STOP_IDENTITY_AND_ERRORS_PASS')
