"""Replay completed-JPEG arrivals through a bounded constant-rate FIFO.

Uses only board-local completion timestamps. This measures a proposed output
shaper's queue requirements, not FPGA throughput or physical camera latency.
An empty queue stays idle; no stuffing, frame dropping or invented payload.
"""
import argparse,hashlib,json,math
from pathlib import Path


def evaluate(rows,target_mbps):
    if not math.isfinite(target_mbps) or target_mbps<=0:raise ValueError('Invalid link rate')
    rate=target_mbps*1e6/8
    previous=None;first=None;backlog=0.;peak=0.;delay=0.;idle=0.;total=0;count=0
    last_index=None;worst=None;trace=[]
    for row in rows:
        index=row['index'];size=row['frame_bytes'];stamp=row['completed_s']
        if type(index) is not int or (last_index is not None and index!=last_index+1):raise ValueError('Source frame gap')
        if type(size) is not int or size<4:raise ValueError('Invalid completed JPEG size')
        if not isinstance(stamp,(int,float)) or isinstance(stamp,bool) or not math.isfinite(stamp):raise ValueError('Invalid timestamp')
        if previous is not None:
            interval=stamp-previous
            if interval<=0:raise ValueError('Non-increasing completion timestamps')
            idle+=max(0.,interval-backlog/rate)
            backlog=max(0.,backlog-interval*rate)
        else:first=stamp
        backlog+=size;latency=backlog/rate
        if latency>delay:delay=latency;worst=index
        peak=max(peak,backlog);total+=size;count+=1
        trace.append(dict(index=index,completed_s=stamp,queued_bytes=backlog,completion_to_shaped_last_byte_ms=latency*1000))
        previous=stamp;last_index=index
    if count<2:raise ValueError('Need at least two completed JPEGs')
    duration=previous-first
    result=dict(frames=count,target_mbps=target_mbps,observed_completion_span_s=duration,
        total_jpeg_bytes=total,peak_fifo_bytes=math.ceil(peak),
        max_completion_to_shaped_last_byte_ms=delay*1000,worst_frame=worst,
        idle_before_last_arrival_s=idle,tail_drain_s=backlog/rate,
        elapsed_from_first_completion_through_final_departure_s=duration+backlog/rate,
        delay_budget_results={str(ms):dict(passed=delay*1000<=ms,
            frames_exceeding=sum(t['completion_to_shaped_last_byte_ms']>ms for t in trace)) for ms in (10,25,50,100,200)},
        continuously_busy_between_first_last_arrival=idle==0,
        exact_cbr_verified=False,hardware_shaper_implemented=False,physical_latency_verified=False,
        meaning='hypothetical work-conserving payload FIFO; no claim of hardware CBR or indefinite stability')
    return result,trace


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('session',type=Path);parser.add_argument('--mbps',type=float,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();report=args.session/'report.json';feedback=args.session/'compression.frames.jsonl'
    original=json.loads(report.read_text());assert original['state']=='FIELD_PC_SESSION_PASS'
    rows=[json.loads(s) for s in feedback.read_text().splitlines()]
    assert len(rows)==original['frames']
    result,trace=evaluate(rows,args.mbps)
    result['inputs']={str(p.resolve()):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),report,feedback)}
    args.output.mkdir(parents=True,exist_ok=False)
    (args.output/'trace.jsonl').write_text(''.join(json.dumps(row)+'\n' for row in trace))
    (args.output/'result.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2))


if __name__=='__main__':main()
