"""Nonmodal video review: human truth stays separate from live action markers."""
from pathlib import Path
from PySide6 import QtCore as C, QtWidgets as W
from shiboken6 import isValid
from evaluate_field1416 import export


class ReviewWindow(W.QDialog):
    def __init__(self, console, session):
        super().__init__(console)
        self.console, self.session = console, session
        self.setAttribute(C.Qt.WA_DeleteOnClose)
        self.setWindowTitle('养老动作复核 · '+Path(session['directory']).name)
        self.resize(780, 520);self.setMinimumSize(650, 470)
        layout = W.QVBoxLayout(self);layout.setContentsMargins(20,16,20,16);layout.setSpacing(12)
        hint = W.QLabel('先在主窗口回看完整会话，再标出每次跌倒的起点和允许告警截止时点。')
        hint.setWordWrap(True);layout.addWidget(hint)
        timing = W.QLabel('时间从首个源帧起算；可用回放当前帧定位。坐下、弯腰等正常动作不列为跌倒。')
        timing.setObjectName('Muted');timing.setWordWrap(True);layout.addWidget(timing)
        row = W.QHBoxLayout();row.setSpacing(10)
        self.onset, self.deadline = W.QDoubleSpinBox(), W.QDoubleSpinBox()
        for box in (self.onset, self.deadline):
            box.setDecimals(3);box.setRange(0,session['duration_s']);box.setSuffix(' 秒');box.setSingleStep(.1)
        row.addWidget(W.QLabel('起点'));row.addWidget(self.onset)
        self.onset_button = W.QPushButton('取当前帧');self.onset_button.clicked.connect(lambda:self.take_frame(self.onset));row.addWidget(self.onset_button)
        row.addSpacing(8);row.addWidget(W.QLabel('截止'));row.addWidget(self.deadline)
        self.deadline_button = W.QPushButton('取当前帧');self.deadline_button.clicked.connect(lambda:self.take_frame(self.deadline));row.addWidget(self.deadline_button)
        self.onset.setAccessibleName('跌倒起点秒');self.deadline.setAccessibleName('允许告警截止秒')
        layout.addLayout(row)
        self.events = W.QTableWidget(0, 2);self.events.setHorizontalHeaderLabels(['跌倒起点（秒）','允许告警截止（秒）'])
        self.events.horizontalHeader().setSectionResizeMode(W.QHeaderView.Stretch)
        self.events.verticalHeader().hide();self.events.setSelectionBehavior(W.QAbstractItemView.SelectRows)
        self.events.setEditTriggers(W.QAbstractItemView.NoEditTriggers);layout.addWidget(self.events,1)
        buttons = W.QHBoxLayout();self.add_button = W.QPushButton('添加跌倒事件');self.add_button.clicked.connect(self.add_event);buttons.addWidget(self.add_button)
        remove = W.QPushButton('删除所选');remove.clicked.connect(self.remove_event);buttons.addWidget(remove);buttons.addStretch();layout.addLayout(buttons)
        form = W.QHBoxLayout();form.addWidget(W.QLabel('复核人'));self.reviewer = W.QLineEdit();self.reviewer.setPlaceholderText('姓名或编号');self.reviewer.setMaxLength(80);form.addWidget(self.reviewer,1)
        self.split = W.QComboBox();self.split.addItems(['开发集','保留测试集']);self.split.setToolTip('只记录数据用途，不自动证明测试独立性');form.addWidget(self.split);layout.addLayout(form)
        self.reviewed = W.QCheckBox('已复核完整会话；除以上事件外，其余时段无跌倒')
        self.reviewed.setEnabled(session['video_coverage_complete']);layout.addWidget(self.reviewed)
        self.status = W.QLabel('未勾选完整复核时，只导出运行统计，不计算准确率。' if session['video_coverage_complete'] else 'PC录像未覆盖完整会话，只能导出运行统计。')
        self.status.setObjectName('Muted');self.status.setWordWrap(True);layout.addWidget(self.status)
        footer = W.QHBoxLayout();self.save_button = W.QPushButton('导出复核结果');self.save_button.setObjectName('Primary')
        self.save_button.clicked.connect(self.save);footer.addWidget(self.save_button)
        self.open_button = W.QPushButton('打开结果目录');self.open_button.setEnabled(False);self.open_button.clicked.connect(self.open_result);footer.addWidget(self.open_button);footer.addStretch()
        close = W.QPushButton('关闭');close.clicked.connect(self.close);footer.addWidget(close);layout.addLayout(footer)
        self.result_path = None

    def take_frame(self, box):
        console = self.console
        if not console.replay or not console.replay_path or console.replay_path.parent.resolve() != Path(self.session['directory']):
            self.status.setText('请在主窗口播放本会话的录像，再定位当前帧。');return
        clip = next((c for c in self.session['recordings'] if c['name'] == console.replay_path.name), None)
        if not clip:
            self.status.setText('当前录像未在复核清单中。');return
        index = max(0, min(console.replay_frame-1, len(clip['frames'])-1))
        box.setValue(self.session['times'][clip['frames'][index]])

    def add_event(self):
        onset, deadline = self.onset.value(), self.deadline.value()
        if deadline < onset:
            self.status.setText('截止时点应在起点之后。');return
        row = self.events.rowCount();self.events.insertRow(row)
        self.events.setItem(row,0,W.QTableWidgetItem(f'{onset:.3f}'));self.events.setItem(row,1,W.QTableWidgetItem(f'{deadline:.3f}'))
        self.status.setText('已添加。导出时会检查重复和重叠区间。')

    def remove_event(self):
        for row in sorted({i.row() for i in self.events.selectedIndexes()}, reverse=True):
            self.events.removeRow(row)

    def annotation(self):
        events = [dict(onset_s=float(self.events.item(row,0).text()),deadline_s=float(self.events.item(row,1).text()))
                  for row in range(self.events.rowCount())]
        for event in events:
            for key in ('onset_s','deadline_s'):
                event[key]=min(event[key],self.session['duration_s'])
        return dict(schema_version=1,bindings=self.session['bindings'],reviewed=self.reviewed.isChecked(),
                    reviewer=self.reviewer.text().strip(),label_origin='manual_video_review',
                    split='held_out' if self.split.currentIndex() else 'development',events=sorted(events,key=lambda e:e['onset_s']))

    def save(self):
        annotation = self.annotation();self.save_button.setEnabled(False);self.status.setText('正在校验输入并导出…')
        def done(value):
            if not isValid(self):return
            self.result_path, result = value;self.open_button.setEnabled(True);self.save_button.setEnabled(True)
            if result['metrics']:
                detector, alarm = result['metrics']['detector'], result['metrics']['alarm']
                self.status.setText(f"姿态事件：命中 {detector['tp']} / 误报 {detector['fp']} / 漏报 {detector['fn']}；新增告警：命中 {alarm['tp']} / 误报 {alarm['fp']} / 漏报 {alarm['fn']}。")
            else:self.status.setText('已导出运行统计；尚未完成人工复核，准确率不计算。')
        # Keep video playback responsive while hashing recordings.
        def task():
            try:return export(self.session,annotation)
            except Exception as error:
                self.console.events.put((lambda _,message=str(error):self.failed(message),None,None))
                return None
        def completed(value):
            if value is not None:done(value)
        self.console.work(task, completed)

    def failed(self, message):
        if not isValid(self):return
        self.save_button.setEnabled(True);self.status.setText('导出失败：'+message)

    def open_result(self):
        if self.result_path:
            import os
            os.startfile(self.result_path)
