import sys
sys.path.insert(0,'/userdata/native_required1138_20261028')
from long_journal1295 import RowJournal,journal_json
from session_config1301 import runtime_seconds
import sys
sys.path.insert(0,'/userdata/live_display1009_20261027')
"""Bounded real JPGS755 -> MPP -> HDMI; preserve source IDs at sink submission."""
from pathlib import Path
import argparse, hashlib, json, mmap, os, signal, subprocess, time, faulthandler
import gi
gi.require_version('Gst', '1.0')
from gi.repository import Gst
from fifo_sampler1326 import FifoSampler
Gst.init(None)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--shared', required=True)
    ap.add_argument('--frame-fifo',required=True)
    ap.add_argument('--generation', type=int, required=True)
    ap.add_argument('--output', required=True)
    ap.add_argument('--max-seconds',type=runtime_seconds,required=True)
    a = ap.parse_args()
    out = Path(a.output)
    out.mkdir()
    os.environ.update(DISPLAY=':0', XAUTHORITY='/var/run/lightdm/root/:0')
    def run(args):
        return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT, timeout=15)
    def current():
        return run(['xrandr', '--current'])
    before = current()
    assert 'HDMI-1 connected 1280x720+0+0' in before
    assert 'DSI-1 connected 800x1280+1024+0' in before
    drm = run(['modetest', '-M', 'rockchip', '-p'])
    plane = drm[drm.index('\n108\t'):drm.index('\n132\t', drm.index('\n108\t'))]
    assert plane.splitlines()[1].startswith('108\t0\t0\t'), 'HDMI overlay already occupied'
    assert '\t\tvalue: 0' in plane[plane.index('COLOR_RANGE:'):].split('rotation:')[0]
    (out/'xrandr_before.txt').write_text(before)
    (out/'drm_before.txt').write_text(drm)
    report = dict(state='FAILED', submitted=[], sink_buffers=[], physical_scanout_verified=False,
                  scope='Real live camera JPEGs. Sink submission and rendered counters are software evidence, not optical measurement.')
    report['submitted']=RowJournal(out/'submitted.jsonl')
    report['sink_buffers']=RowJournal(out/'sink_buffers.jsonl')
    pipe = sampler = mm = None
    fd = None
    switched = False
    def interrupted(signum, frame):
        raise SystemExit('signal ' + str(signum))
    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, interrupted)
    try:
        run(['xrandr','--output','HDMI-1','--mode','1920x1080','--rate','60','--pos','0x0',
             '--output','DSI-1','--pos','1920x0'])
        switched = True
        during = current()
        assert 'HDMI-1 connected 1920x1080+0+0' in during and '1920x1080     60.00*' in during
        (out/'xrandr_during.txt').write_text(during)
        fd = os.open(a.shared, os.O_RDONLY | os.O_NOFOLLOW)
        assert os.fstat(fd).st_size == 4*(1920*1080*6+65536+64)
        mm = mmap.mmap(fd, 0, access=mmap.ACCESS_READ)
        sampler = FifoSampler(a.frame_fifo,a.generation)
        description = ('appsrc name=source block=true max-bytes=4194304 format=time is-live=true '
            'caps="image/jpeg,width=1920,height=1080,framerate=60/1" ! jpegparse ! '
            'mppjpegdec ignore-error=false max-errors=0 rotation=180 ! '
            'capssetter caps="video/x-raw,colorimetry=(string)1:4:0:0" ! '
            'kmssink driver-name=rockchip connector-id=188 plane-id=108 force-modesetting=false '
            'restore-crtc=true skip-vsync=true plane-properties="s,COLOR_RANGE=(uint)1,COLOR_ENCODING=(uint)0" '
            'name=output sync=true qos=false max-lateness=-1')
        report['pipeline'] = description
        pipe = Gst.parse_launch(description)
        source = pipe.get_by_name('source')
        sink = pipe.get_by_name('output')
        def observed(pad, info):
            buffer = info.get_buffer()
            report['sink_buffers'].append(dict(pts_ns=int(buffer.pts), host_ns=time.monotonic_ns()))
            if 'decoded_caps' not in report:
                report['decoded_caps'] = pad.get_current_caps().to_string()
            return Gst.PadProbeReturn.OK
        sink.get_static_pad('sink').add_probe(Gst.PadProbeType.BUFFER, observed)
        assert pipe.set_state(Gst.State.PLAYING) != Gst.StateChangeReturn.FAILURE
        sampler.start()
        (out/'ready.tmp').open('x').write(json.dumps(dict(generation=a.generation)))
        os.replace(out/'ready.tmp',out/'ready.json')
        first = offset = None
        report['push_stalls']=RowJournal(out/'push_stalls.jsonl')
        deadline = time.monotonic()+a.max_seconds
        while True:
            stopping = (out/'stop').exists()
            # Continue to clean FIFO EOF before ending the HDMI stream.
            frames = sampler.take()
            for frame, completed_ns, data in frames:
                if first is None:
                    first = completed_ns
                    clock = pipe.get_clock()
                    assert clock is not None
                    offset = clock.get_time()-pipe.get_base_time()+50_000_000
                pts = completed_ns-first+offset
                buffer = Gst.Buffer.new_allocate(None, len(data), None)
                buffer.fill(0, data)
                buffer.pts = pts
                buffer.dts = pts
                buffer.duration = Gst.SECOND//60
                push_started=time.monotonic_ns()
                faulthandler.dump_traceback_later(1,repeat=True)
                try:assert source.emit('push-buffer', buffer) == Gst.FlowReturn.OK
                finally:faulthandler.cancel_dump_traceback_later()
                elapsed=time.monotonic_ns()-push_started
                if elapsed>20000000:report['push_stalls'].append(dict(frame_id=frame,elapsed_ns=elapsed))
                report['submitted'].append(dict(frame_id=frame, completed_ns=completed_ns, pts_ns=pts,
                    jpeg_sha256=hashlib.sha256(data).hexdigest()))
            msg = pipe.get_bus().pop_filtered(Gst.MessageType.ERROR)
            if msg:
                raise RuntimeError(str(msg.parse_error()))
            if stopping and sampler.eof.is_set() and sampler.bytes==0:
                sampler.stop();break
            if time.monotonic()>deadline:
                raise TimeoutError('Bounded HDMI worker exceeded deadline')
            time.sleep(.002)
        assert source.emit('end-of-stream') == Gst.FlowReturn.OK
        msg = pipe.get_bus().timed_pop_filtered(10*Gst.SECOND, Gst.MessageType.EOS|Gst.MessageType.ERROR)
        assert msg is not None, 'HDMI EOS timeout'
        if msg.type == Gst.MessageType.ERROR:
            raise RuntimeError(str(msg.parse_error()))
        stats = sink.get_property('stats')
        report['sink_stats'] = {k:stats.get_value(k) for k in ('rendered','dropped','average-rate')}
        report['sampler'] = sampler.stats
        report['queue_peak_bytes'] = sampler.peak_bytes
        sent, seen = report['submitted'], report['sink_buffers']
        assert len(sent) >= 2 and [r['pts_ns'] for r in sent] == [r['pts_ns'] for r in seen]
        assert len({r['frame_id'] for r in sent}) == len(sent)
        assert not sampler.stats['frame_id_gaps'] and not sampler.stats['queue_overflow_frames']
        assert report['sink_stats']['rendered'] == len(sent) and report['sink_stats']['dropped'] == 0
        report['source_completion_fps'] = (len(sent)-1)*1e9/(sent[-1]['completed_ns']-sent[0]['completed_ns'])
        report['sink_observed_fps'] = (len(seen)-1)*1e9/(seen[-1]['host_ns']-seen[0]['host_ns'])
        report['state'] = 'LIVE1008_REAL_JPEG_MPP_HDMI_RENDERED_PENDING_SOURCE_AUDIT'
        (out/'drm_during.txt').write_text(run(['modetest','-M','rockchip','-c','-p']))
        atomic = Path('/sys/kernel/debug/dri/0/state')
        if atomic.exists():
            (out/'atomic_during.txt').write_text(atomic.read_text())
    except BaseException as error:
        report['error'] = repr(error)
        raise
    finally:
        faulthandler.cancel_dump_traceback_later()
        if sampler:report.update(sampler=sampler.stats,queue_peak_bytes=sampler.peak_bytes,sampler_error=repr(sampler.error),fifo_clean_eof=sampler.eof.is_set())
        if pipe:
            pipe.set_state(Gst.State.NULL)
        if sampler:sampler.close()
        if mm:
            mm.close()
        if fd is not None:
            os.close(fd)
        try:
            if switched:
                run(['xrandr','--output','HDMI-1','--mode','1280x720','--rate','60','--pos','0x0',
                     '--output','DSI-1','--pos','1024x0'])
                run(['modetest','-M','rockchip','-w','108:COLOR_RANGE:0'])
            after = current()
            report['display_restored'] = after == before
            (out/'xrandr_after.txt').write_text(after)
            assert report['display_restored']
        except BaseException as error:
            report.update(restore_error=repr(error), state='FAILED')
        if isinstance(report.get('submitted'),RowJournal) and not report['submitted'].closed:report['submitted'].close()
        if isinstance(report.get('sink_buffers'),RowJournal) and not report['sink_buffers'].closed:report['sink_buffers'].close()
        if isinstance(report.get('push_stalls'),RowJournal) and not report['push_stalls'].closed:report['push_stalls'].close()
        (out/'report.json').open('x').write(json.dumps(report,indent=2,default=journal_json))

if __name__ == '__main__':
    main()
