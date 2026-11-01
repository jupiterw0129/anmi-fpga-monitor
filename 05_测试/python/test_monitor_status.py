"""Isolated monitor presentation and cloud ACK checks; no board or cloud traffic."""
import os
os.environ['QT_QPA_PLATFORM']='offscreen'
import copy,json,tempfile,threading,time,unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
import qt_desktop as q
from monitor_status import observation,incident
from cloud1694 import CloudBridge,packet_for_pose
APP=q.W.QApplication.instance() or q.W.QApplication([])
q.configure_app(APP)


class IdleThread:
    def __init__(self,*args,**kwargs):pass
    def start(self):pass
    def is_alive(self):return False


class MonitorChecks(unittest.TestCase):
    def test_observation_safety(self):
        for state in ('NO_PERSON','WAIT_BASELINE','CANDIDATE','SUSPECTED_FALL','RECOVERING','UNCERTAIN','AMBIGUOUS','POSTURE_CHANGED','UNKNOWN'):
            value=observation('RUNNING',dict(fall_state={'state':state}),True)
            self.assertNotEqual(value[2],'normal',state)
            self.assertNotIn(state,value[0])
        self.assertEqual(observation('RUNNING',{'fall_state':{'state':'UPRIGHT'}},False)[2],'warning')
        self.assertEqual(observation('DONE',None,False)[0],'监护已结束')
        self.assertEqual(observation('RUNNING',{},True,True)[0],'录像回放')
        low={'people':[{}],'fall_state':{'state':'NO_PERSON','reason':'person_count_or_confidence'}}
        self.assertIn('置信度',observation('RUNNING',low,True)[0])

    def test_incident_is_separate_and_latched(self):
        alarm=dict(id=7,status='ACTIVE',opened_session='s',manual_required=1)
        self.assertEqual(incident(alarm,False,'s')[2],'danger')
        self.assertTrue(incident(alarm,True,'s')[3])
        acknowledged=dict(alarm,status='ACKNOWLEDGED')
        title,_,_,ack,resolve=incident(acknowledged,True,'s')
        self.assertIn('待处理',title);self.assertFalse(ack);self.assertTrue(resolve)
        self.assertNotIn('无待处理',incident(None,False,'s')[0])

    def test_window_states_and_layout(self):
        app=APP
        original=copy.deepcopy(q.b.STATE)
        output=q.b.ROOT.parent/'artifacts/monitor_ui_20261031';output.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='monitor_ui_') as directory:
            with patch.object(q.b,'DATA',Path(directory)),patch.object(q.b.threading,'Thread',IdleThread),patch.object(q.Window,'check',lambda self:None):
                q.b.STATE.clear();q.b.STATE.update(copy.deepcopy(original));q.b.THREAD=None
                w=q.Window();w.timer.stop();w.show();app.processEvents()
                self.assertTrue(w.menuBar().isHidden())
                w.video.image=q.G.QImage(1920,1080,q.G.QImage.Format_RGB32);w.video.image.fill(q.G.QColor('#10151d'))
                painter=q.G.QPainter(w.video.image);painter.setPen(q.G.QColor('#aab6c7'));painter.setFont(q.G.QFont('Microsoft YaHei',30));painter.drawText(w.video.image.rect(),q.C.Qt.AlignCenter,'界面验证画面（非实机检测）');painter.end()
                session='field_20261031_120000_000001'
                def update(state='UPRIGHT',alarm=None,stale=False,phase='RUNNING'):
                    now=time.monotonic_ns();received=now-(3_000_000_000 if stale else 0)
                    pose=dict(frame_id=120,finished_ns=received,people=[{'confidence':.9,'keypoints_xyc':[]}],npu_ms=50,fall_state={'state':state})
                    with q.b.LOCK:
                        q.b.STATE.clear();q.b.STATE.update(copy.deepcopy(original))
                        q.b.STATE.update(phase=phase,session=session,latest_frame=120,elapsed_s=2,recorded_frames=120,
                                        telemetry=dict(pc_received_ns=received,board_monotonic_ns=received,pose=pose,alarm=alarm,source_fps=60,pose_fps=16))
                    w.tick();app.processEvents()
                layouts=[]
                active=dict(id=7,status='ACTIVE',opened_session=session,manual_required=1)
                for width,height in [(1000,700),(1240,820),(1600,900)]:
                    w.resize(width,height);update('SUSPECTED_FALL',active)
                    self.assertEqual((w.width(),w.height()),(width,height))
                    # Primary incident controls remain reachable at the top of the scroll area.
                    for control in (w.scene,w.alarm_text,w.ack,w.resolve,w.start_btn,w.stop_btn):
                        bounds=q.C.QRect(control.mapTo(w,q.C.QPoint()),control.size())
                        self.assertTrue(w.rect().contains(bounds),(width,height,control.text()))
                    self.assertGreaterEqual(w.alarm_text.height(),w.alarm_text.fontMetrics().height())
                    w.grab().save(str(output/f'alert_{width}.png'));layouts.append([width,height])
                w.resize(1240,820)
                for state in ('NO_PERSON','WAIT_BASELINE','UPRIGHT','CANDIDATE','RECOVERING','UNCERTAIN','AMBIGUOUS'):
                    update(state);w.grab().save(str(output/f'{state.lower()}.png'))
                update('UPRIGHT',active)
                self.assertEqual(w.scene.text(),'正常直立');self.assertIn('待确认',w.alarm_text.text())
                self.assertEqual(w.state_badge.property('tone'),'danger')
                update('UPRIGHT',dict(active,status='ACKNOWLEDGED'))
                self.assertFalse(w.ack.isEnabled());self.assertTrue(w.resolve.isEnabled())
                w.grab().save(str(output/'acknowledged.png'))
                update('UPRIGHT',active,stale=True)
                self.assertEqual(w.scene.text(),'检测更新延迟');self.assertIn('未关闭',w.alarm_detail.text())
                w.grab().save(str(output/'stale.png'))
                with q.b.LOCK:q.b.STATE['telemetry']={'pc_received_ns':time.monotonic_ns(),'telemetry_error':'isolated read failure'}
                w.tick();self.assertIn('待确认',w.alarm_text.text());self.assertIn('未关闭',w.alarm_detail.text())
                update('UPRIGHT',active)
                # Operator action captures the current incident and updates the visible active record.
                def work(fn,done=None):
                    value=fn()
                    if done:done(value)
                with patch.object(q.W.QInputDialog,'getText',return_value=('测试人员，现场已核查',True)),patch.object(q.b,'action',return_value={'active':None}) as action,patch.object(w,'work',side_effect=work):
                    w.alarm('resolve');action.assert_called_once_with(session,'resolve',7,'测试人员，现场已核查')
                self.assertIsNone(q.b.STATE['telemetry']['alarm'])
                update('UPRIGHT',active);w.replay=SimpleNamespace(release=lambda:None)
                w.replay_path=Path(directory)/session/'clip.mkv';w.replay_frame=1;w.replay_fps=60;w.replay_start=time.monotonic();w.replay_paused=True
                w.tick();app.processEvents()
                self.assertEqual(w.scene.text(),'录像回放');self.assertIn('实时',w.state_badge.text())
                self.assertFalse(w.ack.isEnabled());self.assertFalse(w.resolve.isEnabled())
                w.grab().save(str(output/'replay_alarm.png'))
                with patch.object(q.b,'action') as action:w.alarm('resolve');action.assert_not_called()
                w.replay=None
                w.tabs.setCurrentWidget(w.cloud_page)
                for state in ('waiting','retrying','synced'):
                    w.cloud_bridge=SimpleNamespace(connection_status=lambda state=state:dict(state=state,last_ack_ns=time.monotonic_ns(),device_id=903,forward_alarms=False,accepted_packets=12))
                    w.refresh_cloud();app.processEvents();w.grab().save(str(output/f'cloud_{state}.png'))
                self.assertEqual(w.cloud_status.text(),'已同步')
                self.assertIn('已接收 12 条',w.cloud_detail.text())
                self.assertFalse(w.cloud_alarms.isChecked())
                for width,height in [(1000,700),(1240,820),(1600,900)]:
                    w.resize(width,height);app.processEvents()
                    controls=[w.cloud_status,w.cloud_detail,w.cloud_start_btn,w.cloud_stop_btn,w.cloud_alarms]
                    bounds=[q.C.QRect(c.mapTo(w.cloud_page,q.C.QPoint()),c.size()) for c in controls]
                    for r in bounds:self.assertTrue(w.cloud_page.rect().contains(r))
                    for i,r in enumerate(bounds):
                        for other in bounds[i+1:]:self.assertFalse(r.intersects(other))
                    w.grab().save(str(output/f'cloud_compact_{width}.png'))
                w.cloud_bridge=None;w.refresh_cloud();self.assertEqual(w.cloud_badge.text(),'云端：未连接')
                w.close();app.processEvents()
                (output/'layouts.json').write_text(json.dumps(layouts),encoding='utf-8')

    def test_cloud_requires_positive_ack(self):
        with tempfile.TemporaryDirectory(prefix='monitor_cloud_') as directory:
            root=Path(directory);(root/'token').write_text('isolated-test-token',encoding='utf-8')
            config=dict(server_url='http://127.0.0.1',device_id=903,device_token_file='token',protocol_root='D:/Desktop/skeleton-monitor',forward_alarms=False)
            (root/'config.json').write_text(json.dumps(config),encoding='utf-8')
            backend=SimpleNamespace(DATA=root,log=lambda message:None)
            (root/'field_test').mkdir()
            for accepted in (True,False):
                bridge=CloudBridge(root/'config.json',backend)
                bridge.snapshot=lambda:('field_test',dict(frame_id=1,fall_state={'state':'NO_PERSON'},people=[]),None)
                def recv(timeout):
                    if not accepted:bridge.end.set()
                    return json.dumps({'accepted':accepted})
                connection=SimpleNamespace(send=lambda data:None,recv=recv,close=lambda:None)
                with patch('websockets.sync.client.connect',return_value=connection):
                    worker=threading.Thread(target=bridge.run);worker.start()
                    deadline=time.monotonic()+2
                    while time.monotonic()<deadline and worker.is_alive():
                        if bridge.connection_status()['accepted_packets']:break
                        time.sleep(.01)
                    status=bridge.connection_status();bridge.stop();worker.join(timeout=2)
                self.assertFalse(worker.is_alive())
                self.assertEqual(status['accepted_packets'],1 if accepted else 0)
                if accepted:self.assertEqual(status['state'],'synced')
                else:self.assertIsNone(status['last_ack_ns'])

    def test_cloud_protocol_and_alarm_opt_in(self):
        import sys
        sys.path.insert(0,'D:/Desktop/skeleton-monitor')
        try:import skeleton_monitor.protocol as protocol
        finally:sys.path.remove('D:/Desktop/skeleton-monitor')
        pose=dict(fall_state={'state':'UPRIGHT'},people=[dict(confidence=.9,
            keypoints_xyc=[[960,540,.8] for _ in range(17)])])
        alarm=dict(status='ACTIVE',id=1)
        packet=packet_for_pose(pose,903,5,123456,protocol,False,alarm)
        decoded=protocol.decode_packet(protocol.encode_packet(packet))
        self.assertFalse(decoded.alarm);self.assertEqual(len(decoded.keypoints),17)
        self.assertAlmostEqual(decoded.keypoints[0].x_norm,.5,places=3)
        self.assertAlmostEqual(decoded.keypoints[0].y_norm,.5,places=3)
        enabled=packet_for_pose(pose,903,6,123457,protocol,True,alarm)
        self.assertTrue(enabled.alarm)
        self.assertEqual(enabled.state,protocol.PacketState.CONFIRMED)
        self.assertFalse(packet_for_pose(pose,903,7,123458,protocol,True,dict(status='CLOSED')).alarm)

    def test_cloud_alarm_switch_requires_operator_confirmation(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(q.b,'DATA',Path(directory)),patch.object(q.b.threading,'Thread',IdleThread),patch.object(q.Window,'check',lambda self:None):
                window=q.Window();window.timer.stop()
                updates=[]
                window.cloud_bridge=SimpleNamespace(set_alarm_forwarding=updates.append,stop=lambda:None)
                with patch.object(q.W.QMessageBox,'question',return_value=q.W.QMessageBox.No):
                    window.cloud_alarms.setChecked(True)
                self.assertFalse(window.cloud_alarms.isChecked());self.assertEqual(updates,[])
                with patch.object(q.W.QMessageBox,'question',return_value=q.W.QMessageBox.Yes):
                    window.cloud_alarms.setChecked(True)
                self.assertEqual(updates,[True])
                window.cloud_alarms.setChecked(False);self.assertEqual(updates,[True,False])
                window.close();APP.processEvents()

    def test_binding_dialog_never_displays_stale_code(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(q.b,'DATA',Path(directory)),patch.object(q.b.threading,'Thread',IdleThread),patch.object(q.Window,'check',lambda self:None):
                window=q.Window();window.timer.stop()
                def work(fn,done=None):
                    value=fn()
                    if done:done(value)
                output=q.b.ROOT.parent/'artifacts/cloud_ux_20261031'
                for bound in (True,False):
                    value=dict(device_id=903,server_url='https://fallmonitor.cn',bound=bound,bind_code=None if bound else 'TEST-ONLY')
                    def close_dialog():
                        dialog=APP.activeModalWidget()
                        self.assertIsNotNone(dialog)
                        edits=dialog.findChildren(q.W.QLineEdit)
                        self.assertEqual(edits[-1].text(),'' if bound else 'TEST-ONLY')
                        self.assertEqual([b for b in dialog.findChildren(q.W.QPushButton) if b.text()=='重新生成绑定码'][0].isEnabled(),not bound)
                        dialog.grab().save(str(output/('binding_bound.png' if bound else 'binding_test_only.png')))
                        dialog.accept()
                    with patch('cloud_binding.binding_status',return_value=value),patch.object(window,'work',side_effect=work):
                        q.C.QTimer.singleShot(60,close_dialog);window.cloud_pairing()
                window.close();APP.processEvents()


if __name__=='__main__':unittest.main()
