"""Nonmodal physical-latency review, independent of the capture session."""
from pathlib import Path
from PySide6 import QtCore as C,QtGui as G,QtWidgets as W
from shiboken6 import isValid
from physical_latency1508 import load_video,frame_png,measure,export

class LatencyWindow(W.QDialog):
    def __init__(self,console):
        super().__init__(console);self.console=console;self.video=None;self.index=0;self.source=None;self.pairs=[];self.output=None;self.busy=False
        self.setWindowTitle('拍屏测延迟');self.resize(1040,780);self.setMinimumSize(820,650)
        layout=W.QVBoxLayout(self);layout.setContentsMargins(16,12,16,12);layout.setSpacing(10)
        top=W.QHBoxLayout();self.open_btn=W.QPushButton('导入手机录像');self.open_btn.clicked.connect(self.open);top.addWidget(self.open_btn)
        self.name=W.QLabel('同时拍到真实场景与HDMI画面');top.addWidget(self.name,1);layout.addLayout(top)
        self.image=W.QLabel('导入后，逐帧定位同一次变化');self.image.setAlignment(C.Qt.AlignCenter);self.image.setMinimumSize(320,180)
        self.image.setSizePolicy(W.QSizePolicy.Ignored,W.QSizePolicy.Expanding);layout.addWidget(self.image,1);self.pixmap=None
        nav=W.QHBoxLayout();self.prev=W.QPushButton('上一帧');self.next=W.QPushButton('下一帧')
        self.prev.clicked.connect(lambda:self.seek(self.index-1));self.next.clicked.connect(lambda:self.seek(self.index+1));nav.addWidget(self.prev);nav.addWidget(self.next)
        self.frame=W.QSpinBox();self.frame.setPrefix('帧 ');self.frame.setKeyboardTracking(False);self.frame.valueChanged.connect(self.seek);nav.addWidget(self.frame)
        self.time=W.QLabel('PTS —');nav.addWidget(self.time);nav.addStretch();layout.addLayout(nav)
        marks=W.QHBoxLayout();self.source_btn=W.QPushButton('标记源变化');self.result_btn=W.QPushButton('标记对应结果')
        self.source_btn.clicked.connect(self.mark_source);self.result_btn.clicked.connect(self.mark_result);marks.addWidget(self.source_btn);marks.addWidget(self.result_btn)
        self.mark=W.QLabel('选变化首次出现的帧；前一帧应尚未变化');self.mark.setWordWrap(True);marks.addWidget(self.mark,1);layout.addLayout(marks)
        self.table=W.QTableWidget(0,3);self.table.setHorizontalHeaderLabels(['源帧 → 结果帧','PTS差（ms）','采样区间（ms）'])
        self.table.horizontalHeader().setSectionResizeMode(W.QHeaderView.Stretch);self.table.setEditTriggers(W.QAbstractItemView.NoEditTriggers)
        self.table.setSelectionBehavior(W.QAbstractItemView.SelectRows);self.table.setMaximumHeight(125);layout.addWidget(self.table)
        row=W.QHBoxLayout();self.reviewer=W.QLineEdit();self.reviewer.setPlaceholderText('复核人');row.addWidget(self.reviewer)
        self.kind=W.QComboBox();self.kind.addItems(['视频通路','目标出现 → 正确识别']);row.addWidget(self.kind)
        self.remove=W.QPushButton('删除所选');self.remove.clicked.connect(self.remove_rows);row.addWidget(self.remove);layout.addLayout(row)
        self.setup=W.QLineEdit();self.setup.setPlaceholderText('拍摄布置：源画面、HDMI、手机模式；识别测量需确认框指向真实目标');layout.addWidget(self.setup)
        self.confirm=W.QCheckBox('同段实拍包含源与结果；已确认对应变化，未使用慢动作、插帧或变速视频');layout.addWidget(self.confirm)
        footer=W.QHBoxLayout();self.save=W.QPushButton('导出测量');self.save.setObjectName('Primary');self.save.clicked.connect(self.save_result);footer.addWidget(self.save)
        self.folder=W.QPushButton('打开结果');self.folder.clicked.connect(self.open_result);self.folder.setEnabled(False);footer.addWidget(self.folder)
        self.status=W.QLabel('按原始PTS计时；不使用平均帧率换算');self.status.setWordWrap(True);footer.addWidget(self.status,1);layout.addLayout(footer)
        self.controls=[self.prev,self.next,self.frame,self.source_btn,self.result_btn,self.remove,self.save]
        self.enabled()

    def enabled(self):
        for item in self.controls:item.setEnabled(self.video is not None and not self.busy)
        self.open_btn.setEnabled(not self.busy)

    def task(self,fn,done):
        self.busy=True;self.enabled()
        def run():
            try:return fn(),None
            except Exception as error:return None,str(error)
        def complete(value):
            if not isValid(self):return
            self.busy=False;self.enabled();result,error=value
            if error:self.status.setText(error)
            else:done(result)
        self.console.work(run,complete)

    def open(self):
        path,_=W.QFileDialog.getOpenFileName(self,'选择手机原视频','','视频 (*.mp4 *.mov *.mkv *.avi);;所有文件 (*)')
        if not path:return
        self.status.setText('读取原始帧时间戳并校验视频…')
        self.task(lambda:load_video(path),self.loaded)

    def loaded(self,video):
        self.video=video;self.source=None;self.pairs=[];self.table.setRowCount(0);self.confirm.setChecked(False);self.name.setText(Path(video['path']).name)
        self.output=None;self.folder.setEnabled(False)
        block=C.QSignalBlocker(self.frame);self.frame.setRange(0,len(video['pts'])-1);self.frame.setValue(0);del block
        self.seek(0)

    def seek(self,index):
        if self.busy or not self.video:return
        index=max(0,min(index,len(self.video['pts'])-1));self.status.setText('解码所选帧…')
        def shown(data):
            self.index=index;block=C.QSignalBlocker(self.frame);self.frame.setValue(index);del block
            from fractions import Fraction
            stamp=float(Fraction(self.video['time_base']))*(self.video['pts'][index]-self.video['pts'][0])
            self.time.setText(f'PTS {stamp:.6f} 秒');self.pixmap=G.QPixmap();self.pixmap.loadFromData(data,'PNG');self.resize_image();self.status.setText('帧号从0开始；标记首次变化帧')
        self.task(lambda:frame_png(self.video,index),shown)

    def resize_image(self):
        if self.pixmap:self.image.setPixmap(self.pixmap.scaled(self.image.size(),C.Qt.KeepAspectRatio,C.Qt.SmoothTransformation))

    def resizeEvent(self,event):
        super().resizeEvent(event)
        if hasattr(self,'pixmap'):self.resize_image()

    def mark_source(self):
        if self.index==0:self.status.setText('需要前一帧确认变化，请从帧1开始');return
        self.source=self.index;self.mark.setText(f'源变化帧 {self.source}；再定位对应结果首次出现帧')

    def mark_result(self):
        try:
            if self.source is None:raise ValueError('先标记源变化')
            value=measure(self.video,self.source,self.index)
            if any(p['source_frame']==self.source and p['result_frame']==self.index for p in self.pairs):raise ValueError('这组已记录')
            self.pairs.append(value);self.refresh();self.source=None;self.mark.setText('已记录；可继续标记下一次变化')
        except ValueError as error:self.status.setText(str(error))

    def refresh(self):
        self.table.setRowCount(len(self.pairs))
        for i,p in enumerate(self.pairs):
            for j,text in enumerate([f'{p["source_frame"]} → {p["result_frame"]}',f'{p["latency_ms"]:.3f}',f'[{p["sampling_lower_ms"]:.3f}, {p["sampling_upper_ms"]:.3f}]']):self.table.setItem(i,j,W.QTableWidgetItem(text))

    def remove_rows(self):
        for i in sorted({cell.row() for cell in self.table.selectedIndexes()},reverse=True):self.pairs.pop(i)
        self.refresh()

    def save_result(self):
        from server import DATA
        args=(self.video,list(self.pairs),self.reviewer.text(),('video_path','recognition')[self.kind.currentIndex()],self.setup.text(),self.confirm.isChecked(),DATA/'physical_latency')
        def saved(value):
            self.output,report=value;self.folder.setEnabled(True);self.status.setText(f'已导出{report["summary"]["count"]}次测量；中位{report["summary"]["median_ms"]:.2f}ms')
        self.task(lambda:export(*args),saved)

    def open_result(self):
        if self.output:
            import os
            os.startfile(self.output)
