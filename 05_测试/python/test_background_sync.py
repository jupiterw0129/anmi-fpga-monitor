import base64
from copy import deepcopy
import hashlib
import io
import json
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from background_sync import BackgroundSync, validate
from board_cloud_proxy import BoardCloudBridge

JPEG = bytes.fromhex('ffd8ffc0000b08021c03c001011100ffd9')


def bundle(version=1):
    return dict(background=dict(device_id=903, background_version=version, width=960, height=540,
        rotation_deg=0, mirrored=False, crop=dict(x=0,y=0,width=1,height=1),
        coordinate_transform_version='camera-frame-v1', sha256=hashlib.sha256(JPEG).hexdigest(),
        captured_at_ms=1,content_type='image/jpeg',size_bytes=len(JPEG)),content_base64=base64.b64encode(JPEG).decode())


class BackgroundSyncTests(unittest.TestCase):
    def test_ui_starts_with_refresh_and_photo_keeps_confirmation_base_version(self):
        import os
        os.environ['QT_QPA_PLATFORM']='offscreen'
        import qt_desktop as q
        from PIL import Image
        from test_monitor_status import IdleThread
        from unittest.mock import Mock
        app=q.W.QApplication.instance() or q.W.QApplication([])
        state=deepcopy(q.b.STATE);approved=getattr(q.b,'APPROVED_BACKGROUND',None)
        order=[]
        bridge=SimpleNamespace(background_version=3,
            refresh_background=lambda **kw:order.append(('refresh',kw)),approve_background=Mock())
        with tempfile.TemporaryDirectory() as folder,patch.object(q.b,'DATA',Path(folder)):
            with patch.object(q.b.threading,'Thread',IdleThread),patch.object(q.Window,'check',lambda _:None):
                window=q.Window();window.timer.stop()
            window.cloud_bridge=bridge
            window.work=lambda fn,done=None:fn()
            with patch.object(q.b,'start',side_effect=lambda value:order.append(('start',value))):window.start()
            self.assertEqual(order[0],('refresh',dict(force=True)))
            self.assertEqual(order[1][0],'start');self.assertFalse(window.starting)
            encoded=io.BytesIO();Image.new('RGB',(960,540),'gray').save(encoded,'JPEG');data=encoded.getvalue()
            q.b.STATE.update(phase='RUNNING',purpose='test',preview_updated_pc_ns=__import__('time').monotonic_ns())
            with patch.object(q.b,'PREVIEW',data),patch.object(q.b,'PREVIEW_ID',7):
                def confirm(*_):
                    bridge.background_version=4  # APP changed while PC dialog was open.
                    return q.W.QMessageBox.Yes
                with patch.object(q.W.QMessageBox,'question',side_effect=confirm):window.capture_background()
            bridge.approve_background.assert_called_once_with(data,expected_version=3)
            self.assertTrue(window.video.background.isNull())  # No unconfirmed local replacement.
            window.cloud_bridge=None;q.b.STATE.clear();q.b.STATE.update(state)
            with q.b.LOCK:q.b.APPROVED_BACKGROUND=approved
            window.close();app.processEvents()

    def test_validator_rejects_wrong_device_geometry_hash_and_transform(self):
        self.assertEqual(validate(bundle(),903),JPEG)
        for field,value in [('device_id',902),('width',1920),('sha256','bad'),('rotation_deg',180),
                            ('mirrored',True),('size_bytes',2),('background_version',0)]:
            bad=bundle();bad['background'][field]=value
            with self.assertRaises(ValueError):validate(bad,903)
        bad=bundle();bad['content_base64']='invalid@'
        with self.assertRaises(ValueError):validate(bad,903)

    def test_cache_survives_failure_corruption_and_version_rollback(self):
        # Native fcntl is exercised on RK; this shim permits Windows regression.
        shim=SimpleNamespace(LOCK_EX=1,flock=lambda *_:None)
        with tempfile.TemporaryDirectory() as directory,patch.dict(sys.modules,{'fcntl':shim}):
            home=Path(directory);(home/'token').write_text('test-only')
            (home/'config.json').write_text(json.dumps(dict(device_id=903,device_token_file='token',server_url='https://example.invalid')))
            sync=BackgroundSync(home)
            with patch.object(sync,'request',return_value=bundle()):
                self.assertEqual(sync.exchange()['background']['background_version'],1)
            before=(home/'confirmed_background.json').read_bytes()
            corrupt=bundle(2);corrupt['content_base64']='broken'
            for response in (corrupt,bundle(0)):
                with patch.object(sync,'request',return_value=response):
                    self.assertIsNotNone(sync.exchange()['sync_error'])
                self.assertEqual((home/'confirmed_background.json').read_bytes(),before)
            with patch.object(sync,'request',side_effect=TimeoutError):
                result=sync.exchange(data=JPEG,expected_version=1)
                self.assertFalse(result['committed']);self.assertIsNotNone(result['sync_error'])
            self.assertEqual((home/'confirmed_background.json').read_bytes(),before)
            response=bundle();response['content_base64']=None
            with patch.object(sync,'request',return_value=response):
                self.assertIsNone(sync.exchange(known_version=1)['content_base64'])

    def test_pc_rejects_unknown_version_and_only_applies_verified_content(self):
        with tempfile.TemporaryDirectory() as directory:
            config=Path(directory)/'config.json';config.write_text('{"device_id":903}')
            backend=SimpleNamespace(ssh_json=lambda *args,**kw:dict(bundle(),sync_error=None),log=lambda *_:None)
            bridge=BoardCloudBridge(config,backend)
            with self.assertRaises(ValueError):bridge.approve_background(JPEG)
            bridge.refresh_background()
            self.assertEqual(bridge.background_version,1)
            self.assertEqual(bridge.take_background_update()[1],JPEG)
            bridge.approve_background(None)
            self.assertFalse(bridge.pending_background)
            bridge.approve_background(JPEG,expected_version=1)
            with self.assertRaises(ValueError):bridge.approve_background(JPEG,expected_version=1)
            bridge.pending_background=False
            bad=bundle(2);bad['background']['sha256']='bad'
            backend.ssh_json=lambda *args,**kw:bad
            with self.assertRaises(ValueError):bridge.refresh_background()
            self.assertEqual(bridge.background_version,1)
            self.assertIsNone(bridge.take_background_update())


if __name__=='__main__':unittest.main()
