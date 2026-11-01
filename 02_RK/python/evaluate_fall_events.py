import argparse
import hashlib
import json
import math
from pathlib import Path

from evaluate_pose_sequences import evaluate


def require(condition, message):
    if not condition:
        raise ValueError(message)


def finite_number(value):
    return type(value) in (int, float) and math.isfinite(value)


def score_events(alarms, windows, duration_s):
    require(finite_number(duration_s) and duration_s > 0, 'invalid duration')
    require(all(finite_number(alarm) and 0 <= alarm <= duration_s for alarm in alarms),
            'invalid alarm time')
    previous_end = -1
    for window in windows:
        onset, deadline = window['onset_s'], window['deadline_s']
        require(finite_number(onset) and finite_number(deadline) and
                0 <= onset <= deadline <= duration_s and onset > previous_end,
                'invalid or overlapping annotation windows')
        previous_end = deadline
    matches = []
    unmatched = set(range(len(windows)))
    false_positives = []
    for alarm in sorted(alarms):
        match = next((index for index in sorted(unmatched)
                      if windows[index]['onset_s'] <= alarm <= windows[index]['deadline_s']), None)
        if match is None:
            false_positives.append(alarm)
        else:
            unmatched.remove(match)
            matches.append(dict(event_index=match, alarm_s=alarm,
                                delay_s=alarm - windows[match]['onset_s']))
    true_positive = len(matches)
    return dict(tp=true_positive, fp=len(false_positives), fn=len(unmatched),
                precision=true_positive / len(alarms) if alarms else None,
                recall=true_positive / len(windows) if windows else None,
                f1=2 * true_positive / (len(alarms) + len(windows))
                if alarms or windows else None,
                false_alarms_per_hour=len(false_positives) * 3600 / duration_s,
                matches=matches, unmatched_events=sorted(unmatched),
                false_positive_alarm_s=false_positives)


def evaluate_manifest(manifest, video_dir):
    require(manifest.get('schema_version') == 1 and manifest.get('sequences'),
            'invalid annotation manifest')
    require(manifest.get('split') in ('development', 'held_out'), 'explicit dataset split required')
    results = []
    seen = set()
    for annotation in manifest['sequences']:
        require(annotation.get('reviewed') is True and
                isinstance(annotation.get('reviewer'), str) and annotation['reviewer'].strip(),
                'reviewed human annotations required; predictions are not ground truth')
        require(annotation.get('label_origin') == 'manual_video_review',
                'labels must come from video review, not model events')
        require(isinstance(annotation.get('events'), list), 'explicit event list required')
        source = Path(annotation['source'])
        require(source.resolve() not in seen, 'duplicate source')
        seen.add(source.resolve())
        require(hashlib.sha256(source.read_bytes()).hexdigest() == annotation['source_sha256'],
                'pose source hash mismatch')
        sequence = evaluate(source, video_dir)
        require(sequence['video_sha256'] == annotation['video_sha256'], 'video hash mismatch')
        alarms = [row['time_s'] for row in sequence['replay_events']
                  if row['event'] == 'SUSPECTED_FALL']
        metrics = score_events(alarms, annotation['events'], sequence['duration_s'])
        results.append(dict(**sequence, metrics=metrics))
    totals = {name: sum(result['metrics'][name] for result in results) for name in ('tp', 'fp', 'fn')}
    duration = sum(result['duration_s'] for result in results)
    true_positive, false_positive, false_negative = (totals[name] for name in ('tp', 'fp', 'fn'))
    return dict(scope='Recorded RKNN keypoint replay; not live FPGA, pose mAP or medical validation',
                split=manifest['split'], independent_test_verified=False,
                state_machine_sha256=hashlib.sha256(Path(__file__).with_name('pose_fall.py').read_bytes()).hexdigest(),
                metrics=dict(**totals,
                             precision=true_positive / (true_positive + false_positive)
                             if true_positive + false_positive else None,
                             recall=true_positive / (true_positive + false_negative)
                             if true_positive + false_negative else None,
                             f1=2 * true_positive / (2 * true_positive + false_positive + false_negative)
                             if 2 * true_positive + false_positive + false_negative else None,
                             false_alarms_per_hour=false_positive * 3600 / duration),
                sequences=results)


def main():
    parser = argparse.ArgumentParser(description='Score manually labeled events against recorded NPU poses')
    parser.add_argument('--annotations', type=Path, required=True)
    parser.add_argument('--video-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads(args.annotations.read_text(encoding='utf-8'))
    report = evaluate_manifest(manifest, args.video_dir)
    report['annotation_sha256'] = hashlib.sha256(args.annotations.read_bytes()).hexdigest()
    with args.output.open('x', encoding='utf-8') as output:
        output.write(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + '\n')
    print(json.dumps(report['metrics']))


if __name__ == '__main__':
    main()
