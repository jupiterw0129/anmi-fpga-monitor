"""One PC owner for RK live capture or offline inference, released on process exit."""
from pathlib import Path
import os


def acquire(path=None):
    path=Path(path or Path(__file__).with_name('rk_resource1695.lock')).resolve()
    protected=Path('C:/Users/Jupiterw/OneDrive').resolve()
    if path==protected or protected in path.parents:raise ValueError('OneDrive目录受保护')
    file=path.open('a+b')
    try:
        file.seek(0,2)
        if file.tell()==0:file.write(b'0');file.flush()
        file.seek(0)
        if os.name=='nt':
            import msvcrt
            msvcrt.locking(file.fileno(),msvcrt.LK_NBLCK,1)
        else:
            import fcntl
            fcntl.flock(file,fcntl.LOCK_EX|fcntl.LOCK_NB)
        return file
    except OSError as error:
        file.close()
        raise ValueError('RK正被其他实时测试或离线复盘使用，请等待结束') from error
