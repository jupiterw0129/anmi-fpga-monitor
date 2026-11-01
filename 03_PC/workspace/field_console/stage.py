"""Stage isolated field controller, retaining the tested native/rollback bindings."""

from pathlib import Path

import ast, hashlib, json, subprocess, sys,time
from recovery_support import progress

from controller_quality1412 import augment
from preprocess_runtime1520 import augment as augment_preprocess
from alarm_pipeline1781 import augment_controller, sources as sd_sources
from threshold1786 import augment_controller as augment_threshold
from pose_pipeline1806 import augment_pose
from headless1797 import augment_controller as augment_headless
from preview_pipeline import augment_controller as augment_preview
from preview_transport import augment_controller as augment_transport
from source_fault_diagnostics import augment_controller as augment_source_fault
ROOT = Path(__file__).resolve().parent

ART = ROOT.parent/'artifacts'

N = '/userdata/native_required1138_20261028'

SSH = ['ssh.exe', '-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', 'rk3576']



def remote(code):

    r = subprocess.run(SSH+['python3', '-B', '-'], input=code, text=True, capture_output=True, timeout=25)

    r.check_returncode()

    return json.loads(r.stdout)



files = remote("from pathlib import Path\nimport json\nn=Path("+repr(N)+")\nprint(json.dumps({p:(n/p).read_text() for p in ('session_config1306.py','binding1332.json')}))")

config = files['session_config1306.py'].replace(N+'/stream1306_component/alarms.sqlite', N+'/field1382/alarms.sqlite')

(ROOT/'session_config_field1382.py').write_text(config, encoding='utf-8')

t = (ART/'control_component1332.py').read_text()

t = t.replace('from session_config1306 import', 'from session_config_field1382 import').replace("ROOT/'binding1332.json'", "ROOT/'binding_field1382.json'")

t = t.replace(N+'/stream1306_component/alarms.sqlite', N+'/field1382/alarms.sqlite')

t = t.replace('import read_diag902\n', 'import read_diag902\n            read_diag902.VERSION=0x4a505134\n')

old = "                notice=line(p,tick=observe_consumers);"

assert old in t

t = t.replace(old, "                if not quiescing and (ROOT/'field1382'/a.name/'stop_requested').exists():\n                    state['operator_stop']=True;request_stop1025(b,p,state);quiescing=True\n"+old)

t = t.replace("notice=='EARLY_STOP' and quiescing and state['consumer_exits']", "notice=='EARLY_STOP' and quiescing and (state['consumer_exits'] or state.get('operator_stop'))")

t = t.replace("n['committed']<a.frames and not state['consumer_exits']", "n['committed']<a.frames and not state['consumer_exits'] and not state.get('operator_stop')")

t = augment(t)

t = t.replace('from compression1412 import options,board_support,Observer', 'from compression1412 import options,board_support\nfrom compression1564 import Observer')
assert t.count('live_pose1301.py') == 1

t = t.replace('live_pose1301.py', 'live_pose1420.py')

t = augment_preprocess(t)
t = augment_controller(t)
t = augment_threshold(t)
t = t.replace('from compression1564 import Observer', 'from compression1564 import Observer\nfrom compression1608 import Observer as MetadataObserver')
t = t.replace('observer=Observer(shared,output,generation,compression)', 'observer=(MetadataObserver if version==0x4a505399 else Observer)(shared,output,generation,compression)')
t = t.replace('/userdata/quality1403_20261029/native/publish1403','/userdata/feedback1585_20261029/native/publish1585')
# Keep the longstanding five-field source timestamp journal ABI.
t = t.replace('frames.append(notice)', "frames.append(' '.join(notice.split()[:5]))")
t = augment_headless(t)
t = augment_preview(t)
t = augment_transport(t)
t = augment_source_fault(t)

(ROOT/'control_field1382.py').write_text(t, encoding='utf-8')

binding = json.loads(files['binding1332.json'])

pose_source = ART/'native_required1138_20261028/live_pose1301.py'

assert hashlib.sha256(pose_source.read_bytes()).hexdigest() == binding['files'][N+'/live_pose1301.py']

pose = pose_source.read_text(encoding='utf-8')

old_pose = "current=dict(generation=a.generation,session=a.session,observation=report['frames'][-1])"

assert pose.count(old_pose) == 1

pose = pose.replace(old_pose, "current=dict(generation=a.generation,session=a.session,observation=report['frames'][-1],observations=len(report['frames']))")

pose = augment_pose(pose)

(ROOT/'live_pose1420.py').write_text(pose, encoding='utf-8')

names = ('control_field1382.py', 'session_config_field1382.py','compression1412.py','rate_control1401.py','dqt1412.json','live_pose1420.py','pose_rate1420.py','wire_reader1428.py','wire_reader1432.py','wire_reader1551.py','compression1436.py','rate_control1436.py','dqt1436.json','rate_control1466.py','compression1466.py','rate_control1558.py','compression1558.py','compression1564.py','compression1585.py','rate_control1585.py','compression1592.py','rate_control1592.py','compression1597.py','rate_control1597.py','compression1608.py','rate_control1608.py','rate_control1605.py','dqt1564.json','live_preprocess1518.py','preprocess_runtime1520.py')
names += ('latest_decode1722.py','latest_decode1790.py')
names += ('pose_remedy1806.py','pose_fall1806.py')
names += sd_sources(ROOT)
names += ('threshold1786.py',)
names += ('field_failure1793.py',)
names += ('source_fault_diagnostics.py',)
quality = ART/'quality1399_20261029'

(ROOT/'rate_control1401.py').write_bytes((quality/'rate_control1401.py').read_bytes())

from rate_control1401 import dqt_signature

steps=ART/'quality_steps1423_20261029'

steps_report=json.loads((steps/'status.json').read_text())

assert steps_report['state']=='QUALITY1423_TEN_FINE_Q_SOF_CDC_DQT_DECODE_PASS'

for path,digest in steps_report['inputs'].items():

    assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest,path

signatures={}

for frame in steps_report['frames']:

    jpeg=(steps/f"frame_{frame['index']}.jpg").read_bytes()

    assert hashlib.sha256(jpeg).hexdigest()==frame['jpeg_sha256']

    signatures[dqt_signature(jpeg)]=frame['quality']

assert len(signatures)==10

(ROOT/'dqt1412.json').write_text(json.dumps(signatures))

fine_steps=ART/'quality_steps1435_20261029'

fine_report=json.loads((fine_steps/'status.json').read_text())

assert fine_report['state']=='QUALITY1435_66_Q_SOF_CDC_DQT_DECODE_PASS'

for path,digest in fine_report['inputs'].items():

    assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest,path

fine_signatures={}

for frame in fine_report['frames']:

    jpeg=(fine_steps/f"frame_{frame['index']}.jpg").read_bytes()

    assert hashlib.sha256(jpeg).hexdigest()==frame['jpeg_sha256']

    fine_signatures[dqt_signature(jpeg)]=frame['quality']

assert len(fine_signatures)==66

(ROOT/'dqt1436.json').write_text(json.dumps(fine_signatures))

low_steps=ART/'quality_low1562_20261029'
low_report=json.loads((low_steps/'status.json').read_text())
assert low_report['state']=='QUALITY1562_LOW_NINE_Q_TWO_SCENES_SOF_CDC_DQT_DECODE_PASS'
for path,digest in low_report['inputs'].items():
    assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest,path
expanded=dict(fine_signatures)
for frame in low_report['frames']:
    jpeg=(low_steps/f"frame_{frame['index']}.jpg").read_bytes()
    assert hashlib.sha256(jpeg).hexdigest()==frame['jpeg_sha256']
    signature=dqt_signature(jpeg)
    assert signature not in expanded or expanded[signature]==frame['quality']
    expanded[signature]=frame['quality']
assert len(expanded)==75 and set(expanded.values())==set(range(1,76))
(ROOT/'dqt1564.json').write_text(json.dumps(expanded))
for name in names:

    binding['files'][N+'/'+name] = hashlib.sha256((ROOT/name).read_bytes()).hexdigest()

(ROOT/'binding_field1382.json').write_text(json.dumps(binding, indent=2), encoding='utf-8')

candidate=remote("from pathlib import Path\nimport json\nprint((Path('/userdata/quality1403_20261029/binding1403.json')).read_text())")

quality_binding=dict(binding)

quality_binding['files']={**binding['files'],**candidate['files']}
quality_binding['files'].update(json.loads((ART/'feedback1585_20261029/build.json').read_text())['files'])
quality_binding['files'].update(json.loads((ROOT/'preview_transport_manifest.json').read_text())['files'])

quality_binding['ring_driver']=candidate['ring_driver'];quality_binding['ring_build_id']=candidate['ring_build_id']

(ROOT/'binding_quality1412.json').write_text(json.dumps(quality_binding,indent=2),encoding='utf-8')

# Validate the entire deployment before changing any board files. This path is
# also run before JTAG so a missing historical/source file cannot strand PCIe.
deploy_names=(*names,'binding_field1382.json','binding_quality1412.json',
              'field_remote.py','telemetry_remote.py','pose_remote.py','preview_remote.py')
for name in deploy_names:
    path=ROOT/name
    if name.endswith('.py'):ast.parse(path.read_text(encoding='utf-8'),filename=str(path))
assert "ap.add_argument('--preview-only'" in t, 'Preview-only support missing'
if '--check-only' in sys.argv:
    print('FIELD_STAGE_CHECK_PASS; board files unchanged',flush=True)
    raise SystemExit(0)

pending=N+'/field1382/deploy_'+str(time.time_ns())
remote("from pathlib import Path\nimport json\nPath("+repr(pending)+").mkdir(parents=True)\nprint('{}')")
entries=[]
wrappers=('field_remote.py','telemetry_remote.py','pose_remote.py','preview_remote.py')
for index,name in enumerate(dict.fromkeys(deploy_names)):
    if index%10==0:progress(84+int(10*index/len(deploy_names)),f'上传并校验板端程序 {index}/{len(deploy_names)}')
    subprocess.run(['scp.exe',str(ROOT/name),'rk3576:'+pending+'/'+name],check=True,timeout=20)
    entries.append(dict(name=name,destination=N+('/field1382/' if name in wrappers else '/')+name,
                        sha256=hashlib.sha256((ROOT/name).read_bytes()).hexdigest()))
# An interrupted upload leaves the installed program intact. Validate every
# uploaded file first, keep the previous installed bytes, install bindings last.
remote("from pathlib import Path\nimport ast,hashlib,json,os,shutil\nroot=Path("+repr(pending)+")\nentries="+repr(entries)+"\n"
       "for row in entries:\n p=root/row['name'];assert hashlib.sha256(p.read_bytes()).hexdigest()==row['sha256'],row['name']\n if p.suffix=='.py':ast.parse(p.read_text())\n"
       "backup=root/'previous';backup.mkdir()\n"
       "for row in entries:\n dest=Path(row['destination'])\n if dest.is_file():shutil.copyfile(dest,backup/row['name'])\n"
       "installed=[]\ntry:\n"
       " for row in sorted(entries,key=lambda r:r['name'].startswith('binding_')):\n  os.replace(root/row['name'],row['destination']);installed.append(row)\n"
       "except BaseException:\n"
       " for row in reversed(installed):\n  old=backup/row['name'];dest=Path(row['destination'])\n  if old.is_file():shutil.copyfile(old,dest)\n  else:dest.unlink()\n"
       " raise\n"
       "(root/'receipt.json').write_text(json.dumps(entries))\nprint('{}')")

print('FIELD1382_STAGED; no camera started')

