"""Export measured session statistics without inventing action ground truth."""
from pathlib import Path
from datetime import datetime
import json
from collections import Counter
from evaluate_field1416 import load_session, digest, rows, summary


MODE_NAMES = {0:'彩色原图', 1:'灰度', 2:'高斯滤波', 3:'直方图均衡'}


def summarize_modes(directory, source):
    """Group by committed source mode, including poses that finish after a switch."""
    path = directory/'preprocess.frames.jsonl'
    if not path.exists():
        return None
    modes = {row['frame_id']:row['mode'] for row in rows(path)}
    poses = list(rows(directory/'pose.frames.jsonl'))
    result = {}
    for mode in sorted(set(modes.values())):
        frames = [row for row in source if modes[row['frame_id']] == mode]
        inferred = [row for row in poses if modes[row['frame_id']] == mode]
        size = sum(row['bytes'] for row in frames)
        result[str(mode)] = dict(name=MODE_NAMES[mode], source_frames=len(frames),
            pose_frames=len(inferred), jpeg_bytes=size, mean_jpeg_bytes=size/len(frames),
            theoretical_rgb888_to_jpeg_ratio=len(frames)*1920*1080*3/size,
            npu_ms=summary([row['npu_ms'] for row in inferred]),
            completion_to_result_ms=summary([row['host_completion_to_result_ms'] for row in inferred]),
            states=dict(Counter(row['fall_state']['state'] for row in inferred)),
            accuracy=None)
    return result


def export_summary(directory):
    directory = Path(directory).resolve()
    protected = Path('C:/Users/Jupiterw/OneDrive').resolve()
    if directory == protected or protected in directory.parents:
        raise ValueError('OneDrive目录受保护')
    session = load_session(directory)
    remote_report=json.loads((directory/'report.json').read_text(encoding='utf-8')).get('remote',{})
    source = list(rows(directory/'source.frames.jsonl'))
    jpeg_bytes = sum(row['bytes'] for row in source)
    span_bytes = sum(row['bytes'] for row in source[1:])
    telemetry_path = directory/'telemetry.jsonl'
    if telemetry_path.exists():
        session['bindings'][telemetry_path.name] = digest(telemetry_path)
    telemetry = list(rows(telemetry_path)) if telemetry_path.exists() else []
    health = {}
    for key in ('cpu_percent', 'memory_percent', 'temperature_c'):
        values = [row[key] for row in telemetry if isinstance(row.get(key), (int, float))]
        health[key] = dict(mean=sum(values)/len(values), maximum=max(values)) if values else None
    result = {key:session[key] for key in ('source_frames','pose_frames','duration_s','source_fps','pose_fps',
              'states','npu_ms','completion_to_result_ms','video_coverage_complete','preprocessing','compression','bindings')}
    result.update(schema_version=2, state='PERFORMANCE_ONLY_NOT_ACCURACY',
                  hdmi_enabled=remote_report.get('hdmi_enabled',True),
                  pose_remedy=remote_report.get('pose',{}).get('pose_remedy'),
                  implementation_sha256={name:digest(Path(__file__).parent/name) for name in
                      ('session_summary1694.py','evaluate_field1416.py','compression_audit1780.py','threshold1786.py')},
                  session=directory.name, jpeg_bytes=jpeg_bytes,
                  interval_jpeg_mbps=span_bytes*8/session['duration_s']/1e6,
                  theoretical_rgb888_to_jpeg_ratio=len(source)*1920*1080*3/jpeg_bytes,
                  detector_event_count=len(session['detector_events']),
                  new_alarm_count=len(session['alarm_events']), health=health,
                  by_preprocessing=summarize_modes(directory, source),
                  preprocessing_comparison_scope='按实际源帧模式分组；不同时间拍摄，不能视为同源画质或识别准确率对照；RGB888为统一理论基准',
                  accuracy=None, physical_latency_verified=False,
                  scope='实测运行统计；RGB888压缩比是理论未压缩基准；无人工真值不计算准确率；帧率分母为首尾源帧间隔')
    if not all(digest(directory/name) == value for name,value in session['bindings'].items()):
        raise ValueError('导出期间输入已变化')
    out=directory/'summaries'/datetime.now().strftime('%Y%m%d_%H%M%S_%f')
    out.mkdir(parents=True,exist_ok=False)
    (out/'performance.json').write_text(json.dumps(result,ensure_ascii=False,indent=2,allow_nan=False),encoding='utf-8')
    lines=['# 会话性能汇总', '', directory.name, '',
           '| 指标 | 实测 |','|---|---:|',
           f"| 采集完整帧率 | {session['source_fps']:.3f} fps |",
           f"| 模型吞吐 | {session['pose_fps']:.3f} fps |",
           f"| NPU 中位 / P95 | {session['npu_ms']['median']:.2f} / {session['npu_ms']['p95']:.2f} ms |",
           f"| 收完帧到结果 中位 / P95 | {session['completion_to_result_ms']['median']:.2f} / {session['completion_to_result_ms']['p95']:.2f} ms |",
           f"| JPEG载荷 | {result['interval_jpeg_mbps']:.3f} Mbps |",
           f"| 理论RGB888/JPEG体积比 | {result['theoretical_rgb888_to_jpeg_ratio']:.2f}:1 |",
           f"| 源帧 / 推理帧 | {session['source_frames']} / {session['pose_frames']} |",
           f"| PC录像完整覆盖 | {session['video_coverage_complete']} |", '',
           '识别准确率未计算：需独立人工复核。收完帧到结果不等于镜头到屏幕或动作到报警延迟。',
           ('HDMI未启用，本次仅验证PC预览、录像和RK检测。' if not result['hdmi_enabled'] else '当前汇总未测光学HDMI帧率。')+'未测功耗或FPGA资源；资源引用对应位流的布局布线报告。', '',
           '状态分布：'+json.dumps(session['states'],ensure_ascii=False)]
    if result['by_preprocessing']:
        advanced=(session.get('preprocessing') or {}).get('advanced')
        if advanced:
            lines += ['', 'FPGA高级处理：'+advanced['name']+
                      (f"，阈值{advanced['advanced_threshold']}" if advanced['advanced_mode']==2 else '')+'；'+advanced['scope']]
        display = lambda v:'无推理帧' if v is None else f'{v:.2f}'
        lines += ['', '| 预处理 | 源帧 / 推理帧 | 平均JPEG KiB | NPU中位 ms | 收完帧到结果P95 ms |',
                  '|---|---:|---:|---:|---:|']
        for row in result['by_preprocessing'].values():
            lines.append(f"| {row['name']} | {row['source_frames']} / {row['pose_frames']} | {row['mean_jpeg_bytes']/1024:.2f} | {display(row['npu_ms']['median'])} | {display(row['completion_to_result_ms']['p95'])} |")
        lines += ['', result['preprocessing_comparison_scope']]
    if result['compression']:
        compression=result['compression']
        label=('历史记录（压缩反馈未验证）' if not compression['source_identity_verified'] else
               '固定质量' if compression['strategy']=='quality' else f"目标平均 {compression['target_average_mbps']:g} Mbps")
        lines += ['', '压缩策略：'+label+'；实际质量帧数：'+json.dumps(compression['actual_quality_counts'],ensure_ascii=False),
                  '', '| 连续模式区间（源帧） | 预处理 | 帧数 | 时长 s | JPEG Mbps |', '|---|---|---:|---:|---:|']
        for run in compression['runs']:
            rate='无区间' if run['interval_jpeg_mbps'] is None else f"{run['interval_jpeg_mbps']:.3f}"
            lines.append(f"| {run['first_frame']}–{run['last_frame']} | {MODE_NAMES[run['mode']]} | {run['frames']} | {run['duration_s']:.3f} | {rate} |")
        lines += ['', compression['scope']]
    (out/'性能汇总.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    return out, result
