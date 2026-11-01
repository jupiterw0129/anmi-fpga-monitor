import hashlib
import json
import mmap
import os
import struct
import subprocess
import time
from pathlib import Path


DEVICE = Path('/sys/bus/pci/devices/0000:21:00.0')
DMA = Path('/root/deploy/sgdma_drv/anlogic_pci.ko')
VIDEO = Path('/root/deploy/v4l2_drv/milianke_v4l2.ko')
DMA_ID = '4221bd3dd1b4a7d4453578b2a222b548bd7de16d'
HASHES = {DMA: '58a6984dc7a9476c08c335875d46beca8ed8ff02a12ce4c54925758149f7d353',
          VIDEO: '1812e647f321b61db1a4d31c45901112daa556f995d95ee6a7e3ebae0bfe664e'}


def run(arguments):
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=15)
    print(json.dumps(dict(command=arguments, returncode=result.returncode,
                          stdout=result.stdout, stderr=result.stderr)), flush=True)
    result.check_returncode()


def parameters(module):
    return {path.name: path.read_text().strip() for path in
            Path('/sys/module', module, 'parameters').glob('*')}


def module_id():
    note = Path('/sys/module/anlogic_pci/notes/.note.gnu.build-id').read_bytes()
    names, size, kind = struct.unpack_from('<III', note)
    if kind != 3 or size != 20:
        raise RuntimeError('Unexpected build ID note')
    offset = 12 + ((names + 3) & ~3)
    return note[offset:offset + size].hex()


def validate_reset(vendor, device, command, bars):
    if (vendor, device) != ('0x1edb', '0xabcd'):
        raise RuntimeError('Unexpected endpoint')
    if command != 0 or bars != (0, 0):
        raise RuntimeError('Not the observed SRAM reset configuration')


def registers():
    descriptor = os.open(DEVICE / 'resource0', os.O_RDONLY | os.O_SYNC)
    try:
        with mmap.mmap(descriptor, 4096, access=mmap.ACCESS_READ) as memory:
            return {hex(offset): struct.unpack_from('<I', memory, offset)[0]
                    for offset in (0x5c, 0x60, 0x84, 0x90, 0xa4, 0xd4, 0xd8, 0xfc)}
    finally:
        os.close(descriptor)


def main():
    descriptor = os.open(DEVICE / 'config', os.O_RDONLY)
    try:
        command = struct.unpack('<H', os.pread(descriptor, 2, 4))[0]
        bars = struct.unpack('<II', os.pread(descriptor, 8, 16))
    finally:
        os.close(descriptor)
    validate_reset(DEVICE.joinpath('vendor').read_text().strip(),
                   DEVICE.joinpath('device').read_text().strip(), command, bars)
    if module_id() != DMA_ID:
        raise RuntimeError('Unexpected loaded DMA driver')
    if any(hashlib.sha256(path.read_bytes()).hexdigest() != digest
           for path, digest in HASHES.items()):
        raise RuntimeError('Driver restoration SHA mismatch')
    paths = [str(path) for pattern in ('ANLOGIC-PCI0_*', 'video*') for path in Path('/dev').glob(pattern)]
    if not paths:
        raise RuntimeError('No known board devices')
    held = subprocess.run(['fuser', *paths], capture_output=True, text=True, timeout=5)
    if held.returncode != 1 or held.stdout.strip():
        raise RuntimeError('Devices occupied or fuser failed')
    before = registers()
    if any(value != 0xffffffff for value in before.values()):
        raise RuntimeError('Not the observed stale all-ones BAR state')
    dma_parameters = parameters('anlogic_pci')
    video_loaded = Path('/sys/module/milianke_v4l2').exists()
    video_parameters = parameters('milianke_v4l2')
    print(json.dumps(dict(stage='JPEG727_PREFLIGHT_PASSED', command=command, bars=bars,
                          registers=before, dma_parameters=dma_parameters,
                          video_loaded=video_loaded, video_parameters=video_parameters)), flush=True)
    try:
        if video_loaded:
            run(['rmmod', 'milianke_v4l2'])
        run(['rmmod', 'anlogic_pci'])
        DEVICE.joinpath('remove').write_text('1')
        Path('/sys/bus/pci/rescan').write_text('1')
        time.sleep(1)
        if (DEVICE.joinpath('vendor').read_text().strip(), DEVICE.joinpath('device').read_text().strip()) != ('0x1edb', '0xabcd'):
            raise RuntimeError('Expected endpoint did not return')
    finally:
        if not Path('/sys/module/anlogic_pci').exists():
            run(['insmod', str(DMA)] + [f'{name}={value}' for name, value in dma_parameters.items()])
        if module_id() != DMA_ID or parameters('anlogic_pci') != dma_parameters:
            raise RuntimeError('Original DMA driver restoration mismatch')
        if video_loaded and not Path('/sys/module/milianke_v4l2').exists():
            run(['insmod', str(VIDEO)] + [f'{name}={value}' for name, value in video_parameters.items()])
        if Path('/sys/module/milianke_v4l2').exists() != video_loaded or parameters('milianke_v4l2') != video_parameters:
            raise RuntimeError('Original video driver restoration mismatch')
    deadline = time.monotonic() + 5
    after = registers()
    while after['0x84'] & 9 != 1 and time.monotonic() < deadline:
        time.sleep(0.1)
        after = registers()
    if after['0x5c'] != 0x4a504727 or after['0xfc'] != 0x32523450:
        raise RuntimeError(f'Not 727/P4R2 after recovery: {after}')
    if any(after[hex(offset)] for offset in (0x60, 0xa4, 0xd4, 0xd8)) or after['0x84'] & 9 != 1:
        raise RuntimeError(f'Not idle/I2C-ready after recovery: {after}')
    print(json.dumps(dict(state='JPEG727_PCIE_RECOVERED_IDLE_IDENTITY_VERIFIED', registers=after,
                          driver_restored=True, camera_started=False, flash_written=False)), flush=True)


if __name__ == '__main__':
    main()
