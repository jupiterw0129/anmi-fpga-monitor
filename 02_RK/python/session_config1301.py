"""Read-only preflight for a bounded capture on the identified SD card."""
from pathlib import Path
import json,math,re,subprocess

ALARM_DB='/userdata/elderly_monitor1196/alarms.sqlite'
SD_UUID='0403-0201'
WIRE_BOUND=70*1024**3

def runtime_seconds(value):
    value=int(value)
    if not 20<=value<=7500:raise ValueError('Worker bound must be 20..7500 seconds')
    return value

def plan(name,frames,recordings):
    if not re.fullmatch(r'[A-Za-z0-9_]{1,64}',name):raise ValueError('Invalid session name')
    if not 2<=frames<=432000:raise ValueError('Frame target must be 2..432000')
    path=Path(recordings)
    if not path.is_absolute() or '..' in path.parts:raise ValueError('Recordings path must be absolute without parent traversal')
    return dict(name=name,frames=frames,recordings=str(path),alarm_db=ALARM_DB,
        nominal_capture_seconds=frames/60,worker_max_seconds=runtime_seconds(math.ceil(frames/60)+210),
        capture_timeout_seconds=math.ceil(frames/60)+30,
        evidence_reserve_bytes=1024**3,
        sd_reserve_bytes=2*1024**3,
        native_wire_bound_bytes=WIRE_BOUND,sd_uuid=SD_UUID)

def mount_info(parent):
    r=subprocess.run(['findmnt','-J','-T',str(parent),'-o','SOURCE,FSTYPE,UUID,OPTIONS,TARGET'],
        capture_output=True,text=True,check=True,timeout=5)
    rows=json.loads(r.stdout)['filesystems']
    if len(rows)!=1:raise ValueError('Ambiguous recording filesystem')
    return rows[0]

def available(path):
    import os
    s=os.statvfs(path)
    return s.f_bavail*s.f_frsize

def no_symlinks(path):
    if any(p.is_symlink() for p in (path,*path.parents)):raise ValueError('Symlinked session path')

def validate_directories(config,evidence_root,filesystem=mount_info,free=available):
    output=Path(evidence_root)/config['name'];recordings=Path(config['recordings'])
    no_symlinks(output);no_symlinks(recordings);no_symlinks(Path(config['alarm_db']))
    if not output.parent.is_dir() or not recordings.parent.is_dir():raise ValueError('Session parent must already exist')
    if output.exists() or recordings.exists():raise FileExistsError('Session or recordings directory already exists')
    card=filesystem(recordings.parent)
    if card.get('source')!='/dev/mmcblk1p1' or card.get('fstype')!='vfat' or card.get('uuid')!=SD_UUID:
        raise ValueError('Recordings parent is not the identified SD card')
    options=set(card['options'].split(','))
    if not {'rw','nosuid','nodev','noexec'}<=options:raise ValueError('Unexpected SD mount options')
    if free(output.parent)<config['evidence_reserve_bytes']:raise OSError('Insufficient evidence space')
    if free(recordings.parent)<config['sd_reserve_bytes']:raise OSError('Insufficient SD space')
    return dict(**config,output=str(output),recordings_mount=card,
        evidence_available_bytes=free(output.parent),sd_available_bytes=free(recordings.parent))
