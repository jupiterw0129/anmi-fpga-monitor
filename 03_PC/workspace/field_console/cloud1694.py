"""PC side adapter to the unchanged skeleton-monitor protocol; disabled by default."""
from pathlib import Path
import json
import math
import sys
import threading
import time
from urllib.parse import urlsplit


def packet_for_pose(pose, device_id, sequence, timestamp_ms, protocol, forward_alarms=False, alarm=None):
    state=pose.get('fall_state',{}).get('state','UNCERTAIN')
    states={'UPRIGHT':1,'NORMAL':1,'POSTURE_CHANGED':1,'CANDIDATE':2,
            'FALL_CANDIDATE':2,'SUSPECTED_FALL':2,'RECOVERING':4}
    wire_state=states.get(state,0)
    flags=0 if state in states else 4
    if forward_alarms and alarm and alarm.get('status')!='CLOSED':
        wire_state=3;flags|=1
    people=pose.get('people',[])
    points=()
    if len(people)==1 and people[0].get('confidence',0)>=.5:
        raw=people[0].get('keypoints_xyc',[])
        if len(raw)==17 and all(len(p)==3 and all(math.isfinite(v) for v in p) for p in raw):
            points=tuple(protocol.SemanticKeypoint(max(0,min(1,x/1920)),max(0,min(1,y/1080)),max(0,min(1,c))) for x,y,c in raw)
    if not points:
        flags|=4
        if not flags&1:wire_state=0
    return protocol.SemanticPacket(device_id,sequence,timestamp_ms,wire_state,flags,points)


class CloudBridge:
    def __init__(self, config_path, backend):
        path=Path(config_path).resolve()
        self.config=json.loads(path.read_text(encoding='utf-8-sig'))
        self.backend=backend;self.end=threading.Event();self.connection=None
        self.device_id=self.config['device_id']
        if type(self.device_id) is not int or not 0<self.device_id<=0xffffffff or self.device_id in (901,902):
            raise ValueError('请使用独立的FPGA测试设备号，不能复用901/902')
        url=urlsplit(self.config['server_url'].rstrip('/'))
        if url.scheme not in ('http','https') or not url.hostname or url.username or url.password or url.query or url.fragment or url.path:
            raise ValueError('server_url须为http(s)服务根地址，不含口令、路径或查询参数')
        if url.scheme=='http' and url.hostname not in ('127.0.0.1','localhost','::1'):
            raise ValueError('非本机服务须使用HTTPS')
        self.uri=('wss' if url.scheme=='https' else 'ws')+'://'+url.netloc+'/ws/v1/device-stream'
        token_path=Path(self.config['device_token_file'])
        if not token_path.is_absolute():token_path=path.parent/token_path
        self.token=token_path.read_text(encoding='utf-8-sig').strip()
        if not self.token:raise ValueError('设备令牌文件为空')
        if type(self.config.get('forward_alarms',False)) is not bool:raise ValueError('forward_alarms须为布尔值')
        root=Path(self.config.get('protocol_root','D:/Desktop/skeleton-monitor'))
        if not (root/'skeleton_monitor/protocol/__init__.py').is_file():raise ValueError('云端协议源码路径不存在')
        sys.path.insert(0,str(root))
        try:
            import skeleton_monitor.protocol as protocol
            self.protocol=protocol
        finally:sys.path.remove(str(root))
        self.thread=threading.Thread(target=self.run,daemon=True)
        self.control_thread=threading.Thread(target=self.background_run,daemon=True)
        self.background_session=None
        self._status_lock=threading.Lock()
        self._status=dict(state='waiting',device_id=self.device_id,
                          forward_alarms=self.config.get('forward_alarms',False),
                          accepted_packets=0,last_ack_ns=None,error=None)

    def connection_status(self):
        with self._status_lock:return dict(self._status)

    def set_alarm_forwarding(self, enabled):
        if type(enabled) is not bool:raise ValueError('forward_alarms须为布尔值')
        with self._status_lock:
            self.config['forward_alarms']=enabled
            self._status['forward_alarms']=enabled

    def _set_status(self,**values):
        with self._status_lock:self._status.update(values)

    def start(self):
        self.thread.start()
        self.control_thread.start()

    def stop(self):
        self._set_status(state='stopping')
        self.end.set()
        # The worker owns network I/O; UI never waits on DNS/TLS/close.

    def snapshot(self):
        b=self.backend
        with b.LOCK:
            s=b.STATE
            row=s.get('fast_pose') or {}
            age=time.monotonic_ns()-row.get('pc_received_ns',0)
            if row.get('pose') and row.get('board_monotonic_ns'):
                age+=max(0,row['board_monotonic_ns']-row['pose']['finished_ns'])
            if s.get('phase')!='RUNNING' or s.get('purpose')=='preview' or not 0<=age<2_000_000_000:return None
            alarm=s.get('telemetry',{}).get('alarm')
            return s['session'],row.get('pose'),alarm

    def handle_background(self, command, upload):
        if hasattr(self.backend,'handle_background'):
            return self.backend.handle_background(command,upload)
        action=command.get('action');session=command.get('session_id')
        if not isinstance(session,str) or not session:raise ValueError('missing background session')
        if action=='start':self.background_session=session
        elif action=='stop':
            if session!=self.background_session:raise ValueError('background session mismatch')
            self.background_session=None
        elif action in ('preview','capture'):
            if session!=self.background_session:raise ValueError('background session mismatch')
            with self.backend.LOCK:data=getattr(self.backend,'APPROVED_BACKGROUND',None)
            if not data:raise ValueError('先在PC测试台手动拍摄并确认无人背景')
            # Only the manually approved empty scene can leave the PC.
            upload(session,action,data)
        else:raise ValueError('unsupported background command')

    def background_run(self):
        from websockets.sync.client import connect
        from urllib.request import Request,urlopen
        from urllib.parse import urlencode,quote
        def upload(session,action,data):
            url=self.config['server_url'].rstrip('/')+'/api/v1/devices/'+str(self.device_id)+'/background/calibration/'+quote(session,safe='')+'/frame?'+urlencode({'kind':action})
            request=Request(url,data=data,method='PUT',headers={'Content-Type':'image/jpeg','X-Device-Token':self.token})
            with urlopen(request,timeout=5) as response:
                if response.status!=200:raise ValueError('background upload rejected')
        while not self.end.is_set():
            try:
                with connect(self.uri.replace('/ws/v1/device-stream','/ws/v1/device-control/'+str(self.device_id)),
                             additional_headers={'X-Device-Token':self.token},open_timeout=4,close_timeout=1,max_size=1<<20) as ws:
                    self.background_session=None
                    self.backend.log('APP相机控制已连接' if hasattr(self.backend,'handle_background') else '云端背景控制已连接；仅允许上传手动确认的空场背景')
                    while not self.end.is_set():
                        try:command=json.loads(ws.recv(timeout=.5))
                        except TimeoutError:continue
                        try:
                            self.handle_background(command,upload)
                            ws.send(json.dumps(dict(ok=True,action=command.get('action'))))
                        except Exception as error:
                            self.backend.log('背景请求失败：'+type(error).__name__+': '+str(error)[:200])
                            ws.send(json.dumps(dict(ok=False,error='相机预览暂不可用，请检查摄像头或稍后重试' if hasattr(self.backend,'handle_background') else '请先在PC手动拍摄空场背景并检查会话')))
            except Exception as error:
                self.backend.log('云端背景通道异常：'+type(error).__name__)
                self.end.wait(3)

    def run(self):
        from websockets.sync.client import connect
        b=self.backend;last_key=None;active=None;sequence=0;journal=None
        try:
            while not self.end.wait(.05):
                snap=self.snapshot()
                if not snap:
                    if self.connection:self.connection.close();self.connection=None
                    self._set_status(state='waiting')
                    continue
                name,pose,alarm=snap
                if not pose:continue
                if name!=active:
                    if self.connection:self.connection.close();self.connection=None
                    if journal:journal.close()
                    directory=b.DATA/name/'cloud';directory.mkdir(exist_ok=True)
                    journal=(directory/('relay_'+str(time.time_ns())+'.jsonl')).open('x',encoding='utf-8')
                    active=name;last_key=None;sequence=0
                key=(name,pose['frame_id'])
                if key==last_key:continue
                try:
                    if self.connection is None:
                        self._set_status(state='connecting',error=None)
                        self.connection=connect(self.uri,additional_headers={'X-Device-Token':self.token},open_timeout=4,close_timeout=1,max_size=1<<20)
                        sequence=0
                        b.log('云端已连接 · 设备'+str(self.device_id)+(' · 转发检测告警' if self.config.get('forward_alarms') else ' · 骨架预览，不转发告警'))
                        # Refresh after connection setup; never forward an expired pose.
                        continue
                    packet=packet_for_pose(pose,self.device_id,sequence,time.time_ns()//1_000_000,self.protocol,self.config.get('forward_alarms',False),alarm)
                    self.connection.send(self.protocol.encode_packet(packet))
                    ack=json.loads(self.connection.recv(timeout=3))
                    journal.write(json.dumps(dict(source_frame_id=pose['frame_id'],device_id=self.device_id,sequence=sequence,
                        pc_unix_ms=packet.timestamp_ms,local_state=pose.get('fall_state',{}).get('state'),
                        wire_state=int(packet.state),alarm=packet.alarm,accepted=ack.get('accepted') is True,
                        pc_received_ns=time.monotonic_ns()),ensure_ascii=False)+'\n');journal.flush()
                    if ack.get('accepted') is not True:raise ValueError('server rejected packet')
                    with self._status_lock:
                        self._status.update(state='synced',error=None,last_ack_ns=time.monotonic_ns(),
                                            accepted_packets=self._status['accepted_packets']+1)
                    last_key=key;sequence=(sequence+1)&0xffffffff
                except Exception as error:
                    self._set_status(state='retrying',error=type(error).__name__)
                    journal.write(json.dumps(dict(source_frame_id=pose['frame_id'],accepted=False,error_type=type(error).__name__))+'\n');journal.flush()
                    b.log('云端连接异常：'+type(error).__name__+'；本地采集继续')
                    if self.connection:self.connection.close();self.connection=None
                    self.end.wait(2)
        finally:
            self._set_status(state='stopped')
            if self.connection:self.connection.close();self.connection=None
            if journal:journal.close()
            b.log('云端转发已结束')
