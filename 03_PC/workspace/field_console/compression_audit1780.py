"""Bind committed compression feedback to the archived source, not UI requests."""
import json
import math
from collections import Counter


def audit_compression(directory, source, times, modes, report):
    from evaluate_field1416 import rows, digest, require
    paths = [directory/name for name in ('compression.frames.jsonl', 'compression.latest.json')]
    remote = report.get('remote', {})
    if not any(path.exists() for path in paths) and 'compression_result' not in remote:
        return None, {}
    require(all(path.is_file() for path in paths), '压缩反馈文件不完整')
    bindings = {path.name:digest(path) for path in paths}
    feedback = list(rows(paths[0]))
    latest = json.loads(paths[1].read_text(encoding='utf-8'))
    require(len(feedback) == len(source), '压缩反馈未覆盖全部源帧')
    if 'compression_result' in remote:
        require(remote['compression_result'] == latest, '压缩末态与会话报告不匹配')
    # Early recordings predate native COMMIT identity fields. Preserve their
    # usability, but bind the files and explicitly decline compression proof.
    identity_fields = {'jpeg_sha256','frame_bytes','completed_s','preprocess_mode'}
    if 'rate_controller_version' not in latest and all(not identity_fields.intersection(row) for row in feedback):
        return dict(strategy=latest.get('compression'), target_average_mbps=None,
                    actual_quality_counts=None, runs=[], exact_cbr_verified=False,
                    source_identity_verified=False,
                    scope='历史压缩日志缺少逐帧JPEG身份和时戳；已绑定原文件，但未验证压缩质量、码率反馈或模式归属'), bindings
    previous_mode = None
    for row, frame in zip(feedback, source):
        ident = frame['frame_id']
        require(type(row.get('index')) is int and row['index'] == ident and
                row.get('jpeg_sha256') == frame['jpeg_sha256'] and
                type(row.get('frame_bytes')) is int and row['frame_bytes'] == frame['bytes'],
                '压缩反馈与源JPEG身份或字节数不匹配')
        stamp = row.get('completed_s')
        require(type(stamp) in (int, float) and math.isfinite(stamp) and
                abs(stamp-times[ident]) < .000002, '压缩反馈源时戳不匹配')
        quality, mode = row.get('actual_quality'), row.get('preprocess_mode')
        require(type(quality) is int and 1 <= quality <= 75 and
                type(mode) is int and mode in range(4), '压缩反馈质量或模式无效')
        require(modes is None or modes[ident] == mode, '压缩反馈与预处理源帧模式不匹配')
        changed = previous_mode is not None and mode != previous_mode
        require(row.get('mode_changed') is changed, '压缩反馈模式切换标记错误')
        previous_mode = mode
    require(latest.get('completed_frames') == len(source) and
            latest.get('frame_id') == source[-1]['frame_id'] and
            latest.get('actual_quality') == feedback[-1]['actual_quality'] and
            latest.get('preprocess_mode') == previous_mode, '压缩末态与逐帧记录不匹配')
    kind = latest.get('compression')
    require(kind in ('quality', 'target'), '压缩策略无效')
    for key in ('compression', 'jpeg_quality', 'target_mbps'):
        require(key not in remote or remote[key] == latest.get(key), '压缩配置与会话报告不匹配')
    if kind == 'quality':
        require(all(row['actual_quality'] == latest.get('jpeg_quality') for row in feedback),
                '固定质量会话出现不同实际质量')
    target = latest.get('target_mbps') if kind == 'target' else None
    require(target is None or (type(target) in (int,float) and math.isfinite(target) and target > 0),
            '目标平均码率无效')
    # Divide consecutive runs only: switching back to a mode must not add the
    # intervening mode's time to its denominator. First frame of each run is
    # excluded from interval bytes, matching the whole-session convention.
    runs = []
    for row in feedback:
        if not runs or runs[-1]['mode'] != row['preprocess_mode']:
            runs.append(dict(mode=row['preprocess_mode'], first_frame=row['index'],
                             last_frame=row['index'], frames=0, jpeg_bytes=0,
                             interval_bytes=0, qualities=Counter()))
        run = runs[-1]
        if run['frames']:
            run['interval_bytes'] += row['frame_bytes']
        run['frames'] += 1
        run['last_frame'] = row['index']
        run['jpeg_bytes'] += row['frame_bytes']
        run['qualities'][row['actual_quality']] += 1
    for run in runs:
        duration = times[run['last_frame']]-times[run['first_frame']]
        run['duration_s'] = duration
        run['source_fps'] = (run['frames']-1)/duration if duration else None
        run['interval_jpeg_mbps'] = run['interval_bytes']*8/duration/1e6 if duration else None
        run['qualities'] = dict(run['qualities'])
        run['target_relative_error_percent'] = (
            (run['interval_jpeg_mbps']/target-1)*100 if target and duration else None)
    span = times[source[-1]['frame_id']]-times[source[0]['frame_id']]
    measured = sum(frame['bytes'] for frame in source[1:])*8/span/1e6
    return dict(strategy=kind, target_average_mbps=target, interval_jpeg_mbps=measured,
                target_relative_error_percent=(measured/target-1)*100 if target else None,
                actual_quality_counts=dict(Counter(row['actual_quality'] for row in feedback)),
                runs=runs, exact_cbr_verified=False, source_identity_verified=True,
                scope='逐帧压缩元数据与源JPEG哈希、长度、时戳和模式核对；录像JPEG另行核验；本汇总不重新解析DQT，不评画质或准确率；包含启动和切换瞬态，平均码率不证明严格CBR'), bindings
