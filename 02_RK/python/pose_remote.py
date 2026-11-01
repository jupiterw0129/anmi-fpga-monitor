"""Read-only latest-pose channel, independent of 500ms device telemetry."""
import argparse,json,time
from pathlib import Path

def main():
    import re
    parser=argparse.ArgumentParser();parser.add_argument('--name',required=True);a=parser.parse_args()
    assert re.fullmatch(r'field_[0-9_]+',a.name)
    base=Path('/userdata/native_required1138_20261028')
    path=base/'evidence'/a.name/'pose/latest1184.json'
    report=base/'field1382'/a.name/'report.json'
    previous=None
    deadline=time.monotonic()+7800
    while time.monotonic()<deadline:
        try:
            observation=json.loads(path.read_text())['observation']
            key=observation['frame_id']
            if key!=previous:
                print(json.dumps(dict(pose=observation,board_monotonic_ns=time.monotonic_ns())),flush=True)
                previous=key
        except FileNotFoundError:pass
        if report.exists():break
        time.sleep(.02)

if __name__=='__main__':main()
