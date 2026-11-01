"""Queue recurrence, mode continuity and bounded closed-loop debt repayment."""
from pathlib import Path
import hashlib,json,random
from rate_control1608 import Controller
from rate_control1597 import Controller as Baseline
from rate_buffer1579 import evaluate
F=Path(__file__).resolve().parent;A=F.parent/'artifacts';O=A/'rate1609_20261029';O.mkdir(exist_ok=False)
prior=A/'entropy_acceptance1591_20261029/status.json'
gap=next(t for t in json.loads(prior.read_text())['trials'] if t['label']=='target26_gap')
samples={r['quality']:r['mean_mbps']*1e6/8/60 for r in gap['quality_rate_samples'] if r['mode']==3}


def plant(q,scale):
    keys=sorted(samples)
    if q in samples:return samples[q]*scale
    for a,b in zip(keys,keys[1:]):
        if a<q<b:return (samples[a]+(samples[b]-samples[a])*(q-a)/(b-a))*scale
    return samples[keys[0]]*q/keys[0]*scale if q<keys[0] else samples[keys[-1]]*q/keys[-1]*scale


def run(cls,target,delay,scenario):
    c=cls(target,qualities=tuple(range(1,76)));rng=random.Random(1604)
    schedule={};quality=50;rows=[];stamp=100.
    for i in range(7200):
        stamp+=1/60+rng.uniform(-.0002,.0002)
        quality=schedule.pop(i,quality)
        mode=0 if scenario=='mode' and i>=3600 else 3
        scale=1 if i<3600 or scenario=='static' else (1.7 if scenario=='burst' else .7)
        size=max(4,round(plant(quality,scale)*(1+rng.uniform(-.003,.003))))
        if cls is Controller:row=c.observe(i,size,quality,mode,stamp)
        else:row=c.observe(i,size,quality,mode)
        row.update(frame_bytes=size,completed_s=stamp);rows.append(row)
        if row['requested_quality'] is not None:
            schedule[i+delay]=row['requested_quality'];c.issued_frontier(i)
    budget,trace=evaluate(rows,target)
    if cls is Controller:
        assert all(abs(t['queued_bytes']-r['virtual_queue_bytes'])<.00001 for t,r in zip(trace,rows))
        if scenario=='mode':assert rows[3600]['mode_changed'] and rows[3600]['virtual_queue_bytes']>=rows[3600]['frame_bytes']
    windows=[sum(r['frame_bytes'] for r in rows[i:i+60])*8/1e6 for i in range(6600,7141)]
    return dict(target_mbps=target,delay_frames=delay,scenario=scenario,max_delay_ms=budget['max_completion_to_shaped_last_byte_ms'],
        final_queue_delay_ms=trace[-1]['completion_to_shaped_last_byte_ms'],
        last10s_max_queue_delay_ms=max(t['completion_to_shaped_last_byte_ms'] for t in trace[6600:]),
        last10s_min_one_second_mbps=min(windows),last10s_max_one_second_mbps=max(windows)),rows


out=dict(state='RATE1609_RUNNING',plants=[],baselines=[],board_changed=False,exact_cbr=False)
try:
    for target in (26,36):
        baseline,_=run(Baseline,target,2,'static');out['baselines'].append(baseline)
        for delay in (1,2,8):
            for scenario in ('static','burst','mode'):
                result,rows=run(Controller,target,delay,scenario)
                assert result['last10s_max_queue_delay_ms']<100,result
                assert target*.95<=result['last10s_min_one_second_mbps']<=result['last10s_max_one_second_mbps']<=target*1.05,result
                out['plants'].append(result)
    # Invalid or duplicate times, a frame gap, and nine delayed old-Q frames
    # beyond the real command frontier cannot clear or excuse debt.
    c=Controller(8,qualities=tuple(range(1,76)))
    for i in range(3):row=c.observe(i,200000,50,3,i/60)
    assert row['requested_quality'] is not None;c.issued_frontier(25)
    for i in range(3,34):c.observe(i,200000,50,3,i/60)
    try:c.observe(34,200000,50,3,34/60)
    except ValueError:pass
    else:raise AssertionError('Late old DQT accepted')
    for stamp in (float('nan'),float('inf'),True,-1,0):
        c=Controller(26);c.observe(0,1000,50,3,0)
        before=(c.virtual_queue_bytes,c.previous_completion)
        try:c.observe(1,1000,50,3,stamp)
        except ValueError:pass
        else:raise AssertionError(stamp)
        assert before==(c.virtual_queue_bytes,c.previous_completion)
    out.update(state='RATE1609_TIMESTAMPED_FIFO_RECURRENCE_LONG_DEBT_MODE_SCENE_AND_QUEUE_GUARDS_PASS',
        inputs={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),F/'rate_control1608.py',F/'rate_control1605.py',F/'rate_control1597.py',F/'rate_buffer1579.py',prior)})
except BaseException as error:
    out.update(state='RATE1609_FAILED',error=repr(error));raise
finally:(O/'status.json').write_text(json.dumps(out,indent=2))
print(json.dumps(out,indent=2))
