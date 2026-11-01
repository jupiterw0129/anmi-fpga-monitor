"""Qt field console; all FPGA controls use the verified session controller."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent/'vendor'))
from PySide6 import QtCore as C, QtGui as G, QtWidgets as W, QtNetwork as N
import json,os,queue,shutil,threading,time
from datetime import datetime
import server as b
from monitor_status import observation, incident
from posture_hint import PostureHints

MODES=['彩色原图','灰度','高斯滤波','直方图均衡']
DEVICE_NAME='设备 Anmi'
DURATIONS=[('30秒',30),('1分钟',60),('5分钟',300),('10分钟',600),('30分钟',1800),('1小时',3600),('2小时',7200),('手动停止（最长2小时）',0)]
STYLE='''
QMainWindow,QWidget{background:#191d24;color:#e6eaf0;font-family:"Microsoft YaHei";font-size:13px;}
QFrame#Panel{background:#232934;border:1px solid #343c49;border-radius:8px;}
QLabel{background:transparent;border:0;}
QLabel#Muted{color:#aab6c7;} QLabel#Title{font-size:18px;font-weight:600;}
QLabel#Metric{font-family:"Microsoft YaHei";font-size:24px;font-weight:600;color:#edf3ff;}
QLabel#Scene{font-size:19px;font-weight:600;}
QLabel#AlarmTitle{font-size:16px;font-weight:600;}
QLabel[tone="normal"]{color:#8cdbb7;} QLabel[tone="warning"]{color:#ffd58a;} QLabel[tone="danger"]{color:#ffb9bf;}
QLabel#StateBadge{padding:4px 8px;border-radius:4px;background:#303a49;}
QLabel#StateBadge[tone="warning"]{background:#4c3b20;color:#ffe0a8;}
QLabel#StateBadge[tone="danger"]{background:#532c34;color:#ffd4d8;}
QFrame#AlarmPanel{border:1px solid #47546a;border-radius:5px;background:#252c37;}
QFrame#AlarmPanel[tone="danger"]{background:#45272f;border-color:#b86d79;}
QFrame#AlarmPanel[tone="warning"]{background:#40351f;border-color:#a38951;}
QScrollArea{border:0;background:transparent;}
QPushButton{background:#303a49;border:1px solid #47546a;border-radius:5px;padding:7px 13px;min-height:17px;}
QPushButton:hover{background:#3d4d64;border-color:#7199d0;} QPushButton:pressed{background:#243047;}
QPushButton:disabled{color:#687385;background:#272e39;border-color:#353e4b;}
QPushButton#Primary{background:#3478d5;border-color:#4b8de5;} QPushButton#Primary:hover{background:#4388e5;}
QComboBox,QLineEdit{background:#171d27;border:1px solid #44516a;border-radius:5px;padding:6px 10px;min-height:18px;}
QComboBox{padding-right:30px;} QComboBox::drop-down{border:0;width:28px;}
QComboBox::down-arrow{image:url(__CHEVRON__);width:14px;height:14px;}
QComboBox QAbstractItemView{background:#202936;color:#e6eaf0;border:1px solid #54647b;outline:0;selection-background-color:#355a87;selection-color:#ffffff;padding:4px;}
QComboBox QAbstractItemView::item{min-height:32px;padding-left:8px;}
QPushButton:focus,QComboBox:focus,QLineEdit:focus{border:1px solid #8cb7f4;}
QToolButton{background:#303a49;border:1px solid #47546a;border-radius:5px;padding:7px 30px 7px 12px;}
QToolButton::menu-button{border:0;border-left:1px solid #47546a;width:22px;}
QToolButton::menu-arrow{image:url(__CHEVRON__);width:12px;height:12px;}
QToolButton:hover{background:#3d4d64;} QToolButton:disabled{color:#687385;background:#272e39;border-color:#353e4b;}
QMenu{background:#202936;border:1px solid #54647b;padding:4px;} QMenu::item{padding:8px 16px;} QMenu::item:selected{background:#355a87;}
QTabWidget::pane{border:1px solid #343e4e;background:#232934;border-radius:6px;}
QTabBar::tab{background:#222a36;padding:7px 18px;color:#98a7bb;border-bottom:2px solid transparent;}
QTabBar::tab:selected{color:#dcecff;border-bottom:2px solid #5d9aef;}
QPlainTextEdit,QListWidget{background:#1b222e;border:0;border-radius:4px;padding:4px;selection-background-color:#355c8c;}
QCheckBox{background:transparent;spacing:6px;} QCheckBox::indicator{width:14px;height:14px;border:1px solid #677991;border-radius:3px;background:#192333;}
QCheckBox::indicator:checked{background:#4a8fe9;border:1px solid #75b1ff;}
QScrollBar:vertical{background:#202938;width:9px;}QScrollBar::handle:vertical{background:#53627b;border-radius:4px;min-height:25px;}
QStatusBar{border-top:1px solid #333d4e;color:#a9b5c7;}QStatusBar::item{border:0;}
QSlider::groove:horizontal{height:4px;background:#44516a;border-radius:2px;}
QSlider::sub-page:horizontal{background:#5d9aef;border-radius:2px;}
QSlider::handle:horizontal{background:#d5e5fa;border:1px solid #779ecf;width:12px;margin:-5px 0;border-radius:6px;}
'''.replace('__CHEVRON__',(b.ROOT/'assets/chevron.svg').as_posix())


def combo(items):
    box=W.QComboBox();box.setView(W.QListView());box.addItems(items)
    box.setMaxVisibleItems(min(len(items),8));box.setMinimumContentsLength(5)
    box.setSizeAdjustPolicy(W.QComboBox.AdjustToMinimumContentsLengthWithIcon)
    return box


class ConsoleStyle(W.QProxyStyle):
    def styleHint(self,hint,option=None,widget=None,returnData=None):
        if hint==W.QStyle.SH_ComboBox_Popup:return 0
        return super().styleHint(hint,option,widget,returnData)


class SeekSlider(W.QSlider):
    def jump(self,event):
        option=W.QStyleOptionSlider();self.initStyleOption(option)
        handle=self.style().subControlRect(W.QStyle.CC_Slider,option,W.QStyle.SC_SliderHandle,self)
        groove=self.style().subControlRect(W.QStyle.CC_Slider,option,W.QStyle.SC_SliderGroove,self)
        position=round(event.position().x()-groove.x()-handle.width()/2)
        value=W.QStyle.sliderValueFromPosition(self.minimum(),self.maximum(),position,max(1,groove.width()-handle.width()),option.upsideDown)
        self.setSliderPosition(value);self.sliderMoved.emit(value)
    def mousePressEvent(self,event):
        if event.button()==C.Qt.LeftButton:
            self.setSliderDown(True);self.jump(event);event.accept()
        else:super().mousePressEvent(event)
    def mouseMoveEvent(self,event):
        if self.isSliderDown():self.jump(event);event.accept()
        else:super().mouseMoveEvent(event)
    def mouseReleaseEvent(self,event):
        if event.button()==C.Qt.LeftButton and self.isSliderDown():
            self.jump(event);self.setSliderDown(False);event.accept()
        else:super().mouseReleaseEvent(event)


def configure_app(app):
    # Load the actual CJK font rather than relying on system font substitution.
    for path in ['C:/Windows/Fonts/msyh.ttc','C:/Windows/Fonts/msyhbd.ttc']:
        if Path(path).exists():G.QFontDatabase.addApplicationFont(path)
    app.setFont(G.QFont('Microsoft YaHei',10));app.setStyle(ConsoleStyle('Fusion'))

def label(text='',name=None):
    w=W.QLabel(text)
    if name:w.setObjectName(name)
    return w


def tint(widget,tone):
    if widget.property('tone')!=tone:
        widget.setProperty('tone',tone);widget.style().unpolish(widget);widget.style().polish(widget)


class Video(W.QWidget):
    def __init__(self):
        super().__init__();self.image=G.QImage();self.pose=None;self.setMinimumSize(320,180)
        self.show_person=True;self.background=G.QImage()
        self.setSizePolicy(W.QSizePolicy.Expanding,W.QSizePolicy.Expanding)
    def paintEvent(self,event):
        p=G.QPainter(self);self.draw(p,self.rect())
    def draw(self,p,bounds):
        p.setRenderHints(G.QPainter.Antialiasing|G.QPainter.SmoothPixmapTransform|G.QPainter.TextAntialiasing)
        p.fillRect(bounds,G.QColor('#10151d'))
        if self.image.isNull():
            p.setPen(G.QColor('#8190a6'));p.drawText(bounds,C.Qt.AlignCenter,'点击“开始测试”获取画面');return
        size=self.image.size().scaled(bounds.size(),C.Qt.KeepAspectRatio)
        rect=C.QRectF((bounds.width()-size.width())/2,(bounds.height()-size.height())/2,size.width(),size.height())
        if self.show_person:p.drawImage(rect,self.image)
        elif not self.background.isNull():p.drawImage(rect,self.background)
        if self.pose:
            p.save();p.translate(rect.topLeft());p.scale(rect.width()/1920,rect.height()/1080)
            pen=G.QPen(G.QColor('#55c7ed'),3);pen.setCosmetic(True);p.setPen(pen)
            for person in self.pose.get('people',[]):
                box=person.get('box_xyxy');k=person.get('keypoints_xyc',[])
                if box:
                    box_pen=G.QPen(G.QColor('#ffb65a'),2);box_pen.setCosmetic(True);p.setPen(box_pen)
                    p.drawRect(C.QRectF(box[0],box[1],box[2]-box[0],box[3]-box[1]));p.setPen(pen)
                for i,j in [(5,6),(5,7),(7,9),(6,8),(8,10),(5,11),(6,12),(11,12),(11,13),(13,15),(12,14),(14,16)]:
                    if len(k)>max(i,j) and k[i][2]>.3 and k[j][2]>.3:p.drawLine(C.QPointF(*k[i][:2]),C.QPointF(*k[j][:2]))
                p.setBrush(G.QColor('#eef6ff'))
                for x,y,c in k:
                    if c>.3:p.drawEllipse(C.QPointF(x,y),5,5)
            p.restore()


class Window(W.QMainWindow):
    def __init__(self):
        super().__init__();self.events=queue.Queue();self.closing=False;self.last_id=-1;self.preview_count=0;self.rate_tick=time.monotonic();self.rate_count=0;self.preview_rate=None;self.replay=None;self.current={};self.record_wanted=True
        self.notice='';self.notice_until=0;self.label_key=None;self.replay_path=None;self.replay_frame=0;self.replay_report={}
        self.visible_alarm=None
        self.setWindowTitle('养老姿态监测 · 192.168.50.2');self.resize(1240,820);self.setMinimumSize(1000,700)
        self.setStyleSheet(STYLE)
        body=W.QWidget();self.setCentralWidget(body);main=W.QVBoxLayout(body);main.setContentsMargins(16,12,16,10);main.setSpacing(12)
        header=W.QHBoxLayout();header.setSpacing(10);header.addWidget(label('养老姿态监测','Title'));header.addSpacing(12);header.addWidget(label('192.168.50.2','Muted'))
        self.connected=label('检查中','Muted');header.addWidget(self.connected);header.addStretch()
        self.cloud_badge=self.button('云端：未连接',lambda:self.tabs.setCurrentWidget(self.cloud_page),header)
        self.cloud_badge.setToolTip('打开云端设置；连接状态以服务端接收确认为准')
        self.duration=combo([text for text,_ in DURATIONS]);self.duration.setMinimumWidth(200);self.duration.setCurrentIndex(1);self.duration.setToolTip('定时结束，或手动停止；停止后保存并结束本次会话。手动模式空间不足时会提前结束');header.addWidget(self.duration)
        self.check_btn=self.button('检查',self.check,header);self.start_btn=self.button('开始测试',self.start,header,'Primary');self.stop_btn=self.button('停止',lambda:self.work(b.request_stop),header);main.addLayout(header)
        metrics=W.QHBoxLayout();metrics.setSpacing(10);self.metrics={};self.metric_labels={}
        for key,text,unit in [('source','采集','fps'),('preview','预览','fps'),('pose','检测','fps'),('latency','主机处理延迟','ms'),('record','已录制','帧')]:
            frame=W.QFrame();frame.setObjectName('Panel');layout=W.QVBoxLayout(frame);layout.setContentsMargins(14,9,14,9);layout.setSpacing(2);caption=label(text,'Muted');layout.addWidget(caption);self.metric_labels[key]=caption;value=label('— '+unit,'Metric');layout.addWidget(value);self.metrics[key]=(value,unit);metrics.addWidget(frame,1)
        main.addLayout(metrics)
        middle=W.QHBoxLayout();middle.setSpacing(12);main.addLayout(middle,1)
        left=W.QFrame();left.setObjectName('Panel');lv=W.QVBoxLayout(left);lv.setContentsMargins(1,1,1,1);lv.setSpacing(0)
        vb=W.QHBoxLayout();vb.setContentsMargins(12,8,12,8);vb.setSpacing(10);self.video_title=label('相机 1 · 1080p');vb.addWidget(self.video_title);vb.addStretch();self.state_badge=label('尚未开始','StateBadge');vb.addWidget(self.state_badge);self.frame_id=label('帧 —','Muted');vb.addWidget(self.frame_id);lv.addLayout(vb)
        self.preview_btn=self.button('打开预览',self.preview,vb);self.preview_btn.setToolTip('仅查看相机及拍摄背景，不录像、不检测；单次最长10分钟')
        self.video=Video();lv.addWidget(self.video,1)
        self.replay_controls=W.QWidget();replay_row=W.QHBoxLayout(self.replay_controls);replay_row.setContentsMargins(12,5,12,5);replay_row.setSpacing(10)
        self.pause_btn=self.button('暂停',self.pause_replay,replay_row)
        self.progress=SeekSlider(C.Qt.Horizontal);self.progress.setTracking(False);self.progress.setAccessibleName('录像进度');replay_row.addWidget(self.progress,1)
        self.replay_time=label('00:00 / 00:00','Muted');self.replay_time.setMinimumWidth(100);replay_row.addWidget(self.replay_time)
        self.progress.sliderPressed.connect(self.begin_seek);self.progress.sliderMoved.connect(self.preview_seek);self.progress.sliderReleased.connect(self.end_seek)
        self.progress.valueChanged.connect(self.slider_changed)
        lv.addWidget(self.replay_controls);self.replay_controls.hide();self.replay_paused=False;self.seeking=False
        vb=W.QHBoxLayout();vb.setSpacing(10);vb.setContentsMargins(12,8,12,8);self.bones=W.QCheckBox('骨架');self.bones.setChecked(True);vb.addWidget(self.bones)
        self.real_person=W.QCheckBox('人物');self.real_person.setChecked(True);self.real_person.setToolTip('控制本窗口人物显示；原始录像和RK模型输入不变');self.real_person.toggled.connect(self.person_visibility);vb.addWidget(self.real_person)
        background=W.QToolButton();background.setText('背景');background.setPopupMode(W.QToolButton.InstantPopup)
        background_menu=W.QMenu(background);background_menu.addAction('拍摄',self.capture_background);background_menu.addAction('清除',self.clear_background);background.setMenu(background_menu);vb.addWidget(background)
        vb.addSpacing(8);self.elapsed=label('00:00','Muted');vb.addWidget(self.elapsed);vb.addStretch()
        self.record_btn=self.button('录像：开',self.record,vb);self.record_btn.setToolTip('开始测试时自动录像；测试中可单独开关PC录像')
        self.live_btn=self.button('退出回放',self.live,vb);self.live_btn.setToolTip('关闭录像回放，返回相机页；不会启动采集');lv.addLayout(vb);middle.addWidget(left,1)
        right_scroll=W.QScrollArea();right_scroll.setFixedWidth(292);right_scroll.setWidgetResizable(True);right_scroll.setHorizontalScrollBarPolicy(C.Qt.ScrollBarAlwaysOff)
        right=W.QFrame();right.setObjectName('Panel');right_scroll.setWidget(right);rv=W.QVBoxLayout(right);rv.setContentsMargins(14,12,14,12);rv.setSpacing(6)
        rv.addWidget(label('当前观测','Muted'));self.scene=label('尚未开始','Scene');self.scene.setWordWrap(True);rv.addWidget(self.scene)
        self.reason=label('点击“开始测试”启动监护。','Muted');self.reason.setWordWrap(True);rv.addWidget(self.reason)
        self.posture_hint=label('姿态提示：—');self.posture_hint.setWordWrap(True)
        self.posture_hints=PostureHints()
        self.posture_hint.setToolTip('移植自Pi的二维关键点几何提示；不等同动作分类，不改变跌倒告警判据')
        rv.addWidget(self.posture_hint)
        rv.addSpacing(6);self.alarm_panel=W.QFrame();self.alarm_panel.setObjectName('AlarmPanel');alarm_layout=W.QVBoxLayout(self.alarm_panel);alarm_layout.setContentsMargins(10,9,10,9);alarm_layout.setSpacing(5)
        self.alarm_text=label('告警尚未更新','AlarmTitle');self.alarm_text.setWordWrap(True);alarm_layout.addWidget(self.alarm_text)
        self.alarm_detail=label('开始监护后读取板端告警。');self.alarm_detail.setWordWrap(True);alarm_layout.addWidget(self.alarm_detail)
        ar=W.QHBoxLayout();ar.setSpacing(6);self.ack=self.button('现场知晓',lambda:self.alarm('ack'),ar);self.resolve=self.button('现场解除',lambda:self.alarm('resolve'),ar)
        self.ack.setToolTip('现场人员已知晓本地事件；与APP的远程确认分别记录');self.resolve.setToolTip('现场核查安全后解除板端告警，填写操作人及原因');alarm_layout.addLayout(ar);rv.addWidget(self.alarm_panel);rv.addSpacing(6)
        rv.addWidget(label('FPGA预处理','Muted'));self.mode=combo(MODES);self.mode.setToolTip('支持的FPGA版本可在测试中按帧切换；会改变模型输入');rv.addWidget(self.mode)
        self.mode.currentIndexChanged.connect(self.mode_selected)
        self.mode_state=label('下次启动：彩色原图','Muted');rv.addWidget(self.mode_state)
        self.info={};grid=W.QGridLayout();grid.setVerticalSpacing(7)
        for i,(key,text) in enumerate([('people','人体'),('npu','NPU耗时'),('pose_id','检测源帧')]):
            grid.addWidget(label(text,'Muted'),i,0);self.info[key]=label('—');self.info[key].setAlignment(C.Qt.AlignRight|C.Qt.AlignVCenter);grid.addWidget(self.info[key],i,1)
        rv.addLayout(grid);rv.addStretch(1);middle.addWidget(right_scroll)
        tabs=W.QTabWidget();self.tabs=tabs;tabs.setFixedHeight(170);main.addWidget(tabs)
        actions=W.QWidget();al=W.QVBoxLayout(actions);al.setContentsMargins(10,8,10,8);al.setSpacing(7);row=W.QHBoxLayout();row.setSpacing(10)
        self.action_choice=combo(['站立 / 行走','坐下','卧倒','弯腰','跌倒动作','遮挡 / 出画','弱光','仅备注']);self.action_choice.setMinimumWidth(150);row.addWidget(self.action_choice)
        self.note=W.QLineEdit();self.note.setPlaceholderText('补充备注（可选）：距离、光照、动作情况');self.note.setMaxLength(200);row.addWidget(self.note,1)
        self.mark_btn=self.button('记录此刻',self.note_mark,row);self.mark_btn.setToolTip('人工标记当前源帧，供录像复盘；不改变模型结果，也不触发告警');al.addLayout(row)
        self.label_list=W.QListWidget();self.label_list.setAlternatingRowColors(False);al.addWidget(self.label_list,1);tabs.addTab(actions,'测试记录')
        files=W.QWidget();fl=W.QHBoxLayout(files);self.files=W.QListWidget();fl.addWidget(self.files,1);buttons=W.QVBoxLayout();self.button('窗口内回放',self.play,buttons);self.button('性能汇总',self.summarize_session,buttons);self.button('打开目录',lambda:os.startfile(b.DATA),buttons);buttons.addStretch();fl.addLayout(buttons);tabs.addTab(files,'录像')
        resources=W.QWidget();resources_layout=W.QGridLayout(resources);resources_layout.setContentsMargins(14,8,14,8)
        for i,(key,text) in enumerate([('cpu','CPU / 内存'),('temperature','板卡温度'),('bandwidth','串流带宽'),('faults','故障 / 中止'),('disk','PC可用空间'),('sd','SD卡可用 / 总容量')]):
            group=W.QVBoxLayout();group.setSpacing(4);group.addWidget(label(text,'Muted'));self.info[key]=label('—');group.addWidget(self.info[key]);resources_layout.addLayout(group,i//3,i%3)
        self.resource_state=label('未开始监护时不采集板端指标。','Muted');self.resource_state.setWordWrap(True);resources_layout.addWidget(self.resource_state,2,0,1,2)
        tools=W.QHBoxLayout();tools.setSpacing(8)
        self.sd_refresh_btn=self.button('刷新容量',self.refresh_sd,tools)
        self.sd_clean_btn=self.button('清理录像…',self.manage_sd,tools)
        self.recover_btn=self.button('恢复设备',self.recover_board,tools);self.recover_btn.setToolTip('仅在启动失败且设备空闲时使用，重新加载FPGA SRAM并恢复PCIe');resources_layout.addLayout(tools,2,2)
        self.recovery_text=label('','Muted');self.recovery_text.setWordWrap(True);self.recovery_text.hide();resources_layout.addWidget(self.recovery_text,3,0,1,3)
        self.recovery_progress=W.QProgressBar();self.recovery_progress.setRange(0,100);self.recovery_progress.setTextVisible(False);self.recovery_progress.setFixedHeight(5);self.recovery_progress.hide();resources_layout.addWidget(self.recovery_progress,4,0,1,3)
        self.device_page=resources;self.sd_inventory=None;self.storage_busy=False;self.next_sd_refresh=0
        tabs.currentChanged.connect(lambda _:self.refresh_sd() if tabs.currentWidget() is resources else None)
        tabs.addTab(resources,'设备')
        image_settings=W.QWidget();image_layout=W.QFormLayout(image_settings);image_layout.setContentsMargins(14,12,14,12);image_layout.setSpacing(10)
        self.binary_threshold=W.QCheckBox('阈值二值化');image_layout.addRow(self.binary_threshold)
        self.binary_value=W.QSpinBox();self.binary_value.setRange(0,255);self.binary_value.setValue(128);self.binary_value.setEnabled(False)
        self.binary_threshold.toggled.connect(self.binary_value.setEnabled);image_layout.addRow('亮度阈值',self.binary_value)
        self.binary_state=label('下次测试生效；处理后的画面也会送入模型。','Muted');self.binary_state.setWordWrap(True);image_layout.addRow(self.binary_state)
        tabs.addTab(image_settings,'图像')
        compression=W.QWidget();compression_layout=W.QGridLayout(compression);compression_layout.setContentsMargins(14,8,14,8);compression_layout.setHorizontalSpacing(16)
        compression_layout.addWidget(label('压缩方式','Muted'),0,0);self.compression_mode=combo(['固定质量','目标码率']);compression_layout.addWidget(self.compression_mode,1,0)
        compression_layout.addWidget(label('JPEG质量','Muted'),0,1);self.jpeg_quality=combo(['省带宽 · Q25','均衡 · Q50','清晰 · Q75']);self.jpeg_quality.setCurrentIndex(1);compression_layout.addWidget(self.jpeg_quality,1,1)
        compression_layout.addWidget(label('目标码率','Muted'),0,2);self.target_mbps=W.QSpinBox();self.target_mbps.setRange(8,120);self.target_mbps.setValue(36);self.target_mbps.setSuffix(' Mbps');compression_layout.addWidget(self.target_mbps,1,2)
        self.compression_state=label('等待压缩状态','Muted');compression_layout.addWidget(self.compression_state,2,0,1,3)
        compression_hint=label('养老测试先用Q50；目标码率可能降低弱光检出率。','Muted');compression_hint.setWordWrap(True);compression_layout.addWidget(compression_hint,3,0,1,3)
        self.jpeg_quality.setToolTip('目标码率模式下作为起始质量；压缩会影响模型输入，需对比检测效果')
        self.target_mbps.setToolTip('JPEG载荷目标；30帧平均控制范围±5%，不是严格CBR；Q1..Q75自动调节。低Q可能影响识别，养老现场默认使用固定Q50')
        tabs.addTab(compression,'压缩')
        log_page=W.QWidget();log_layout=W.QVBoxLayout(log_page);log_layout.setContentsMargins(10,6,10,6)
        log_tools=W.QHBoxLayout();self.log_space=label('板端历史日志','Muted');log_tools.addWidget(self.log_space,1)
        self.log_manage_btn=self.button('查看 / 清理…',self.manage_logs,log_tools);log_layout.addLayout(log_tools)
        self.logs=W.QPlainTextEdit();self.logs.setReadOnly(True);log_layout.addWidget(self.logs,1);tabs.addTab(log_page,'日志');self.log_key=None;self.file_key=None
        self.cloud_bridge=None
        self.cloud_page=W.QWidget();cloud_layout=W.QVBoxLayout(self.cloud_page);cloud_layout.setContentsMargins(14,8,14,8);cloud_layout.setSpacing(8)
        cloud_row=W.QHBoxLayout();self.cloud_status=label('未连接云端','Title');cloud_row.addWidget(self.cloud_status);cloud_row.addStretch()
        self.cloud_start_btn=self.button('连接云端',self.connect_cloud,cloud_row);self.cloud_stop_btn=self.button('断开连接',self.disconnect_cloud,cloud_row);cloud_layout.addLayout(cloud_row)
        self.cloud_detail=label('未启用远程查看','Muted');self.cloud_detail.setToolTip('上传骨架与状态；已同步以云服务回执为准');cloud_row.insertWidget(1,self.cloud_detail,1)
        self.cloud_detail.setWordWrap(True)
        cloud_options=W.QHBoxLayout();cloud_options.setSpacing(14)
        self.cloud_alarms=W.QCheckBox('同步告警');self.cloud_alarms.setToolTip('将本地未解除告警转发至APP；本次连接有效')
        cloud_options.addWidget(self.cloud_alarms);self.cloud_alarms.toggled.connect(self.toggle_cloud_alarms)
        cloud_options.addStretch();self.button('设备绑定…',self.cloud_pairing,cloud_options);cloud_layout.addLayout(cloud_options)
        cloud_layout.addStretch();tabs.addTab(self.cloud_page,'远程连接')
        if '--maintenance' in sys.argv:
            maintenance=self.menuBar().addMenu('维护');maintenance.addAction('拍屏测延迟',self.open_latency);maintenance.addAction('选中录像在RK重新检测',self.replay_on_rk)
        else:self.menuBar().hide()
        self.statusBar().showMessage('等待设备检查')
        b.DATA.mkdir(exist_ok=True,parents=True);threading.Thread(target=b.preview_worker,daemon=True).start()
        self.next_file_scan=0
        self.timer=C.QTimer(self);self.timer.timeout.connect(self.tick);self.timer.start(25);C.QTimer.singleShot(100,self.check)

    def button(self,text,fn,layout,name=None):
        w=W.QPushButton(text);w.clicked.connect(fn)
        if name:w.setObjectName(name)
        layout.addWidget(w);return w
    def open_latency(self):
        from latency_window1508 import LatencyWindow
        dialog=LatencyWindow(self);dialog.setStyleSheet(STYLE);dialog.show();self.latency_window=dialog
    def recover_board(self):
        if self.storage_busy:return self.feedback('请等待存储操作结束')
        with b.LOCK:busy=b.STATE.get('phase') in ('STARTING','RUNNING','STOPPING','FINALIZING') or b.STATE.get('offline_busy')
        if busy:return self.feedback('请先停止测试并等待会话完成')
        if getattr(self,'recovering',False):return self.feedback('设备恢复正在进行')
        self.recovering=True;self.feedback('正在恢复设备，详情见日志；不会启动采集')
        self.recovery_started=time.monotonic();self.recovery_stage='正在检查恢复条件'
        self.recovery_progress.setValue(0);self.recovery_progress.show();self.recovery_text.show()
        self.tabs.setCurrentWidget(self.device_page)
        def changed(row):
            self.recovery_stage=row['message'];self.recovery_progress.setValue(row['percent'])
            b.log(row['message'])
        def run():
            from resource_gate1695 import acquire
            from recovery_support import run_recovery
            lease=None
            try:
                lease=acquire()
                path=run_recovery(b.ROOT,lambda row:self.events.put((changed,row,None)))
                result=b.preflight()
                if not result['ready']:raise RuntimeError(result['reason'])
                return dict(result=result,log=str(path))
            except Exception as error:return dict(error=str(error))
            finally:
                if lease:lease.close()
        def finished(value):
            self.recovering=False
            self.recovery_stage=('恢复未通过：'+value['error']) if value.get('error') else '设备恢复完成，可开始测试'
            self.recovery_text.setText(self.recovery_stage)
            if not value.get('error'):self.recovery_progress.setValue(100)
            self.feedback(self.recovery_stage)
        self.work(run,finished)
    def person_visibility(self,visible):
        self.video.show_person=visible;self.video.update()
    def capture_background(self):
        if self.replay:return self.feedback('请先退出回放，再拍摄空场背景')
        with b.LOCK:
            data=b.PREVIEW;frame=b.PREVIEW_ID;name=b.STATE.get('session');age=time.monotonic_ns()-b.STATE.get('preview_updated_pc_ns',0)
            running=b.STATE.get('phase')=='RUNNING'
        if not data or not running or not 0<=age<2_000_000_000:return self.feedback('请在直播画面更新正常时拍摄背景')
        shared=self.cloud_bridge and hasattr(self.cloud_bridge,'refresh_background')
        expected=self.cloud_bridge.background_version if shared else None
        if shared and expected is None:return self.feedback('背景尚未同步，请稍后再拍摄')
        if W.QMessageBox.question(self,'拍摄空场背景','请确认画面无人、机位固定。\n背景用于隐私预览，连接云端后也可供云端背景使用；原始录像仍保留人物。\n是否保存无人背景？')!=W.QMessageBox.Yes:return
        directory=b.DATA/'backgrounds';directory.mkdir(exist_ok=True)
        path=directory/('background_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f')+'.jpg')
        path.write_bytes(data)
        path.with_suffix('.json').write_text(json.dumps(dict(source_frame_id=frame,session=name,orientation='upright preview',operator_confirmed_empty=True,created=datetime.now().isoformat()),ensure_ascii=False,indent=2),encoding='utf-8')
        if not shared:
            self.video.background=G.QImage.fromData(data)
            with b.LOCK:b.APPROVED_BACKGROUND=data
        if self.cloud_bridge and hasattr(self.cloud_bridge,'approve_background'):
            if shared:
                try:self.cloud_bridge.approve_background(data,expected_version=expected)
                except ValueError as error:return self.feedback(str(error))
            else:self.cloud_bridge.approve_background(data)
        self.feedback('背景已保存，等待云端确认后同步至两端' if shared else '背景已保存；取消“人物”可查看骨架与背景')
    def clear_background(self):
        self.video.background=G.QImage()
        with b.LOCK:b.APPROVED_BACKGROUND=None
        self.video.update();self.feedback('已清除当前显示背景，已保存文件保留')
    def connect_cloud(self):
        if self.cloud_bridge:return self.feedback('云端已启动，请先断开再更换设备')
        default=b.ROOT/'cloud1694.local.json'
        if default.is_file():path=str(default)
        else:path,_=W.QFileDialog.getOpenFileName(self,'选择专用云端设备配置',str(b.ROOT),'JSON (*.json)')
        if not path:return
        try:
            config=json.loads(Path(path).read_text(encoding='utf-8-sig'))
            if config.get('transport')=='board':
                from board_cloud_proxy import BoardCloudBridge as CloudBridge
            else:
                from cloud1694 import CloudBridge
            bridge=CloudBridge(path,b)
            enabled=self.cloud_alarms.isChecked() or bridge.config.get('forward_alarms',False)
            if enabled and not self.cloud_alarms.isChecked():
                if W.QMessageBox.question(self,'转发真实检测告警','此配置会将检测告警发送至APP，服务端可能触发推送。\n请确认这是专用测试设备。是否连接？')!=W.QMessageBox.Yes:return
            bridge.set_alarm_forwarding(enabled)
            self.cloud_alarms.blockSignals(True);self.cloud_alarms.setChecked(enabled);self.cloud_alarms.blockSignals(False)
            self.cloud_bridge=bridge;bridge.start();self.feedback('板端直连已启用，等待检测数据与云端确认' if config.get('transport')=='board' else '云端已配置，等待检测数据与服务端确认')
        except Exception as error:self.feedback(str(error))
    def toggle_cloud_alarms(self,enabled):
        if enabled and W.QMessageBox.question(self,'转发告警到APP','开启后将同步本地未解除的告警，包括历史待处理事件，云端可能触发推送。\n请先核查当前告警。是否开启？')!=W.QMessageBox.Yes:
            self.cloud_alarms.blockSignals(True);self.cloud_alarms.setChecked(False);self.cloud_alarms.blockSignals(False);return
        if self.cloud_bridge:self.cloud_bridge.set_alarm_forwarding(enabled)
    def cloud_pairing(self):
        from cloud_binding import binding_status
        dialog=W.QDialog(self);dialog.setWindowTitle('设备绑定');dialog.setMinimumWidth(480)
        layout=W.QVBoxLayout(dialog);layout.setContentsMargins(20,18,20,18);layout.setSpacing(14)
        state=label('正在查询绑定状态…','Title');state.setWordWrap(True);layout.addWidget(state)
        form=W.QFormLayout();form.setSpacing(10);fields={}
        for key,title in [('server_url','服务地址'),('device_id','设备号'),('bind_code','一次性绑定码')]:
            field=W.QLineEdit();field.setReadOnly(True);fields[key]=field;form.addRow(title,field)
        layout.addLayout(form)
        hint=label('在APP登录账号后添加设备。');hint.setWordWrap(True);layout.addWidget(hint)
        row=W.QHBoxLayout();refresh=self.button('刷新',lambda:load(False),row)
        renew=self.button('重新生成绑定码',lambda:regenerate(),row);renew.setEnabled(False);row.addStretch()
        self.button('关闭',dialog.accept,row);layout.addLayout(row)
        def show(value):
            if not dialog.isVisible():return
            refresh.setEnabled(True);renew.setEnabled(not value['bound'])
            state.setText('已绑定账号' if value['bound'] else '等待绑定')
            for key,field in fields.items():field.setText(str(value.get(key) or ''))
            fields['bind_code'].setPlaceholderText('已使用' if value['bound'] else '请重新生成，或使用APP解绑时提供的新码')
            hint.setText('换手机或重装APP：登录原账号即可。更换账号：先由原账号在APP解绑。' if value['bound'] else '在APP添加此设备。绑定码使用后失效；重新生成会使旧码失效。')
        def load(regenerate):
            refresh.setEnabled(False);renew.setEnabled(False);state.setText('正在查询…')
            for field in fields.values():field.clear()
            def fetch():
                try:return binding_status(regenerate)
                except Exception:return None
            def done(value):
                if not dialog.isVisible():return
                if value is not None:show(value)
                else:
                    state.setText('暂时无法查询');refresh.setEnabled(True)
                    hint.setText('检查网络后刷新。登录原APP账号不需要重新绑定。')
            self.work(fetch,done)
        def regenerate():
            if W.QMessageBox.question(dialog,'重新生成绑定码','旧绑定码将立即失效，是否继续？')==W.QMessageBox.Yes:load(True)
        C.QTimer.singleShot(0,lambda:load(False));dialog.exec()
    def disconnect_cloud(self):
        if self.cloud_bridge:self.cloud_bridge.stop();self.cloud_bridge=None;self.feedback('云端转发已停止')
    def refresh_cloud(self):
        bridge=self.cloud_bridge
        self.cloud_start_btn.setEnabled(bridge is None);self.cloud_stop_btn.setEnabled(bridge is not None)
        if bridge is None:
            self.cloud_badge.setText('云端：未连接');self.cloud_status.setText('未连接云端')
            self.cloud_detail.setText('未启用远程查看');tint(self.cloud_status,'neutral');return
        value=bridge.connection_status();state=value['state']
        if state=='synced' and time.monotonic_ns()-value['last_ack_ns']>5_000_000_000:state='paused'
        title,tone={
            'waiting':('等待检测数据','neutral'),'connecting':('正在连接','neutral'),
            'synced':('已同步','normal'),'paused':('同步暂停','warning'),
            'retrying':('连接异常 · 重试中','warning'),'stopping':('正在断开','neutral'),
            'stopped':('连接已停止','neutral'),
        }.get(state,('连接状态未知','warning'))
        self.cloud_status.setText(title);tint(self.cloud_status,tone);self.cloud_badge.setText('云端：'+title)
        route='板端直连 · ' if value.get('transport')=='board' else ''
        bg=' · '+value['background_status'] if value.get('background_status') else ''
        self.cloud_detail.setText(f"{route}{DEVICE_NAME} · 已接收 {value['accepted_packets']} 条"+bg)
    def summarize_session(self):
        item=self.files.currentItem()
        if not item:return self.feedback('先选择已结束会话的录像')
        from session_summary1694 import export_summary
        self.feedback('正在核对原始录像并汇总性能…')
        self.work(lambda:export_summary(Path(item.data(C.Qt.UserRole)).parent),lambda result:self.feedback('性能汇总已保存：'+str(result[0])))
    def replay_on_rk(self):
        item=self.files.currentItem()
        if not item:return self.feedback('请在录像页选择已结束会话')
        if getattr(self,'recovering',False):return self.feedback('请先等待设备恢复结束')
        from replay1695 import run_replay
        path=Path(item.data(C.Qt.UserRole)).parent
        self.feedback('开始RK原片重新检测，期间请勿开始实时测试；结果保存在原会话replays目录')
        self.work(lambda:run_replay(path),lambda result:self.feedback('RK复盘完成，结果目录：'+str(result[0])))
    def work(self,fn,done=None):
        def run():
            try:self.events.put((done,fn(),None))
            except BaseException as e:self.events.put((None,None,str(e)))
        threading.Thread(target=run,daemon=True).start()
    def check(self):
        def checked(r):
            if r['ready']:text='设备就绪'
            elif not r.get('endpoint'):text='网络已连 · FPGA待恢复'
            elif r.get('registers',{}).get('0x84',0)&9 != 1:text='网络已连 · 相机初始化失败'
            else:text='网络已连 · 启动条件未满足'
            self.connected.setText(text)
        self.work(b.preflight,checked)
    def start(self):
        if self.storage_busy:return self.feedback('请等待存储操作结束')
        if getattr(self,'starting',False):return self.feedback('正在同步背景并准备启动，请稍候')
        if getattr(self,'recovering',False):return self.feedback('请等待设备恢复结束')
        seconds=DURATIONS[self.duration.currentIndex()][1]
        if seconds in (0,7200):
            text='手动停止模式单次最多2小时，点击停止后保存并结束。' if seconds==0 else '即将启动2小时测试。'
            if W.QMessageBox.question(self,'确认长时间运行',text+'\n请确认设备和存储已准备好，是否开始？')!=W.QMessageBox.Yes:return
        self.live()
        selected=self.mode.currentIndex();record=self.record_wanted
        compression='target' if self.compression_mode.currentIndex() else 'quality'
        quality=(25,50,75)[self.jpeg_quality.currentIndex()];target=self.target_mbps.value()
        binary=self.binary_value.value() if self.binary_threshold.isChecked() else None
        values=dict(seconds=seconds,record=record,preprocess=selected,compression=compression,jpeg_quality=quality,target_mbps=target,binary_threshold=binary)
        def begin():
            bridge=self.cloud_bridge
            if bridge and hasattr(bridge,'refresh_background'):
                try:bridge.refresh_background(force=True)
                except Exception:b.log('启动前背景同步失败，保留原背景；采集仍可启动')
            with b.LOCK:preview=b.STATE.get('purpose')=='preview' and b.THREAD and b.THREAD.is_alive()
            if preview:
                b.request_stop();b.THREAD.join(timeout=100)
                if b.THREAD.is_alive() or b.STATE['phase']!='DONE':raise RuntimeError('预览未正常关闭，请检查设备后再测试')
            return b.start(values)
        self.starting=True
        def launch():
            try:return begin()
            finally:self.starting=False
        self.work(launch)
    def preview(self):
        if self.storage_busy:return self.feedback('请等待存储操作结束')
        if getattr(self,'recovering',False):return self.feedback('请等待设备恢复结束')
        with b.LOCK:
            busy=b.THREAD and b.THREAD.is_alive()
            preview=b.STATE.get('purpose')=='preview'
        if busy:
            if preview:self.work(b.request_stop)
            else:self.feedback('请先停止测试，再打开独立预览')
            return
        self.live()
        self.work(lambda:b.start(dict(purpose='preview',seconds=600,record=False,preprocess=0,
                                     compression='quality',jpeg_quality=50)))
    def mode_selected(self,index):
        with b.LOCK:running=b.STATE['phase']=='RUNNING'
        if running:
            self.mode.setEnabled(False);self.mode_state.setText('正在切换…')
            self.work(lambda:b.set_preprocess(index))
        else:self.mode_state.setText('下次启动：'+MODES[index])
    def record(self):
        self.record_wanted=not self.record_wanted
        with b.LOCK:b.RECORD_WANTED=self.record_wanted
        self.record_btn.setText('录像：开' if self.record_wanted else '录像：关')
    def feedback(self,text):
        self.notice=text;self.notice_until=time.monotonic()+6;self.statusBar().showMessage(text)
    def apply_sd(self,result):
        self.sd_inventory=result
        self.info['sd'].setText(f"{result['free_bytes']/1024**3:.1f} / {result['total_bytes']/1024**3:.1f} GiB")
        when=datetime.fromtimestamp(result['checked_at_ns']/1e9).strftime('%H:%M:%S')
        self.info['sd'].setToolTip('最近读取 '+when+(' · 正在使用' if result.get('in_use') else ''))
    def sd_request(self,action,done=None,selected=None):
        if self.storage_busy:return self.feedback('正在读取或清理SD卡，请稍候')
        with b.LOCK:phase=b.STATE.get('phase')
        if action=='status' and (getattr(self,'starting',False) or getattr(self,'recovering',False) or phase in ('STARTING','STOPPING','FINALIZING')):
            return self.feedback('设备正在切换状态，请稍后刷新容量')
        if action!='status' and (getattr(self,'starting',False) or getattr(self,'recovering',False) or (b.THREAD and b.THREAD.is_alive())):
            return self.feedback('请先停止测试或预览，等待录像保存完成')
        from pc_storage import request
        self.storage_busy=True
        def run():
            try:return request(b,action,selected)
            finally:self.storage_busy=False
        def loaded(result):
            self.apply_sd(result)
            if done:done(result)
        self.work(run,loaded)
    def refresh_sd(self):
        self.next_sd_refresh=time.monotonic()+15
        self.sd_request('status')
    def manage_sd(self):
        self.feedback('正在读取SD录像列表…')
        self.sd_request('scan',self.sd_dialog)
    def manage_logs(self):
        if self.storage_busy:return self.feedback('正在处理存储，请稍候')
        with b.LOCK:phase=b.STATE.get('phase')
        if phase in ('STARTING','RUNNING','STOPPING','FINALIZING') or b.STATE.get('offline_busy') or getattr(self,'starting',False) or getattr(self,'recovering',False):
            return self.feedback('请先停止测试或预览，等待保存完成')
        self.storage_busy=True;self.feedback('正在读取板端日志列表…')
        def run():
            from pc_storage import request
            try:return request(b,'scan',kind='evidence')
            finally:self.storage_busy=False
        self.work(run,lambda result:self.sd_dialog(result,'evidence'))
    def sd_dialog(self,result,kind='sd'):
        evidence=kind=='evidence'
        from pc_storage import pc_recording_status
        class StorageDialog(W.QDialog):
            working=False
            def reject(self):
                if not self.working:super().reject()
            def closeEvent(self,event):
                if self.working:event.ignore()
                else:super().closeEvent(event)
        dialog=StorageDialog(self);dialog.setWindowTitle('板端日志' if evidence else 'SD录像');dialog.resize(760,460);dialog.setMinimumSize(640,360)
        layout=W.QVBoxLayout(dialog);layout.setContentsMargins(18,16,18,16);layout.setSpacing(12)
        capacity=label('','Title');layout.addWidget(capacity)
        hint=label('清理会删除所选会话的板端日志与诊断数据；PC文件、SD录像、模型和背景保留。' if evidence else '只删除勾选的SD会话。PC录像、检测日志和背景保留。');hint.setWordWrap(True);layout.addWidget(hint)
        table=W.QTableWidget(0,4);table.setHorizontalHeaderLabels(['日志会话','占用','PC留存','状态'] if evidence else ['拍摄时间','占用','PC录像','状态'])
        table.setEditTriggers(W.QAbstractItemView.NoEditTriggers);table.setSelectionBehavior(W.QAbstractItemView.SelectRows)
        table.verticalHeader().hide();table.horizontalHeader().setSectionResizeMode(0,W.QHeaderView.Stretch)
        for column in (1,2,3):table.horizontalHeader().setSectionResizeMode(column,W.QHeaderView.ResizeToContents)
        layout.addWidget(table,1)
        total=label('','Muted');layout.addWidget(total)
        progress=W.QProgressBar();progress.setRange(0,0);progress.setFixedHeight(5);progress.setTextVisible(False);progress.hide();layout.addWidget(progress)
        row=W.QHBoxLayout();all_btn=self.button('全选',lambda:choose_all(),row)
        if evidence:self.button('查看日志',lambda:show_log(),row)
        row.addStretch()
        clean=self.button('删除所选',lambda:remove(),row);close=self.button('关闭',dialog.reject,row);layout.addLayout(row)
        deleting=False
        def selection():
            return [table.item(i,0).data(C.Qt.UserRole) for i in range(table.rowCount()) if table.item(i,0).checkState()==C.Qt.Checked]
        def update_selection():
            items=selection();size=sum(item['bytes'] for item in items)
            total.setText(f'已选 {len(items)} 段 · {size/1024**3:.2f} GiB')
            clean.setEnabled(bool(items) and not deleting)
        def fill(value):
            capacity.setText(f"可用 {value['free_bytes']/1024**3:.2f} / {value['total_bytes']/1024**3:.1f} GiB" if evidence else f"可用 {value['free_bytes']/1024**3:.1f} / {value['total_bytes']/1024**3:.1f} GiB")
            table.blockSignals(True);table.setRowCount(len(value['sessions']))
            for i,item in enumerate(value['sessions']):
                parts=item['name'].split('_')
                stamp=(parts[1][:4]+'-'+parts[1][4:6]+'-'+parts[1][6:8]+' '+parts[2][:2]+':'+parts[2][2:4]+':'+parts[2][4:6]) if len(parts)>=3 else item['name']
                name=W.QTableWidgetItem(item['name'] if evidence else stamp);name.setData(C.Qt.UserRole,item);name.setToolTip(item['name'])
                if item['eligible']:name.setFlags(name.flags()|C.Qt.ItemIsUserCheckable);name.setCheckState(C.Qt.Unchecked)
                else:name.setFlags(name.flags()&~C.Qt.ItemIsEnabled)
                table.setItem(i,0,name);table.setItem(i,1,W.QTableWidgetItem(f"{item['bytes']/1024**2:.1f} MiB"))
                table.setItem(i,2,W.QTableWidgetItem(('有PC日志（非完整备份）' if (b.DATA/item['name']/'report.json').is_file() else '未找到PC日志') if evidence else pc_recording_status(b.DATA,item['name'])))
                state=W.QTableWidgetItem('可清理' if item['eligible'] else '保留');state.setToolTip(item.get('reason',''));table.setItem(i,3,state)
            table.blockSignals(False)
            if not value['sessions']:hint.setText('没有可列出的板端日志。' if evidence else 'SD卡没有可列出的现场会话。其他文件不在清理范围内。')
            elif value.get('excluded_entries') and not evidence:hint.setText('只删除勾选的SD会话，其他文件保留。PC录像状态仅供参考，并非完整备份校验。')
            update_selection()
        def show_log():
            if self.storage_busy:return self.feedback('正在处理存储，请稍候')
            index=table.currentRow()
            if index<0:return self.feedback('请先点选一行日志')
            item=table.item(index,0).data(C.Qt.UserRole)
            from pc_storage import request
            self.storage_busy=True;self.feedback('正在读取日志…')
            def read():
                try:return request(b,'view',kind='evidence',name=item['name'])
                finally:self.storage_busy=False
            def show(value):
                viewer=W.QDialog(dialog);viewer.setWindowTitle(value['name']);viewer.resize(800,540)
                content=W.QVBoxLayout(viewer);text=W.QPlainTextEdit();text.setReadOnly(True);text.setPlainText(value['text']);content.addWidget(text)
                content.addWidget(label('最多显示12个文本文件，每个文件末尾8 KiB。','Muted'))
                self.button('关闭',viewer.reject,content);dialog.log_viewer=viewer;viewer.open()
            self.work(read,show)
        def choose_all():
            for i in range(table.rowCount()):
                item=table.item(i,0)
                if item.flags()&C.Qt.ItemIsUserCheckable:item.setCheckState(C.Qt.Checked)
        def remove():
            nonlocal deleting
            if evidence and self.storage_busy:return self.feedback('正在处理存储，请稍候')
            chosen=selection()
            if not chosen:return
            missing=sum(pc_recording_status(b.DATA,item['name'])!='有PC录像' for item in chosen)
            message=f"删除 {len(chosen)} 个{'板端日志会话' if evidence else 'SD会话'}，共 {sum(item['bytes'] for item in chosen)/1024**3:.2f} GiB？\n此操作不可撤销。"
            if missing and not evidence:message+=f'\n其中 {missing} 个会话未找到PC录像。'
            if evidence:message+='\n将删除该会话的全部板端诊断文件；PC留存不代表完整备份。'
            if W.QMessageBox.question(dialog,'删除板端日志' if evidence else '删除SD录像',message,W.QMessageBox.Yes|W.QMessageBox.No,W.QMessageBox.No)!=W.QMessageBox.Yes:return
            deleting=True;dialog.working=True;table.setEnabled(False);all_btn.setEnabled(False);clean.setEnabled(False);close.setEnabled(False)
            clean.setText('正在删除…');progress.show()
            started=time.monotonic()
            def show_progress():
                seconds=int(time.monotonic()-started)
                total.setText(f"正在清理 {len(chosen)} 个{'板端日志会话' if evidence else 'SD会话、同步并卸载SD卡'} · 已用 {seconds} 秒")
            clock=C.QTimer(dialog);clock.setInterval(1000);clock.timeout.connect(show_progress);show_progress();clock.start()
            # Block Escape/window close until deletion and unmount have returned.
            def run():
                from pc_storage import request
                try:
                    selected=[dict(name=item['name'],fingerprint=item['fingerprint']) for item in chosen]
                    return dict(value=request(b,'delete',selected,kind='evidence') if evidence else request(b,'delete',selected))
                except Exception as error:return dict(error=str(error))
            self.storage_busy=True
            def finished(outcome):
                nonlocal deleting
                clock.stop();progress.hide();clean.setText('删除所选')
                self.storage_busy=False;deleting=False;dialog.working=False;table.setEnabled(True);all_btn.setEnabled(True);close.setEnabled(True)
                if outcome.get('error'):
                    self.feedback(outcome['error']);update_selection()
                    hint.setText('清理结果未确认：'+outcome['error']+'；请关闭窗口并刷新容量核对。')
                else:
                    if evidence:self.log_space.setText(f"板端可用 {outcome['value']['free_bytes']/1024**3:.2f} GiB")
                    else:self.apply_sd(outcome['value'])
                    fill(outcome['value']);self.feedback('板端日志已清理' if evidence else 'SD录像已清理')
                    hint.setText(f"已删除 {len(outcome['value']['deleted_sessions'])} 个会话，释放 {outcome['value']['deleted_bytes']/1024**3:.2f} GiB"+('。' if evidence else '；SD卡已卸载。'))
            self.work(run,finished)
        table.itemChanged.connect(lambda _:update_selection());fill(result)
        # Open without nesting the event loop inside tick(): its completion queue
        # must keep draining while this dialog is visible.
        if evidence:self.log_space.setText(f"板端可用 {result['free_bytes']/1024**3:.2f} GiB · 日志 {sum(item['bytes'] for item in result['sessions'])/1024**3:.2f} GiB")
        self.sd_window=dialog
        dialog.finished.connect(lambda _:setattr(self,'sd_window',None))
        dialog.open()
    def mark(self,text,note=''):
        with b.LOCK:
            name=b.STATE['session'];frame=b.STATE.get('latest_frame');elapsed=b.STATE.get('elapsed_s',0);running=b.STATE['phase']=='RUNNING'
        if not running or self.replay or frame is None:
            self.feedback('请在测试直播中记录动作');return False
        row=dict(label=text,note=note,source_frame_id=frame,elapsed_s=elapsed,pc_time=datetime.now().isoformat(),pc_ns=time.monotonic_ns(),kind='manual_observation')
        try:
            with (b.DATA/name/'labels.jsonl').open('a',encoding='utf-8') as f:f.write(json.dumps(row,ensure_ascii=False)+'\n')
        except OSError as e:self.feedback('记录失败：'+str(e));return False
        self.label_key=None;self.feedback(f'已记录：{text} · 源帧 {frame}');b.log('人工记录：'+text);return True
    def note_mark(self):
        note=self.note.text().strip();text=self.action_choice.currentText()
        if text=='仅备注' and not note:return self.feedback('请填写备注')
        if self.mark(text,note):self.note.clear()
    def refresh_labels(self,session):
        path=b.DATA/session/'labels.jsonl' if session else None
        key=(str(path),path.stat().st_mtime_ns if path and path.exists() else None)
        if key==self.label_key:return
        self.label_key=key;self.label_list.clear()
        if not path or not path.exists():
            item=W.QListWidgetItem('动作发生时点“记录此刻”，供录像复盘；不会改变检测结果。');item.setFlags(C.Qt.NoItemFlags);self.label_list.addItem(item);return
        try:
            for line in reversed(path.read_text(encoding='utf-8').splitlines()):
                row=json.loads(line);seconds=int(row.get('elapsed_s',0));text=f"{seconds//60:02}:{seconds%60:02}  {row['label']}"
                if row.get('note'):text+=' · '+row['note']
                text+='    源帧 '+str(row.get('source_frame_id','—'))
                item=W.QListWidgetItem(text);item.setToolTip(text);self.label_list.addItem(item)
        except (OSError,ValueError) as e:self.feedback('读取记录失败：'+str(e))
    def alarm(self,verb):
        alarm=self.visible_alarm
        if not alarm or self.replay or getattr(self,'alarm_pending',False):return
        session=self.current.get('session');incident_id=alarm['id']
        title='知晓告警' if verb=='ack' else '解除告警'
        prompt=('仅标记已知晓，告警仍保留。' if verb=='ack' else '请核查人员情况，确认安全后再解除。')+f'\n事件 #{incident_id}，请填写操作人及原因：'
        reason,ok=W.QInputDialog.getText(self,title,prompt)
        if ok and reason.strip():
            self.alarm_pending=True
            def apply_action():
                try:
                    result=b.action(session,verb,incident_id,reason)
                    with b.LOCK:
                        if b.STATE.get('session')==session:b.STATE.setdefault('telemetry',{})['alarm']=result['active']
                    return result
                finally:self.alarm_pending=False
            self.work(apply_action,lambda result:self.feedback('告警已知晓，等待处理' if verb=='ack' else '告警已解除'))
    def live(self):
        if self.replay:self.replay.release()
        self.replay=None;self.replay_path=None;self.replay_report={};self.last_id=-1
        self.video.image=G.QImage();self.video.pose=None;self.video_title.setText('相机 1 · 1080p')
        self.replay_controls.hide();self.seeking=False;self.replay_paused=False
    def pause_replay(self):
        if not self.replay:return
        if self.replay_paused and self.replay_frame>=self.replay_total:self.seek_replay(0)
        self.replay_paused=not self.replay_paused
        self.replay_start=time.monotonic()-max(0,self.replay_frame-1)/self.replay_fps
        self.pause_btn.setText('播放' if self.replay_paused else '暂停')
    def replay_clock(self,frame):
        def stamp(seconds):
            seconds=max(0,int(seconds));return f'{seconds//60:02}:{seconds%60:02}'
        self.replay_time.setText(stamp(frame/self.replay_fps)+' / '+stamp(max(0,self.replay_total-1)/self.replay_fps))
    def begin_seek(self):
        self.seeking=True
    def preview_seek(self,value):
        if self.replay:self.replay_clock(value)
    def end_seek(self):
        target=self.progress.sliderPosition();self.seeking=False;self.seek_replay(target)
    def slider_changed(self,value):
        if self.replay and not self.seeking and not self.progress.isSliderDown():self.seek_replay(value)
    def seek_replay(self,frame):
        if not self.replay:return
        import cv2
        frame=max(0,min(frame,self.replay_total-1))
        if not self.replay.set(cv2.CAP_PROP_POS_FRAMES,frame):return self.feedback('此录像无法跳转')
        self.read_replay_frame()
        self.replay_start=time.monotonic()-max(0,self.replay_frame-1)/self.replay_fps
        self.video.update()
    def read_replay_frame(self):
        import cv2
        ok,frame=self.replay.read()
        if not ok:
            self.replay_paused=True;self.pause_btn.setText('播放');self.video_title.setText('回放结束 · '+self.replay_path.name);return False
        self.replay_frame=int(self.replay.get(cv2.CAP_PROP_POS_FRAMES))
        frame=cv2.cvtColor(cv2.rotate(frame,cv2.ROTATE_180),cv2.COLOR_BGR2RGB)
        self.video.image=G.QImage(frame.data,frame.shape[1],frame.shape[0],frame.strides[0],G.QImage.Format_RGB888).copy()
        self.video.pose=None;self.replay_clock(max(0,self.replay_frame-1))
        blocked=C.QSignalBlocker(self.progress);self.progress.setValue(max(0,self.replay_frame-1));del blocked
        return True
    def play(self):
        item=self.files.currentItem()
        if not item:return
        import cv2
        path=Path(item.data(C.Qt.UserRole));self.live();capture=cv2.VideoCapture(str(path))
        if not capture.isOpened():capture.release();return self.feedback('录像无法打开')
        self.replay=capture;self.replay_path=path;self.replay_frame=0;self.replay_start=time.monotonic()
        try:self.replay_report=json.loads((path.parent/'report.json').read_text(encoding='utf-8'))
        except (OSError,ValueError):self.replay_report={}
        self.replay_fps=capture.get(cv2.CAP_PROP_FPS) or 60
        self.replay_total=max(1,int(capture.get(cv2.CAP_PROP_FRAME_COUNT)))
        self.progress.setRange(0,self.replay_total-1);self.replay_controls.show();self.pause_btn.setText('暂停')
        self.read_replay_frame()
        self.video_title.setText('回放 · '+path.parent.name+' / '+path.name)
    def tick(self):
        while not self.events.empty():
            done,value,error=self.events.get()
            if error:b.log(error);self.statusBar().showMessage(error)
            elif done:done(value)
        if getattr(self,'recovering',False):
            seconds=int(time.monotonic()-self.recovery_started)
            self.recovery_text.setText(self.recovery_stage+f' · 已用 {seconds} 秒')
        if self.cloud_bridge and hasattr(self.cloud_bridge,'take_background_update'):
            update=self.cloud_bridge.take_background_update()
            if update:
                meta,content=update;image=G.QImage.fromData(content)
                if not image.isNull() and image.width()==meta['width'] and image.height()==meta['height']:
                    self.video.background=image
                    with b.LOCK:b.APPROVED_BACKGROUND=content
                    self.video.update();self.feedback('背景 v'+str(meta['background_version'])+' 已同步；取消“人物”可查看')
                else:b.log('背景图像解码校验失败，保留原背景')
        with b.LOCK:s=json.loads(json.dumps(b.STATE));data=b.PREVIEW;ident=b.PREVIEW_ID
        self.current=s;now=time.monotonic_ns();t=s.get('telemetry',{});fresh=t.get('pc_received_ns') and now-t['pc_received_ns']<2e9
        pose_channel=s.get('fast_pose') or t;p=pose_channel.get('pose')
        pose_age=(now-pose_channel['pc_received_ns']+pose_channel['board_monotonic_ns']-p['finished_ns']) if p and pose_channel.get('pc_received_ns') else float('inf')
        busy=s['phase'] in ('STARTING','RUNNING','STOPPING','FINALIZING');running=s['phase']=='RUNNING'
        preview_only=s.get('purpose')=='preview'
        finished=s['phase'] in ('DONE','ERROR')
        pose_ok=running and p and pose_age<5e8
        # Telemetry arrives every 500ms. Keep numeric metrics valid between polls;
        # the stricter 500ms limit remains solely for the live skeleton overlay.
        pose_metrics=running and p and pose_age<2e9
        mode_status=t.get('preprocess',{})
        mode_request=s.get('preprocess_request')
        mode_pending=bool(s.get('preprocess_sending') or mode_status.get('phase') in ('pending','awaiting_commit') or
            (mode_request and not (mode_status.get('request_id')==mode_request['request_id'] and mode_status.get('phase')=='applied')))
        self.mode.setEnabled(not busy or (running and bool(fresh) and mode_status.get('supported',False) and not mode_pending))
        if running:
            actual=mode_status.get('actual_mode',s.get('preprocess',0))
            self.mode_state.setText(('切换中 · 当前：' if mode_pending else '当前：')+MODES[actual])
            if not mode_pending and self.mode.currentIndex()!=actual:
                blocker=C.QSignalBlocker(self.mode);self.mode.setCurrentIndex(actual);del blocker
        recovering=getattr(self,'recovering',False) or getattr(self,'starting',False) or self.storage_busy or s.get('offline_busy',False)
        self.recover_btn.setEnabled(not busy and not recovering)
        self.sd_refresh_btn.setEnabled(not recovering and s['phase'] not in ('STARTING','STOPPING','FINALIZING'))
        self.sd_clean_btn.setEnabled(not busy and not recovering)
        self.log_manage_btn.setEnabled(not busy and not recovering)
        if self.tabs.currentWidget() is self.device_page and time.monotonic()>=self.next_sd_refresh and not recovering and s['phase'] not in ('STARTING','STOPPING','FINALIZING'):
            self.refresh_sd()
        self.duration.setEnabled(not busy);self.start_btn.setEnabled(not busy and not recovering and not self.closing);self.check_btn.setEnabled(not busy and not recovering);self.stop_btn.setEnabled(s['phase'] in ('STARTING','RUNNING'))
        self.preview_btn.setText('关闭预览' if busy and preview_only else '打开预览')
        self.preview_btn.setEnabled(not recovering and not self.closing and (not busy or (preview_only and running)))
        if preview_only and running:self.start_btn.setEnabled(not recovering and not self.closing);self.duration.setEnabled(True)
        version=s.get('preflight',{}).get('registers',{}).get('0x5c')
        supports_quality=version==0x4a505399
        self.compression_mode.setEnabled(not busy and supports_quality);self.jpeg_quality.setEnabled(not busy and supports_quality)
        self.target_mbps.setEnabled(not busy and supports_quality and self.compression_mode.currentIndex()==1)
        self.binary_threshold.setEnabled(not busy and not recovering)
        self.binary_value.setEnabled(not busy and not recovering and self.binary_threshold.isChecked())
        if running:
            advanced=mode_status.get('advanced_config')
            self.binary_state.setText(('已生效：阈值 '+str(advanced['advanced_threshold']) if advanced and advanced['advanced_mode']==2 else
                                       '已生效：二值化关闭') if fresh and advanced else '等待图像配置状态')
        elif busy:self.binary_state.setText('图像配置在本次测试中保持不变')
        else:self.binary_state.setText('下次测试生效；处理后的画面也会送入模型。')
        compression=t.get('compression',{})
        if running and fresh and compression:
            age=(t.get('board_monotonic_ns',0)-compression.get('host_ns',0))/1e9
            status={'within_band':'目标范围内','above_band':'偏高，调节中','below_band':'偏低，调节中','over_target_at_minimum':'最低质量仍超目标','below_target_at_maximum':'最高质量仍低于目标','settling':'调节中','fixed_quality':'固定质量'}.get(compression.get('feedback_status'),'')
            self.compression_state.setText((f"实际 Q{compression['actual_quality']} · JPEG {compression['jpeg_payload_mbps']:.1f} Mbps · {status}") if 0<=age<2 else '压缩数据更新延迟')
        elif busy:self.compression_state.setText('等待压缩状态')
        elif not supports_quality:self.compression_state.setText('当前FPGA：固定Q50')
        else:self.compression_state.setText('配置在下次开始测试时应用')
        if not running:
            self.connected.setText({'STARTING':'启动中','STOPPING':'停止中','FINALIZING':'保存中','DONE':'测试已结束','ERROR':'测试失败'}.get(s['phase'],'设备就绪' if s.get('preflight',{}).get('ready') else self.connected.text()))
        else:self.connected.setText('直播中' if fresh else '直播中 · 状态更新延迟')
        if s.get('offline_busy'):self.connected.setText('RK原片重新检测中')
        self.live_btn.setEnabled(bool(self.replay))
        self.bones.setEnabled(not self.replay);self.record_btn.setEnabled(not self.replay and not (busy and preview_only))
        self.record_btn.setText('录像：关' if busy and preview_only else '录像：开' if self.record_wanted else '录像：关')
        self.mark_btn.setEnabled(bool(running and not preview_only and not self.replay and s.get('latest_frame') is not None));self.action_choice.setEnabled(self.mark_btn.isEnabled());self.note.setEnabled(self.mark_btn.isEnabled())
        def fmt(v):return f'{v:.1f}' if isinstance(v,(int,float)) else '—'
        if time.monotonic()-self.rate_tick>=1:
            self.preview_rate=(self.preview_count-self.rate_count)/(time.monotonic()-self.rate_tick);self.rate_count=self.preview_count;self.rate_tick=time.monotonic()
        vals=dict(source=fmt(t.get('source_fps')) if running and fresh else '—',preview=fmt(self.preview_rate) if running else '—',pose=fmt(t.get('pose_fps')) if running and fresh else '—',latency=fmt(p.get('host_completion_to_result_ms')) if pose_metrics else '—',record=str(s.get('recorded_frames',0)))
        report=self.replay_report if self.replay else s.get('report',{})
        summary=report.get('remote',{}) if finished or self.replay else {}
        if self.replay:
            vals.update(source='—',preview='—',pose='—',latency='—',record='—')
            for movie in report.get('recordings',[]):
                if movie['name']==self.replay_path.name:vals['record']=str(movie['frames'])
        elif finished and report.get('recordings'):vals['record']=str(sum(m['frames'] for m in report['recordings']))
        if summary:
            vals['source']=fmt(summary.get('source_completion_fps',summary.get('video',{}).get('source_completion_fps')))
            frames=summary.get('pose',{}).get('frames',{});first=frames.get('first') or {};tail=frames.get('tail') or []
            if tail and first and frames.get('rows',0)>1:
                interval=(tail[-1]['finished_ns']-first['finished_ns'])/1e9
                if interval>0:vals['pose']=fmt((frames['rows']-1)/interval)
        self.metric_labels['source'].setText('采集 · 平均' if summary else '采集')
        self.metric_labels['pose'].setText('检测 · 平均' if summary else '检测')
        for key,value in vals.items():
            widget,unit=self.metrics[key];text=value+' '+unit
            if widget.text()!=text:widget.setText(text)
        regs=t.get('registers',{});active=regs.get('0xd0');mode=(active>>2)&3 if isinstance(active,int) else None
        if not mode_status:
            if running and fresh and mode is not None:self.mode_state.setText('已生效：'+MODES[mode])
            elif busy:self.mode_state.setText('等待生效确认')
            else:self.mode_state.setText('下次启动：'+MODES[self.mode.currentIndex()])
        elif not running:self.mode_state.setText('下次启动：'+MODES[self.mode.currentIndex()])
        scene,reason,tone=observation(s['phase'],p,pose_metrics,bool(self.replay))
        self.posture_hint.setText(self.posture_hints.update(s.get('session'),s['phase'],p,pose_metrics,bool(self.replay)))
        if preview_only and running and not self.replay:scene,reason,tone='仅预览','可调整机位、拍摄背景；未启动检测。','neutral'
        elif preview_only and s['phase']=='DONE' and not self.replay:scene,reason,tone='预览已关闭','背景已保留，可开始正式测试。','neutral'
        self.scene.setText(scene);self.reason.setText(reason);tint(self.scene,tone)
        elapsed=s.get('elapsed_s',0);details=dict(people=str(len(p['people'])) if pose_metrics and not self.replay else '—',npu=fmt(p.get('npu_ms'))+' ms' if pose_metrics and not self.replay else '—',pose_id=str(p['frame_id']) if pose_metrics and not self.replay else '—',cpu=fmt(t.get('cpu_percent'))+'% / '+fmt(t.get('memory_percent'))+'%' if fresh else '—',temperature=fmt(t.get('temperature_c'))+' ℃' if fresh else '—',bandwidth=fmt(s.get('wire_bytes',0)*8/elapsed/1e6)+' Mbps' if running and elapsed else '—',faults=f"{regs.get('0x1e0','—')} / {regs.get('0x1dc','—')}" if fresh else '—',disk=fmt(shutil.disk_usage(b.DATA).free/1024**3)+' GB')
        for k,v in details.items():self.info[k].setText(v)
        self.resource_state.setText('板端状态读取失败，请查看日志。' if running and t.get('telemetry_error') else '板端指标正在更新' if running and fresh else '板端指标更新延迟，请查看连接状态。' if running else '监护未运行；板端指标在开始后显示。')
        secs=int(elapsed);self.elapsed.setText(f'{secs//60:02}:{secs%60:02}'+('  录制中' if s.get('recording') else ''));self.frame_id.setText('帧 '+str(s.get('latest_frame','—')))
        if not self.replay:self.video_title.setText('相机 1 · 1080p · '+('直播' if running else '已结束 / 最后一帧' if finished else '等待开始'))
        if preview_only and running and not self.replay:self.video_title.setText('相机 1 · 仅预览')
        if 'alarm' in t:self.visible_alarm=t['alarm']
        alarm=self.visible_alarm;alarm_title,alarm_detail,alarm_tone,can_ack,can_resolve=incident(alarm,bool(fresh and 'alarm' in t),s.get('session'))
        active_alarm=bool(alarm and alarm.get('status')!='CLOSED')
        if self.replay and active_alarm:alarm_detail='这是实时未关闭事件；退出回放后核查并处理。'
        self.alarm_text.setText(alarm_title);self.alarm_detail.setText(alarm_detail);tint(self.alarm_panel,alarm_tone);tint(self.alarm_text,alarm_tone)
        operable=bool(s.get('session') and not self.replay and not getattr(self,'alarm_pending',False))
        if preview_only:operable=False
        self.ack.setEnabled(can_ack and operable);self.resolve.setEnabled(can_resolve and operable)
        badge=('实时告警待处理' if self.replay else '告警待处理') if active_alarm else scene
        self.state_badge.setText(badge);tint(self.state_badge,alarm_tone if active_alarm else tone)
        self.refresh_cloud()
        status=(s.get('error') or s['message'] or s.get('preflight',{}).get('reason')) if not busy else {'STARTING':'启动中','RUNNING':'直播中','STOPPING':'停止中，正在排空','FINALIZING':'保存录像与检测日志'}[s['phase']]
        self.statusBar().showMessage(self.notice if time.monotonic()<self.notice_until else status)
        logkey=json.dumps(s['logs'],ensure_ascii=False)
        if logkey!=self.log_key:self.log_key=logkey;self.logs.setPlainText('\n'.join(x['time']+'  '+x['message'] for x in s['logs']))
        if self.replay:
            import cv2
            target=int((time.monotonic()-self.replay_start)*self.replay_fps)
            if not self.replay_paused and not self.seeking and target>=self.replay_frame:
                while self.replay_frame<target:
                    if not self.replay.grab():break
                    self.replay_frame+=1
                self.read_replay_frame()
            self.frame_id.setText('录像帧 '+str(self.replay_frame));replay_secs=int(max(0,self.replay_frame-1)/self.replay_fps);self.elapsed.setText(f'{replay_secs//60:02}:{replay_secs%60:02}')
            self.video.pose=None
        else:
            if data and ident!=self.last_id:self.video.image=G.QImage.fromData(data);self.last_id=ident;self.preview_count+=1
            self.video.pose=p if pose_ok and self.bones.isChecked() and p['frame_id']<=self.last_id else None
        self.video.update()
        self.refresh_labels(self.replay_path.parent.name if self.replay_path else s.get('session'))
        if time.monotonic()>=self.next_file_scan:
            self.next_file_scan=time.monotonic()+3
            paths=[p for p in sorted(b.DATA.glob('field_*/*.mkv'),reverse=True) if (p.parent/'report.json').exists() or any(x['name']==p.name and x['session']==p.parent.name for x in s['recordings'])];key=tuple(str(p) for p in paths)
            if key!=self.file_key:
                self.file_key=key;self.files.clear()
                for path in paths:
                    item=W.QListWidgetItem(path.parent.name+' / '+path.name);item.setData(C.Qt.UserRole,str(path));self.files.addItem(item)
        if self.closing and not busy and not (b.THREAD and b.THREAD.is_alive()):self.timer.stop();self.close()
    def closeEvent(self,event):
        if getattr(self,'recovering',False):
            self.feedback('设备恢复正在进行，请等待完成后退出');event.ignore();return
        with b.LOCK:offline_busy=b.STATE.get('offline_busy')
        if offline_busy:self.feedback('RK离线复盘仍在运行，请等待完成后退出');event.ignore();return
        if b.THREAD and b.THREAD.is_alive():
            if not self.closing and W.QMessageBox.question(self,'停止测试','保存录像后退出？')!=W.QMessageBox.Yes:event.ignore();return
            if not self.closing:self.closing=True;self.work(b.request_stop)
            event.ignore();return
        if self.cloud_bridge and hasattr(self.cloud_bridge,'detach'):
            self.cloud_bridge.detach();self.cloud_bridge=None
        else:self.disconnect_cloud()
        self.live();event.accept()


if __name__=='__main__':
    app=W.QApplication(sys.argv);configure_app(app)
    socket_name='fpga_field_console_1392'
    activation=N.QLocalSocket();activation.connectToServer(socket_name)
    if activation.waitForConnected(1000):
        activation.write(b'SHOW');activation.waitForBytesWritten(1000);activation.disconnectFromServer()
        raise SystemExit(0)
    lock=C.QLockFile(str(b.ROOT/'qt_console.lock'));lock.setStaleLockTime(0)
    if not lock.tryLock(100):raise SystemExit('Console already running')
    N.QLocalServer.removeServer(socket_name)
    listener=N.QLocalServer()
    if not listener.listen(socket_name):raise SystemExit(listener.errorString())
    window=Window();window.show()
    if (b.ROOT/'cloud1694.local.json').is_file() and '--no-cloud' not in sys.argv and '--verify-layout' not in sys.argv:
        C.QTimer.singleShot(0,window.connect_cloud)
    def activate():
        while listener.hasPendingConnections():
            client=listener.nextPendingConnection();client.disconnectFromServer();client.deleteLater()
        window.showNormal();window.raise_();window.activateWindow()
    listener.newConnection.connect(activate)
    if '--verify-layout' in sys.argv:
        def verify():
            rows=[]
            for width,height in [(1000,700),(1240,820),(1600,900)]:
                window.resize(width,height);app.processEvents();clipped=[]
                for child in window.findChildren(W.QWidget):
                    if not child.isVisible():continue
                    pos=child.mapTo(window,C.QPoint(0,0));r=C.QRect(pos,child.size())
                    if not window.rect().adjusted(-1,-1,1,1).contains(r):clipped.append(child.metaObject().className())
                rows.append(dict(size=[width,height],actual=[window.width(),window.height()],clipped=clipped))
            (b.ROOT/'qt_layout1391.json').write_text(json.dumps(rows,indent=2));window.resize(1240,820);app.processEvents();window.grab().save(str(b.ROOT/'output/qt1391.png'))
        C.QTimer.singleShot(2000,verify)
    sys.exit(app.exec())
