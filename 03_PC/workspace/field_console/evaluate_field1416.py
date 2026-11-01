"""Score human video review against the recorded live detector and alarm outputs."""
from pathlib import Path
from collections import Counter
from datetime import datetime
import argparse
import hashlib
import json
import math
import subprocess
import sys

# Reuse the existing one-to-one event scorer; never replay a different detector.
_metrics_path = str(Path(__file__).resolve().parent.parent/'artifacts/pose_model_20261017')
sys.path.insert(0, _metrics_path)
try:
    from evaluate_fall_events import score_events
finally:
    sys.path.remove(_metrics_path)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    with Path(path).open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def rows(path):
    with Path(path).open(encoding='utf-8') as source:
        for line in source:
            yield json.loads(line)


def percentile(values, fraction):
    if not values:
        return None
    ordered = sorted(values)
    position = (len(ordered)-1)*fraction
    low = int(position)
    return ordered[low]+(ordered[min(low+1, len(ordered)-1)]-ordered[low])*(position-low)


def summary(values):
    return dict(count=len(values), median=percentile(values, .5), p95=percentile(values, .95))


def load_session(directory):
    """Read only: bind source IDs, actual poses, recording manifests and MKV packets."""
    directory = Path(directory).resolve()
    report_path = directory/'report.json'
    report = json.loads(report_path.read_text(encoding='utf-8'))
    require(report['state'] == 'FIELD_PC_SESSION_PASS', '仅支持已成功结束并归档的会话')
    sources = {}
    source_rows = []
    for row in rows(directory/'source.frames.jsonl'):
        frame = row['frame_id']
        require(type(frame) is int and frame >= 0 and (not sources or frame == next(reversed(sources))+1), '源帧号不连续')
        sources[frame] = row['jpeg_sha256']
        source_rows.append(row)
    require(len(sources) == report['frames'] and len(sources) > 1, '源帧计数与报告不符')
    times = {}
    for row in rows(directory/'source.timestamps.jsonl'):
        fields = row.split()
        require(len(fields) == 5 and fields[0] == 'FRAME', '板端帧时戳格式错误')
        frame, stamp = int(fields[1]), float(fields[4])
        require(frame in sources and frame not in times and math.isfinite(stamp) and stamp >= 0,
                '板端时戳缺帧、重复或非有限')
        require(not times or (frame > next(reversed(times)) and stamp > times[next(reversed(times))]), '板端时戳未递增')
        times[frame] = stamp
    require(set(times) == set(sources), '源帧时戳覆盖不完整')
    baseline = times[next(iter(times))]
    duration = times[next(reversed(times))]-baseline
    poses = list(rows(directory/'pose.frames.jsonl'))
    require(bool(poses), '缺少实际模型结果')
    previous = -1
    detector, alarms, latencies, npu = [], [], [], []
    for pose in poses:
        frame = pose['frame_id']
        require(frame > previous and frame in sources and pose['jpeg_sha256'] == sources[frame], '姿态结果与源JPEG不匹配')
        previous = frame
        completed, finished = pose['completed_ns']/1e9, pose['finished_ns']/1e9
        require(math.isfinite(completed) and math.isfinite(finished) and
                abs(completed-times[frame]) < .000002 and finished >= completed, '姿态结果时钟或源时戳不一致')
        latency = (finished-completed)*1000
        require(abs(latency-pose['host_completion_to_result_ms']) < .01, '处理延迟字段不一致')
        require(type(pose['npu_ms']) in (int, float) and math.isfinite(pose['npu_ms']) and pose['npu_ms'] >= 0, '无效NPU耗时')
        latencies.append(latency);npu.append(pose['npu_ms'])
        state = pose['fall_state']
        event = dict(frame_id=frame, source_s=completed-baseline, result_s=finished-baseline)
        if state.get('detector_event') == 'SUSPECTED_FALL':
            detector.append(event)
        if (state.get('alarm_transition') or {}).get('action') == 'OPEN':
            alarms.append(event)
    bindings = {name:digest(directory/name) for name in
                ('report.json', 'source.frames.jsonl', 'source.timestamps.jsonl', 'pose.frames.jsonl')}
    preprocessing=None
    modes=None
    mode_path=directory/'preprocess.frames.jsonl'
    if 'advanced_config' in report.get('remote',{}):
        require(mode_path.is_file(),'缺少高级预处理逐帧记录')
    if mode_path.exists():
        modes={}
        mode_rows=[]
        for row in rows(mode_path):
            frame,mode=row.get('frame_id'),row.get('mode')
            require(type(frame) is int and frame in sources and frame not in modes and
                    type(mode) is int and mode in range(4) and row.get('committed') is True,
                    '预处理模式记录帧号、模式或提交状态无效')
            require(not modes or frame==next(reversed(modes))+1,'预处理记录序号不连续')
            modes[frame]=mode
            mode_rows.append(row)
        require(set(modes)==set(sources),'预处理记录未覆盖全部源帧')
        preprocessing=dict(source_frames_by_mode=dict(Counter(modes.values())),
                           pose_frames_by_mode=dict(Counter(modes[p['frame_id']] for p in poses)),
                           mixed_modes=len(set(modes.values()))>1,
                           scope='事件统计属于整段会话，不能当作单一预处理模式的准确率')
        from threshold1786 import audit_rows
        preprocessing['advanced']=audit_rows(mode_rows,report.get('remote',{}))
        bindings[mode_path.name]=digest(mode_path)
        for name in ('preprocess.events.jsonl','preprocess.latest.json'):
            require((directory/name).is_file(),'预处理切换记录不完整')
            bindings[name]=digest(directory/name)
    from compression_audit1780 import audit_compression
    compression, compression_bindings = audit_compression(directory, source_rows, times, modes, report)
    bindings.update(compression_bindings)
    covered, recordings = set(), []
    for clip in report['recordings']:
        name = clip['name']
        require(Path(name).name == name and name.endswith('.mkv'), '录像名称不合法')
        video = directory/name
        manifest = video.with_suffix('.frames.jsonl')
        recorded = list(rows(manifest))
        require(len(recorded) == clip['frames'] and video.stat().st_size == clip['bytes'], '录像长度/计数不匹配')
        for frame in recorded:
            ident = frame['frame_id']
            require(ident in sources and ident not in covered and frame['jpeg_sha256'] == sources[ident], '录像帧不匹配或重复')
            covered.add(ident)
        flags = dict(creationflags=subprocess.CREATE_NO_WINDOW) if sys.platform == 'win32' else {}
        probe = subprocess.run(['ffprobe','-v','error','-select_streams','v:0','-show_packets',
            '-show_entries','packet=data_hash','-show_data_hash','sha256','-of','json',str(video)],
            capture_output=True,text=True,timeout=300,check=True,**flags)
        packets = json.loads(probe.stdout)['packets']
        require([p['data_hash'].split(':',1)[1].lower() for p in packets] ==
                [p['jpeg_sha256'] for p in recorded], 'MKV实际JPEG与录像帧清单不匹配')
        bindings[name] = digest(video);bindings[manifest.name] = digest(manifest)
        recordings.append(dict(name=name, frames=[p['frame_id'] for p in recorded]))
    return dict(directory=str(directory), bindings=bindings, times={frame:stamp-baseline for frame,stamp in times.items()},
                duration_s=duration, source_frames=len(sources), pose_frames=len(poses),
                source_fps=(len(sources)-1)/duration, pose_fps=len(poses)/duration,
                states=dict(Counter(p['fall_state']['state'] for p in poses)),
                npu_ms=summary(npu), completion_to_result_ms=summary(latencies),
                detector_events=detector, alarm_events=alarms, recordings=recordings,
                preprocessing=preprocessing, compression=compression,
                video_coverage_complete=covered == set(sources))


def evaluate(session, annotation):
    require(annotation.get('schema_version') == 1, '复核格式错误')
    require(annotation.get('bindings') == session['bindings'], '复核与当前录像/模型文件不匹配，请重新加载')
    base = {key:session[key] for key in ('duration_s','source_frames','pose_frames','source_fps','pose_fps',
            'states','npu_ms','completion_to_result_ms','video_coverage_complete')}
    base.update(scope='单路养老现场录像的事件级复核；非姿态mAP、临床验证或物理端到端延迟',
                preprocessing=session.get('preprocessing'),
                compression=session.get('compression'),
                physical_latency_verified=False, independent_test_verified=False,
                bindings=session['bindings'], metrics=None,
                implementation_sha256=digest(__file__),
                event_scorer_sha256=digest(Path(_metrics_path)/'evaluate_fall_events.py'),
                alarm_metric_scope='仅统计新增OPEN；既有锁存告警不会重复OPEN，其漏报数与姿态事件漏报须分别解释')
    if annotation.get('reviewed') is not True:
        return dict(base, state='PENDING_HUMAN_VIDEO_REVIEW')
    require(annotation.get('label_origin') == 'manual_video_review' and
            str(annotation.get('reviewer','')).strip(), '需要人工完整录像复核及复核人')
    require(annotation.get('split') in ('development','held_out'), '需要声明开发集或保留测试集')
    require(session['video_coverage_complete'], 'PC录像未覆盖全部源帧，不能将未录像时段标为无跌倒')
    windows = annotation['events']
    require(isinstance(windows, list), '需要明确列出事件；无跌倒时填写空列表')
    # Validate review windows against source duration, separately from result drain time.
    score_events([], windows, session['duration_s'])
    metrics = {}
    for kind in ('detector','alarm'):
        events = session[kind+'_events']
        horizon = max([session['duration_s'], *[row['result_s'] for row in events]])
        score = score_events([row['result_s'] for row in events], windows, horizon)
        score['false_alarms_per_hour'] = score['fp']*3600/session['duration_s']
        score['result_delay_ms'] = summary([row['delay_s']*1000 for row in score['matches']])
        score['events'] = events
        metrics[kind] = score
    return dict(base, state='HUMAN_REVIEWED_FIELD_EVENTS_SCORED', reviewer=annotation['reviewer'],
                split=annotation['split'], metrics=metrics,
                event_latency_basis='人工动作起点对应的板端完整帧时刻→结果完成；含候选确认窗口，不含曝光到收帧')


def export(session, annotation):
    result = evaluate(session, annotation)
    directory = Path(session['directory']).resolve()
    protected = Path('C:/Users/Jupiterw/OneDrive').resolve()
    require(directory != protected and protected not in directory.parents, 'OneDrive目录受保护，无法写入')
    # Recheck all source bytes before persisting human truth or a score.
    require(all(digest(directory/name) == value for name,value in session['bindings'].items()), '源文件在复核期间已改变')
    out = directory/'reviews'/datetime.now().strftime('review_%Y%m%d_%H%M%S_%f')
    resolved = out.resolve()
    require(resolved != protected and protected not in resolved.parents, 'OneDrive目录受保护，无法写入')
    out.mkdir(parents=True, exist_ok=False)
    (out/'annotations.json').write_text(json.dumps(annotation,ensure_ascii=False,indent=2,allow_nan=False),encoding='utf-8')
    (out/'evaluation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2,allow_nan=False),encoding='utf-8')
    lines = ['# 养老动作录像复核', '', '状态：'+result['state'], '', result['scope'], '',
             f"源帧率 {result['source_fps']:.3f}fps；模型吞吐 {result['pose_fps']:.2f}fps。", '',
             '收完帧至结果耗时及动作至结果耗时均不等于镜头到屏幕物理延迟。', '']
    if result.get('preprocessing'):
        pp=result['preprocessing'];names={0:'彩色原图',1:'灰度',2:'高斯滤波',3:'直方图均衡'}
        lines += ['预处理源帧数：'+'；'.join(names[int(k)]+' '+str(v) for k,v in pp['source_frames_by_mode'].items())+'。',
                  pp['scope'],'']
    if result['metrics']:
        lines += ['| 输出 | 命中TP | 误报FP | 漏报FN | 精确率 | 召回率 |', '|---|---:|---:|---:|---:|---:|']
        for key,label in [('detector','姿态事件'),('alarm','新增持久告警')]:
            m = result['metrics'][key]
            display = lambda v:'无定义' if v is None else f'{v:.3f}'
            lines.append(f"| {label} | {m['tp']} | {m['fp']} | {m['fn']} | {display(m['precision'])} | {display(m['recall'])} |")
        lines += ['', '全部原始事件、匹配、延迟和输入哈希见evaluation.json。保留测试集声明不等于独立测试已验证。',
                  '', result['alarm_metric_scope']]
    else:
        lines += ['尚未完成人工完整录像复核，准确率不计算。']
    (out/'复核报告.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    return out, result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('session', type=Path)
    parser.add_argument('--annotations', type=Path)
    args = parser.parse_args()
    data = load_session(args.session)
    annotation = json.loads(args.annotations.read_text(encoding='utf-8')) if args.annotations else dict(
        schema_version=1,bindings=data['bindings'],reviewed=False,reviewer='',
        label_origin='manual_video_review',split='development',events=[])
    path, result = export(data, annotation)
    print(json.dumps(dict(state=result['state'],output=str(path)),ensure_ascii=False))
