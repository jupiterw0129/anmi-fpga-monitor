"""Append-only row evidence with constant in-memory retention.

One producer per journal. Iteration is for quiescent/final verification, not a
snapshot during append. A descriptor is successful only after fsync/close.
"""
from pathlib import Path
from collections import deque
import hashlib,json,os,stat

class RowJournal:
    def __init__(self,path,tail_rows=4):
        if not 1<=tail_rows<=64:raise ValueError('Invalid journal tail bound')
        self.path=Path(path);fd=os.open(self.path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
        if not stat.S_ISREG(os.fstat(fd).st_mode):os.close(fd);raise ValueError('Journal must be a new regular file')
        self.stream=os.fdopen(fd,'wb',buffering=128*1024);self.tail=deque(maxlen=tail_rows)
        self.first=None;self.count=0;self.bytes=0;self.hash=hashlib.sha256();self.closed=False;self.failed=False
    def append(self,row):
        if self.closed or self.failed:raise RuntimeError('Journal is closed or failed')
        payload=(json.dumps(row,sort_keys=True,separators=(',',':'),ensure_ascii=True)+'\n').encode()
        # Freeze retained row identity: callers may reuse their dictionaries.
        frozen=json.loads(payload)
        try:
            if self.stream.write(payload)!=len(payload):raise OSError('Short journal write')
        except BaseException:self.failed=True;raise
        self.hash.update(payload);self.bytes+=len(payload);self.count+=1
        if self.first is None:self.first=frozen
        self.tail.append(frozen)
    def __len__(self):return self.count
    def __getitem__(self,index):
        if not self.count:raise IndexError(index)
        if index==0:return self.first
        if index<0 and -index<=len(self.tail):return self.tail[index]
        raise IndexError('Only first and bounded tail rows are retained')
    def __iter__(self):
        if not self.closed:self.stream.flush()
        with self.path.open('rb') as f:
            for line in f:yield json.loads(line)
    def close(self):
        if self.closed:raise RuntimeError('Journal already closed')
        try:
            if self.failed:raise RuntimeError('Journal has a prior write error')
            self.stream.flush();os.fsync(self.stream.fileno())
            if os.fstat(self.stream.fileno()).st_size!=self.bytes:raise OSError('Journal size differs from admitted bytes')
        except BaseException:self.failed=True;raise
        finally:
            try:self.stream.close()
            except BaseException:self.failed=True;raise
            finally:self.closed=True
    def descriptor(self):
        return dict(schema=1295,path=str(self.path),rows=self.count,bytes=self.bytes,sha256=self.hash.hexdigest(),
                    fsync_complete=self.closed and not self.failed,tail=list(self.tail),first=self.first,tail_limit=self.tail.maxlen)

def journal_json(value):
    if isinstance(value,RowJournal):return value.descriptor()
    raise TypeError(type(value).__name__)
