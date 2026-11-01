"""Persistent alarm state is authoritative even while pose observations stop."""
from pathlib import Path
import copy,sqlite3
import cv2
from overlay1184 import render

class AlarmReader:
    def __init__(self,path):
        path=Path(path)
        if not path.is_absolute() or path.is_symlink() or not path.is_file():raise ValueError('Existing absolute alarm database required')
        self.db=sqlite3.connect(path.as_uri()+'?mode=ro',uri=True,timeout=.01)
        self.db.row_factory=sqlite3.Row
        self.db.execute('PRAGMA query_only=ON')
        self.last=None;self.known=False
    def read(self):
        try:
            row=self.db.execute("SELECT * FROM incidents WHERE status!='CLOSED'").fetchone()
            self.last=dict(row) if row else None;self.known=True
            return dict(known=True,alarm=self.last,error=None)
        except sqlite3.Error as e:
            return dict(known=False,alarm=copy.deepcopy(self.last),error=repr(e),previously_known=self.known)
    def close(self):self.db.close()

def render_current(result,generation,session,now_ns,db_status):
    # Never use an old AI result's alarm when the DB has since ACKed/resolved it.
    observation=copy.deepcopy(result)
    if observation is not None:observation['observation']['fall_state']['alarm']=None
    image,meta=render(observation,generation,session,now_ns)
    active=db_status['alarm'];meta.update(alarm=copy.deepcopy(active),alarm_database_known=db_status['known'],alarm_database_error=db_status['error'])
    if active is not None:
        cv2.rectangle(image,(0,478),(959,539),(0,0,210,255),-1)
        cv2.putText(image,f"FALL ALERT #{active['id']} {active['status']} - CHECK PERSON",(12,503),cv2.FONT_HERSHEY_SIMPLEX,.65,(255,255,255,255),2,cv2.LINE_8)
        if active.get('manual_required') or active.get('opened_session')!=session:
            cv2.putText(image,'MANUAL VERIFICATION REQUIRED',(12,529),cv2.FONT_HERSHEY_SIMPLEX,.55,(255,255,255,255),1,cv2.LINE_8)
    if not db_status['known']:
        cv2.rectangle(image,(0,78),(959,110),(0,100,180,255),-1)
        cv2.putText(image,'ALARM DATABASE UNAVAILABLE - CHECK DEVICE',(12,102),cv2.FONT_HERSHEY_SIMPLEX,.55,(255,255,255,255),1,cv2.LINE_8)
    return image,meta
