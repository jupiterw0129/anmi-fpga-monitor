"""Owned event-only circular storage and interrupted-write quarantine.

The recording worker holds this lock for its lifetime. Quota reclamation only
removes complete, hash-verified, unpinned events bearing this store's token.
Interrupted output is preserved; quarantine is not video-data recovery.
"""
from pathlib import Path
import fcntl,hashlib,json,os,re,shutil,time,uuid

class CircularStore:
    overhead=65536
    event_re=re.compile(r'event_[0-9a-f]{32}')
    allowed={'store_owner.json','video.mkv','video.mkv.partial','manifest.json','event.json','.keep'}

    def __init__(self,root,quota_bytes=24*1024**3,reserve_bytes=256*1024**2):
        if quota_bytes<=self.overhead or reserve_bytes<0:raise ValueError('Invalid storage limits')
        raw=Path(root)
        if any(p.is_symlink() for p in (raw,*raw.parents)):raise ValueError('Symlinked store path')
        raw.mkdir(exist_ok=True);self.root=raw.resolve();self.quota=quota_bytes;self.reserve=reserve_bytes
        marker=self.root/'store.json'
        if not marker.exists():
            if any(self.root.iterdir()):raise ValueError('Refuse to adopt a nonempty unowned directory')
            self._json(marker,dict(schema=1053,token=uuid.uuid4().hex))
        self.owner=json.loads(marker.read_text())
        if self.owner.get('schema')!=1053 or not re.fullmatch('[0-9a-f]{32}',self.owner.get('token','')):raise ValueError('Invalid store owner')
        self.lock=os.open(self.root/'store.lock',os.O_RDWR|os.O_CREAT|os.O_NOFOLLOW,0o600)
        try:fcntl.flock(self.lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BaseException:os.close(self.lock);self.lock=None;raise
        self.evicted=[];self.recovered=[]

    @staticmethod
    def _sync(directory):
        fd=os.open(directory,os.O_RDONLY|os.O_DIRECTORY)
        try:os.fsync(fd)
        finally:os.close(fd)

    @classmethod
    def _json(cls,path,value):
        with path.open('x') as f:json.dump(value,f,indent=2);f.flush();os.fsync(f.fileno())
        cls._sync(path.parent)

    def register(self,directory):
        p=Path(directory)
        if p.is_symlink() or p.parent.resolve()!=self.root or not self.event_re.fullmatch(p.name) or not p.is_dir():raise ValueError('Invalid event directory')
        self._json(p/'store_owner.json',dict(**self.owner,created_unix_ns=time.time_ns()))

    def _owned(self,p):
        if p.is_symlink() or not p.is_dir():return False
        marker=p/'store_owner.json'
        if not marker.is_file() or marker.is_symlink():return False
        value=json.loads(marker.read_text())
        return value.get('schema')==1053 and value.get('token')==self.owner['token']

    def _files(self,p):
        files=list(p.iterdir())
        if any(x.is_symlink() or not x.is_file() or x.name not in self.allowed for x in files):raise ValueError('Unrecognized event content: '+str(p))
        return files

    def _complete(self,p,verify_hash=False):
        if not self._owned(p):return False
        files=self._files(p);names={x.name for x in files}
        if not {'video.mkv','manifest.json','event.json'}<=names or 'video.mkv.partial' in names:return False
        m=json.loads((p/'manifest.json').read_text());e=json.loads((p/'event.json').read_text())
        if m.get('state')!='JPEG_CLIP809_FINALIZED' or e.get('state')!='EVENT837_FINALIZED':return False
        if not m.get('frames') or m.get('container_bytes')!=(p/'video.mkv').stat().st_size or m.get('container_sha256')!=e.get('container_sha256'):return False
        if verify_hash:
            h=hashlib.sha256()
            with (p/'video.mkv').open('rb') as f:
                while block:=f.read(1024*1024):h.update(block)
            if h.hexdigest()!=m['container_sha256']:raise ValueError('Event media hash mismatch: '+str(p))
        return True

    def recover(self):
        # Preserve incomplete events from the previous worker. Never manufacture
        # an EOS, a manifest or a successful event after abrupt termination.
        for p in sorted(self.root.iterdir()):
            if self.event_re.fullmatch(p.name) and self._owned(p):
                if self._complete(p,verify_hash=True):continue
                self._files(p)
                target=self.root/('incomplete_'+p.name[6:]);p.rename(target);self._sync(self.root)
                self.recovered.append(dict(original=p.name,preserved=target.name))
            elif p.name.startswith('trash_') and self._owned(p):
                self._remove_files(p)
            elif re.fullmatch(r'trash_[0-9a-f]{32}',p.name) and p.is_dir() and not p.is_symlink() and not any(p.iterdir()):
                # The owner can already have been unlinked when power/process
                # loss occurs between the final unlink and rmdir.
                p.rmdir();self._sync(self.root)
        return list(self.recovered)

    def _usage(self):
        used=0
        for base,dirs,files in os.walk(self.root,followlinks=False):
            for name in dirs+files:
                p=Path(base)/name
                if p.is_symlink():raise ValueError('Symlink inside managed store')
                if p.is_file():used+=p.stat().st_size
        return used

    def _remove_files(self,p):
        if not self._owned(p) or (p/'.keep').exists():raise ValueError('Unowned or pinned event')
        files=self._files(p)
        # A trash rename records the deletion decision durably. Remove the owner
        # last so interrupted cleanup can be recognized on the next startup.
        files.sort(key=lambda x:x.name=='store_owner.json')
        for f in files:f.unlink()
        p.rmdir();self._sync(self.root)

    def ensure_space(self,additional,pending=0,active=None):
        if min(additional,pending)<0:raise ValueError('Negative reservation')
        active=Path(active).resolve() if active is not None else None
        while self._usage()+pending+additional+self.overhead>self.quota or shutil.disk_usage(self.root).free<pending+additional+self.reserve+self.overhead:
            candidates=[]
            for p in self.root.iterdir():
                if self.event_re.fullmatch(p.name) and p.resolve()!=active and not (p/'.keep').exists() and self._complete(p):
                    created=json.loads((p/'store_owner.json').read_text())['created_unix_ns']
                    candidates.append((created,p.name,p))
            if not candidates:raise OSError('Storage full; no complete unpinned event can be reclaimed')
            _,_,victim=min(candidates)
            assert self._complete(victim,verify_hash=True)
            size=sum(p.stat().st_size for p in self._files(victim))
            target=self.root/('trash_'+victim.name[6:]);victim.rename(target);self._sync(self.root)
            self._remove_files(target);self.evicted.append(dict(event=victim.name,bytes=size))
        return dict(used_bytes=self._usage(),evicted=list(self.evicted))

    def close(self):
        if self.lock is not None:os.close(self.lock);self.lock=None
