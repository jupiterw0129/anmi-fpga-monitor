"""Preserve a failed controller's diagnostic when it never creates session.json."""
import json
from pathlib import Path


def read_log_tail(path, limit=4096):
    with Path(path).open('rb') as stream:
        stream.seek(0,2)
        stream.seek(max(0,stream.tell()-limit))
        return stream.read(limit).decode('utf-8',errors='replace')


def controller_failure(returncode, stderr, stdout):
    stderr=stderr[-4096:];stdout=stdout[-4096:]
    if 'Insufficient SD space' in stderr:
        reason='SD卡剩余空间不足，开始测试前至少需要2GiB可用空间；请先归档或清理SD录像。'
    elif 'Insufficient evidence space' in stderr:
        reason='板端证据存储空间不足，开始测试前至少需要1GiB可用空间；请在“日志→查看 / 清理”中清理板端历史日志。'
    else:
        reason=(stderr.strip() or stdout.strip() or '控制器未生成会话报告')[-1500:]
    return dict(returncode=returncode,reason=reason,stderr_tail=stderr,stdout_tail=stdout)


def startup_failure(stdout, stderr):
    for line in reversed(stdout.splitlines()):
        try:report=json.loads(line)
        except (ValueError,TypeError):continue
        if not isinstance(report,dict) or report.get('state')!='FAILED':continue
        diagnostic=report.get('controller_diagnostics') or {}
        reason=diagnostic.get('reason') or report.get('error')
        if reason:return str(reason)[-2000:]
    return stderr.strip()[-1500:] or '板端进程已退出，未返回错误详情；请查看本次会话日志。'


def failed_consumers(directory):
    failed=[]
    for name in ('sd','pose','video1008','overlay'):
        path=Path(directory)/name/'report.json'
        if not path.is_file():continue
        try:report=json.loads(path.read_text())
        except (ValueError,OSError):continue
        if isinstance(report,dict) and report.get('state')=='FAILED':
            failed.append(dict(component=name,error=str(report.get('error') or report.get('monitor_error') or '进程报告失败')))
    return failed


def consumer_failure_reason(failures):
    for failure in failures:
        if failure['component']=='sd':
            if 'queue overflow' in failure['error']:
                return 'SD录像写入跟不上当前视频载荷，队列已满；请降低JPEG质量或使用目标平均码率。失败日志与已有PC录像已保留。'
            return 'SD录像失败：'+failure['error'][-1500:]
    names={'pose':'RK姿态推理','video1008':'HDMI显示','overlay':'HDMI叠加'}
    first=failures[0]
    return names.get(first['component'],first['component'])+'失败：'+first['error'][-1500:]
