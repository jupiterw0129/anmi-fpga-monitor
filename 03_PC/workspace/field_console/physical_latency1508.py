"""Manual same-shot latency measurements using decoded presentation timestamps."""
from pathlib import Path
from fractions import Fraction
from datetime import datetime
import hashlib,json,subprocess,uuid

HIDDEN=dict(creationflags=subprocess.CREATE_NO_WINDOW) if hasattr(subprocess,'CREATE_NO_WINDOW') else {}

def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream,'sha256').hexdigest()

def load_video(path):
    path=Path(path).resolve()
    run=subprocess.run(['ffprobe','-v','error','-select_streams','v:0','-show_streams','-show_frames',
        '-show_entries','stream=index,time_base,width,height:frame=best_effort_timestamp','-of','json',str(path)],
        capture_output=True,text=True,check=True,timeout=300,**HIDDEN)
    raw=json.loads(run.stdout)
    streams=raw.get('streams',[])
    if len(streams)!=1:raise ValueError('需要一个可解码的视频流')
    base=Fraction(streams[0]['time_base'])
    pts=[int(f['best_effort_timestamp']) for f in raw['frames']]
    if len(pts)<3 or base<=0 or any(b<=a for a,b in zip(pts,pts[1:])):
        raise ValueError('视频帧时间戳缺失或不递增，不能测量')
    return dict(path=str(path),sha256=digest(path),bytes=path.stat().st_size,
        time_base=str(base),pts=pts,width=streams[0]['width'],height=streams[0]['height'])

def frame_png(video,index):
    if type(index)!=int or not 0<=index<len(video['pts']):raise ValueError('无效帧号')
    run=subprocess.run(['ffmpeg','-v','error','-nostdin','-i',video['path'],'-map','0:v:0',
        '-vf',f'select=eq(n\\,{index}),scale=1280:720:force_original_aspect_ratio=decrease',
        '-frames:v','1','-fps_mode','passthrough','-f','image2pipe','-c:v','png','pipe:1'],
        capture_output=True,check=True,timeout=120,**HIDDEN)
    if not run.stdout:raise ValueError('未解码出选中帧')
    return run.stdout

def measure(video,source,screen):
    pts=video['pts'];base=Fraction(video['time_base'])
    if not (type(source)==type(screen)==int and 0<source<=screen<len(pts)):
        raise ValueError('须选变化首次出现帧；两点均需有前一帧，且结果不能早于源变化')
    seconds=lambda tick:float(tick*base)
    return dict(source_frame=source,result_frame=screen,source_pts=pts[source],result_pts=pts[screen],
        latency_ms=seconds(pts[screen]-pts[source])*1000,
        sampling_lower_ms=seconds(pts[screen-1]-pts[source])*1000,
        sampling_upper_ms=seconds(pts[screen]-pts[source-1])*1000,
        source_bracket_ms=seconds(pts[source]-pts[source-1])*1000,
        result_bracket_ms=seconds(pts[screen]-pts[screen-1])*1000)

def export(video,pairs,reviewer,kind,setup,confirmed,output):
    if not reviewer.strip() or not setup.strip() or not confirmed or not pairs:
        raise ValueError('请填写复核人、拍摄布置并确认标记，再导出至少一组测量')
    if kind not in ('video_path','recognition'):raise ValueError('未知测量类型')
    if len({(p['source_frame'],p['result_frame']) for p in pairs})!=len(pairs):
        raise ValueError('存在重复测量')
    if digest(video['path'])!=video['sha256']:raise ValueError('原视频已变化，请重新导入')
    rows=[measure(video,p['source_frame'],p['result_frame']) for p in pairs]
    ordered=sorted(p['latency_ms'] for p in rows)
    count=len(rows);middle=count//2
    median=ordered[middle] if count%2 else (ordered[middle-1]+ordered[middle])/2
    report=dict(schema_version=1,state='MANUAL_SAME_SHOT_PTS_MEASUREMENTS',
        created_pc=datetime.now().astimezone().isoformat(),video=video,measurements=rows,
        reviewer=reviewer.strip(),measurement_kind=kind,setup=setup.strip(),manual_same_shot_confirmed=True,
        summary=dict(count=count,median_ms=median,min_ms=ordered[0],max_ms=ordered[-1]),
        timestamp_method='integer best_effort_timestamp * stream time_base; decoded presentation frame index',
        sampling_interval_scope='Changes occurred after the preceding sampled frame and by the selected frame; excludes rolling shutter, exposure and clock calibration uncertainty.',
        optical_60fps_verified=False,contest_threshold_pass=None,physical_accuracy_independently_verified=False,
        implementation_sha256=digest(__file__))
    output=Path(output);output.mkdir(parents=True,exist_ok=True)
    folder=output/('latency_'+datetime.now().strftime('%Y%m%d_%H%M%S')+'_'+uuid.uuid4().hex[:8]);folder.mkdir()
    (folder/'measurements.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    lines=['# 人工拍屏延迟测量','',f'视频：{video["path"]}',f'复核人：{reviewer}',
        f'类型：{"视频通路" if kind=="video_path" else "目标出现到正确识别结果"}',f'布置：{setup}',
        '', '| 源变化帧 | 结果变化帧 | PTS差 ms | 采样区间 ms |','|---:|---:|---:|---:|']
    lines += [f'| {r["source_frame"]} | {r["result_frame"]} | {r["latency_ms"]:.3f} | [{r["sampling_lower_ms"]:.3f}, {r["sampling_upper_ms"]:.3f}] |' for r in rows]
    lines += ['',f'共{count}次，中位{median:.3f}ms。帧号从0开始。',
        '采样区间只描述视频取样带来的不确定性；不含滚动快门、曝光及拍摄时钟误差。未自动判定赛题达标，也不证明光学60fps。']
    (folder/'测量结果.md').write_text('\n'.join(lines),encoding='utf-8')
    return folder,report
