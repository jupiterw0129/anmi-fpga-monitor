"""Bind cold-start recovery to the hash-verified, live-switch concurrently tested SRAM image."""
from pathlib import Path
import hashlib
import json

VERSION = 0x4a505399
CAPABILITIES = {0x4a505134: 15, VERSION: 31}


def evidence_path(value):
    path=Path(value)
    # Recording folders are routinely archived or cleaned. Keep the original
    # accepted evidence bytes with the program; callers still check the hashes
    # pinned in the original acceptance reports before allowing any download.
    try:relative=path.relative_to(Path('E:/FPGA_field_tests'))
    except ValueError:return path
    cached=Path(__file__).resolve().parent/'recovery_evidence'/relative
    return cached if cached.is_file() else path


def verified_1497(root):
    root = Path(root)
    evidence = json.loads((root/'verification1414.json').read_text())
    assert evidence['state'] == 'FIELD1414_TARGET_AND_Q75_FULL_PREVIEW_RECORD_NPU_HDMI_SD_SHORT_PASS'
    assert len(evidence['trials']) == 2
    for trial in evidence['trials']:
        report = evidence_path(trial['report'])
        assert hashlib.sha256(report.read_bytes()).hexdigest() == trial['report_sha256'], str(report)
        result = json.loads(report.read_text())
        assert result['state'] == 'FIELD_PC_SESSION_PASS'
    acceptance_path = root.parent/'artifacts/i2c_route1497_20261029/acceptance1505.json'
    acceptance = json.loads(acceptance_path.read_text())
    assert acceptance['state'] == 'I2C1505_SRAM_FIXED_Q50_AND_TARGET36_CONCURRENT_ACCEPTANCE_PASS'
    assert {trial['mode'] for trial in acceptance['trials']} == {'quality', 'target'}
    for trial in acceptance['trials']:
        for key in ('verification', 'report'):
            path = evidence_path(trial[key])
            assert hashlib.sha256(path.read_bytes()).hexdigest() == trial[key+'_sha256'], str(path)
        assert trial['source_frames'] == 1801 and trial['source_fps'] >= 59.5
        assert trial['pose_frames'] >= 200 and trial['video_coverage_complete']
    manifest = root.parent/'artifacts/i2c_route1497_20261029/deployment1499/status.json'
    assert str(manifest) == acceptance['candidate_manifest']
    assert hashlib.sha256(manifest.read_bytes()).hexdigest() == acceptance['candidate_manifest_sha256']
    deployment = json.loads(manifest.read_text())
    assert deployment['state'] == 'I2C1499_TIMING_CHECKED_SRAM_CANDIDATE_READY'
    assert deployment['sha256'] == acceptance['candidate_bit_sha256']
    bit = Path(deployment['bit'])
    assert bit.stat().st_size == deployment['bytes']
    assert hashlib.sha256(bit.read_bytes()).hexdigest() == deployment['sha256'], str(bit)
    return manifest


def verified_release(root):
    root=Path(root)
    verified_1497(root)  # Preserve the independently tested rollback evidence.
    acceptance_path=root.parent/'artifacts/live_preprocess1512_20261029/acceptance1553.json'
    acceptance=json.loads(acceptance_path.read_text())
    assert acceptance['state']=='LIVE1553_FIXED_Q50_TARGET36_ALL_DIRECTED_SWITCHES_CONCURRENT_SHORT_ACCEPTANCE_PASS'
    assert not acceptance['two_hour_started'] and not acceptance['flash_written']
    assert len(acceptance['trials'])==2
    assert {(v['mode'],v['seconds'],v['transitions']) for v in acceptance['trials']}=={('quality',30,4),('target',180,12)}
    for p,h in acceptance['inputs'].items():
        assert hashlib.sha256(evidence_path(p).read_bytes()).hexdigest()==h,p
    for trial in acceptance['trials']:
        assert trial['frames']==trial['seconds']*60+1 and trial['source_fps']>=59.5
        assert trial['pose_fps']>=8
        assert json.loads(evidence_path(trial['report']).read_text())['state']=='FIELD_PC_SESSION_PASS'
    manifest=root.parent/'artifacts/live_preprocess1512_20261029/deployment1541/status.json'
    assert str(manifest)==acceptance['candidate_manifest']
    assert hashlib.sha256(manifest.read_bytes()).hexdigest()==acceptance['candidate_manifest_sha256']
    deployment=json.loads(manifest.read_text())
    assert deployment['state']=='LIVE1541_TIMING_CHECKED_SRAM_CANDIDATE_READY'
    assert deployment['sha256']==acceptance['candidate_bit_sha256']
    bit=Path(deployment['bit'])
    assert bit.stat().st_size==deployment['bytes'] and hashlib.sha256(bit.read_bytes()).hexdigest()==deployment['sha256']
    return manifest


def recovery_source(filename, code):
    """Keep original ownership, device-ID, hash, and no-Flash gates intact."""
    if filename == 'program_sram1371.py':
        # Validate the exact accepted candidate before preparing a download.
        verified_release(Path(__file__).resolve().parent)
        replacements = {
            "ART/'deployment1144_20261028/status.json'": "ART/'live_preprocess1512_20261029/deployment1541/status.json'",
            'DIAGNOSTIC1144_BIT_READY_FOR_OWNERSHIP_AND_TARGET_GATED_SRAM': 'LIVE1541_TIMING_CHECKED_SRAM_CANDIDATE_READY',
            "ART/'board_crop727_20261025/imx415_p4r2_727_UNVALIDATED.bit'": "ART/'i2c_route1497_20261029/deployment1499/imx415_i2c1497_SRAM_CANDIDATE.bit'",
            'f4889a4a9072e5850c38fbf4103d766dc189dcacfc3fc4ec991f48611786feda': 'f53d8c9ad0051817d4763992cb67792094cb6863aec22813bb2af94fa4c7c691',
        }
    elif filename == 'recover_endpoint1372.py':
        replacements = {'0x4a505134': '0x4a505399', "values['0x1c8']==15": "values['0x1c8']==31"}
    elif filename == 'restore_driver1373.py':
        replacements = {'0x4a505134': '0x4a505399', "'0x1c8':15": "'0x1c8':31"}
    else:
        raise ValueError(filename)
    for before, after in replacements.items():
        assert code.count(before) == 1, (filename, before)
        code = code.replace(before, after)
    return code
