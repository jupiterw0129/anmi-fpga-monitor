"""Read-only alarm polling with bounded nonblocking SQLite lock retries."""
import sqlite3,time
class AlarmPoll:
    def __init__(self,db,interval=.05,busy_limit=1.5):
        self.db=db;self.interval=interval;self.busy_limit=busy_limit;self.next_read=0
        self.busy_since=None;self.cached=None;self.known=False
        self.stats=dict(reads=0,busy_reads=0,recoveries=0,max_busy_s=0)
    def read(self,force=False):
        now=time.monotonic()
        if self.busy_since is not None and now-self.busy_since>self.busy_limit:
            raise TimeoutError('Alarm database continuously unreadable beyond retry bound')
        if not force and now<self.next_read:return self.cached
        self.next_read=now+self.interval;self.stats['reads']+=1
        try:row=self.db.execute("SELECT * FROM incidents WHERE status!='CLOSED'").fetchone()
        except sqlite3.OperationalError as e:
            if getattr(e,'sqlite_errorcode',0)&255 not in (sqlite3.SQLITE_BUSY,sqlite3.SQLITE_LOCKED):raise
            self.stats['busy_reads']+=1;self.known=False
            if self.busy_since is None:self.busy_since=now
            return self.cached
        if self.busy_since is not None:
            self.stats['recoveries']+=1;self.stats['max_busy_s']=max(self.stats['max_busy_s'],now-self.busy_since)
        self.busy_since=None;self.cached=row;self.known=True;return row
