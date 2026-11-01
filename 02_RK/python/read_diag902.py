import argparse
import json
import mmap
import os
import struct
import time
from pathlib import Path

VERSION = 0x4A504976
MAGIC = 0x52583714
NAMES = (
    'byte_clock_cycles', 'raw_bytes', 'aligned_bytes', 'phy_status',
    'lane0_align_rises', 'lane1_align_rises', 'lane2_align_rises', 'lane3_align_rises',
    'lane0_raw_b8', 'lane1_raw_b8', 'lane2_raw_b8', 'lane3_raw_b8',
    'gear_words', 'header_attempts', 'accepted_headers', 'bad_ecc_headers',
    'filtered_headers', 'payload_timeouts', 'last_accepted_header', 'last_rejected_header',
    'payload_bytes', 'unpack_groups', 'current_line_groups', 'previous_line_groups',
    'frame_start_headers', 'frame_end_headers', 'current_frame_lines', 'previous_frame_lines',
    'last_line_type_word_count', 'raw10_headers', 'raw12_headers', 'embedded_headers',
)


def collect(read32, write32, timeout=0.25):
    version = read32(0x5c)
    if version != VERSION:
        raise RuntimeError(f'Expected diagnostic version 0x{VERSION:08x}, got 0x{version:08x}; no writes performed')

    def select(index):
        write32(0x6c, index)
        return read32(0x6c)

    try:
        if select(0) != MAGIC or select(3) != len(NAMES):
            raise RuntimeError('Diagnostic ABI magic or size mismatch')
        if select(1) != 4 and select(1) != 5:
            raise RuntimeError('Receiver reset or snapshot already busy; camera clock may be absent')
        generation = select(2)
        write32(0x6c, 0x80000001)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            status = read32(0x6c)
            if status == 5:
                break
            if status & 4 == 0:
                raise RuntimeError('Receiver reset during snapshot; no valid sample')
            time.sleep(0.001)
        else:
            raise TimeoutError('No byte-clock snapshot acknowledgement; not a valid zero counter sample')
        expected = (generation + 1) & 0xffffffff
        if select(2) != expected:
            raise RuntimeError('Unexpected snapshot generation; reset or concurrent writer')
        values = {name: select(index + 4) for index, name in enumerate(NAMES)}
        if select(1) != 5 or select(2) != expected or read32(0x5c) != VERSION:
            raise RuntimeError('Snapshot invalidated while reading')
        phy = values['phy_status']
        return dict(state='RX714_DIAGNOSTIC_SNAPSHOT_NOT_FRAME_ACCEPTANCE', version=f'0x{VERSION:08x}',
                    generation=expected, registers=values,
                    phy=dict(lane_valid=phy & 15, delay_tap=(phy >> 4) & 63,
                             manual_mode=bool(phy & (1 << 10)), delay_load=bool(phy & (1 << 11)),
                             best_length=(phy >> 12) & 63, auto_done=bool(phy & (1 << 18))),
                    last_line=dict(data_type=values['last_line_type_word_count'] >> 16,
                                   word_count=values['last_line_type_word_count'] & 0xffff),
                    board_frames_verified=False, payload_crc_checked=False)
    finally:
        write32(0x6c, 0)


