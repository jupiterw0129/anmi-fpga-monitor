"""Presentation of observations and persisted alarms; never creates an event."""


def observation(phase, pose, fresh, replay=False):
    if replay:
        return '录像回放', '当前播放历史原片，不代表实时检测结果。', 'neutral'
    if phase != 'RUNNING':
        return {
            'STARTING': ('正在启动', '等待采集与检测就绪。', 'neutral'),
            'STOPPING': ('正在停止', '正在排空帧并保存记录。', 'neutral'),
            'FINALIZING': ('正在保存', '等待录像封装和设备恢复。', 'neutral'),
            'DONE': ('监护已结束', '画面为最后一帧，可查看录像与记录。', 'neutral'),
            'ERROR': ('监护中断', '查看日志并检查设备后重新开始。', 'danger'),
        }.get(phase, ('尚未开始', '点击“开始测试”启动监护。', 'neutral'))
    if not fresh or not pose:
        return '检测更新延迟', '暂不能判断当前姿态，等待新检测结果。', 'warning'
    state = pose.get('fall_state', {}).get('state')
    views = {
        'UPRIGHT': ('正常直立', '已建立有效姿态观测。', 'normal'),
        'NORMAL': ('姿态正常', '当前未见疑似倒地候选。', 'normal'),
        'NO_PERSON': ('未见人体', '画面无人或模型暂未检出人体。', 'neutral'),
        'WAIT_BASELINE': ('正在建立基线', '请让完整人体进入画面并短暂站立。', 'neutral'),
        'POSTURE_CHANGED': ('姿态变化', '当前姿态发生变化，未达到跌倒条件。', 'neutral'),
        'CANDIDATE': ('疑似倒地 · 确认中', '正在累计持续时间，请关注人员状态。', 'warning'),
        'FALL_CANDIDATE': ('疑似倒地 · 确认中', '正在累计持续时间，请关注人员状态。', 'warning'),
        'SUSPECTED_FALL': ('疑似跌倒', '持续时间条件已满足，请查看人员情况。', 'danger'),
        'FALLEN': ('疑似跌倒', '请查看人员情况。', 'danger'),
        'RECOVERING': ('正在恢复', '检测到恢复姿态，正在持续确认。', 'warning'),
        'UNCERTAIN': ('暂无法判断', '关键点不完整或人体接近画面边缘。', 'warning'),
        'AMBIGUOUS': ('多人或目标不明确', '当前规则针对单人，暂不判断跌倒。', 'warning'),
    }
    title, detail, tone = views.get(state, ('暂无法判断', '当前观测不足，不能据此确认安全。', 'warning'))
    if pose.get('fall_state', {}).get('reason') == 'person_count_or_confidence':
        people = pose.get('people', [])
        if len(people) > 1:
            return views['AMBIGUOUS']
        if len(people) == 1:
            return '人体置信度不足', '当前人体输出不可靠，等待有效观测。', 'warning'
    return title, detail, tone


def incident(alarm, fresh, session=None):
    if not alarm or alarm.get('status') == 'CLOSED':
        return ('无待处理告警', '疑似事件触发后在此处理。', 'neutral', False, False) if fresh else (
            '本地告警待同步', '开始后读取，暂不能确认有无告警。', 'neutral', False, False)
    acknowledged = alarm.get('status') == 'ACKNOWLEDGED'
    title = ('已知晓 · 待处理' if acknowledged else '疑似跌倒 · 待确认') + f"  #{alarm['id']}"
    if not fresh:
        detail = '保留上次未关闭告警；当前状态尚未刷新。'
    elif alarm.get('manual_required') or alarm.get('opened_session') != session:
        detail = '该事件需人工核查，确认安全后再解除。'
    else:
        detail = '请查看人员情况；知晓告警不等于解除。'
    return title, detail, 'warning' if acknowledged else 'danger', not acknowledged, True
