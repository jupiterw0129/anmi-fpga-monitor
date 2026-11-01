"""Apply a narrowly checked CPU-decode overlap to the frozen pose worker."""


def augment_pose(source):
    changes = [
        ('import cv2,numpy as np\n', 'import cv2,numpy as np\nfrom latest_decode1722 import LatestDecode\n'),
        ('fd=None;mm=None;store=None;scene=None', 'fd=None;mm=None;store=None;scene=None;pipeline=None'),
        ('        last=None;deadline=time.monotonic()+a.max_seconds\n', '''        def latest_source(last):
            frames,busy=snapshot(fd,mm,a.generation,last)
            return frames[-1] if frames else None
        def decode_image(row):
            frame,completed,data=row
            started=time.monotonic_ns()
            image=cv2.imdecode(np.frombuffer(data,dtype=np.uint8),cv2.IMREAD_COLOR)
            assert image is not None and image.shape==(1080,1920,3)
            image=cv2.rotate(image,cv2.ROTATE_180)
            return frame,completed,data,started,image,time.monotonic_ns()
        pipeline=LatestDecode(latest_source,decode_image).start()
        last=None;deadline=time.monotonic()+a.max_seconds
'''),
        ('''            frames,busy=snapshot(fd,mm,a.generation,last)
            if frames:
                frame,completed,data=frames[-1]
                started=time.monotonic_ns()
                image=cv2.imdecode(np.frombuffer(data,dtype=np.uint8),cv2.IMREAD_COLOR)
                assert image is not None and image.shape==(1080,1920,3)
                image=cv2.rotate(image,cv2.ROTATE_180)
                people,timing=infer_pose(runtime,image)
''', '''            row=pipeline.take()
            if row is not None:
                frame,completed,data,started,image,decoded_at=row
                assert last is None or frame>last
                inference_started=time.monotonic_ns()
                people,timing=infer_pose(runtime,image)
                timing.update(jpeg_decode_rotate_ms=(decoded_at-started)/1e6,
                              decoded_wait_ms=(inference_started-decoded_at)/1e6)
'''),
        ('    finally:\n        if store:\n', '''    finally:
        decoder_stopped=True
        if pipeline:
            try:report['decode_pipeline']=pipeline.close()
            except BaseException as error:
                decoder_stopped=False
                report.update(state='FAILED',error=repr(error))
        if store:
'''),
        ('        if mm:mm.close()\n        if fd is not None:os.close(fd)\n',
         '        if mm and decoder_stopped:mm.close()\n        if fd is not None and decoder_stopped:os.close(fd)\n'),
        ("        (out/'report.json').open('x').write(json.dumps(report,indent=2,default=journal_json))\n",
         "        (out/'report.json').open('x').write(json.dumps(report,indent=2,default=journal_json))\n        if not decoder_stopped:raise RuntimeError(report['error'])\n"),
    ]
    for old, new in changes:
        if source.count(old) != 1:
            raise ValueError('Pose worker differs from checked source: '+old[:100])
        source = source.replace(old, new)
    compile(source, 'live_pose1723.py', 'exec')
    return source
