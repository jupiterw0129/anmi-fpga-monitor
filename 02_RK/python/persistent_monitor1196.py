"""One durable incident database across capture sessions; never migrate silently."""
from pathlib import Path
import time
from alarm723 import AlarmStore
from scene741 import FallScene

def open_monitor(path,session):
    path=Path(path)
    if not path.is_absolute() or path.is_symlink():raise ValueError('Absolute nonsymlink alarm database required')
    path.parent.mkdir(parents=True,exist_ok=True)
    store=AlarmStore(path)
    try:
        if store.db.execute('PRAGMA integrity_check').fetchone()[0]!='ok':raise RuntimeError('Persistent alarm database integrity failed')
        prior=store.active()
        transition=store.apply('HOLD',session,time.monotonic(),'Monitoring session starting; prior incident needs manual verification')
        startup=dict(database=str(path),prior_alarm=prior,hold_transition=transition,active_alarm=store.active())
        return store,FallScene(store,session),startup
    except BaseException:store.close();raise
