#!/usr/bin/env python3
import argparse
import ctypes
import errno
import hashlib
import mmap
import os
import struct
import sys
from pathlib import Path


REG_CTRL = 0x60
REG_VERSION = 0x5C
REG_CAM_MODE = 0x90
REG_CAM_ERROR = 0x8C
REG_JPEG_MODE = 0xA4
REG_INPUT_OVERFLOW = 0xA8
REG_OVERSIZE = 0xAC
REG_BUSY_DROP = 0xB0
REG_INPUT_FAULT = 0xB4
REG_PREPROCESS = 0xB8
REG_PREPROCESS_ACTIVE = 0xBC
REG_MIPI_FIFO_OVERFLOW = 0xC0
CANDIDATE_VERSION = 0x4A504703
FRAME_CAPACITY = 65536


def validate_candidate(version, control, jpeg_mode):
    if version != CANDIDATE_VERSION:
        raise RuntimeError(f"expected JPEG candidate 0x{CANDIDATE_VERSION:08x}, got 0x{version:08x}; refusing writes")
    if control & 1 or jpeg_mode:
        raise RuntimeError("camera/JPEG is already active; stop the current owner first")


def jpeg_from_transfer(payload):
    if len(payload) < 4 or len(payload) > FRAME_CAPACITY:
        raise ValueError(f"invalid DMA transfer length: {len(payload)}")
    if payload[:2] != b"\xff\xd8":
        raise ValueError("missing JPEG SOI")
    end = payload.rfind(b"\xff\xd9") + 2
    if end < 4 or len(payload) - end > 15 or any(payload[end:]):
        raise ValueError(f"missing EOI or unexpected bytes after EOI: length={len(payload)} "
                         f"eoi_end={end} tail={payload[-32:].hex()} "
                         f"sha256={hashlib.sha256(payload).hexdigest()}")
    return payload[:end]


def read_dma_into(fd, buffer):
    reader = ctypes.CDLL(None, use_errno=True).read
    reader.argtypes = (ctypes.c_int, ctypes.c_void_p, ctypes.c_size_t)
    reader.restype = ctypes.c_ssize_t
    address = ctypes.addressof(ctypes.c_char.from_buffer(buffer))
    while True:
        received = reader(fd, address, len(buffer))
        if received >= 0:
            return received
        error = ctypes.get_errno()
        if error != errno.EINTR:
            raise OSError(error, os.strerror(error))


def read_transfer(fd):
    with mmap.mmap(-1, FRAME_CAPACITY) as buffer:
        received = read_dma_into(fd, buffer)
        if received <= 0 or received > FRAME_CAPACITY:
            raise RuntimeError(f"invalid DMA read result: {received}")
        return buffer[:received]


def main():
    parser = argparse.ArgumentParser(description="Capture an EOP-framed FPGA JPEG without V4L2")
    parser.add_argument("--bar-resource", type=Path, required=True, help="PCIe user BAR resourceN, not the config BAR")
    parser.add_argument("--device", default="/dev/ANLOGIC-PCI0_c2h_0")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--frames", type=int, default=1)
    parser.add_argument("--preprocess", type=int, choices=range(8), default=1,
                        help="frame-latched mask: bit0 grayscale, bit1 contrast, bit2 brightness; 0 bypass")
    parser.add_argument("--probe", action="store_true", help="read registers only; no writes or DMA")
    args = parser.parse_args()
    if args.frames < 1:
        parser.error("--frames must be positive")
    if not args.probe and args.output.exists():
        parser.error("output already exists")

    bar_fd = os.open(args.bar_resource, os.O_RDONLY if args.probe else os.O_RDWR | os.O_SYNC)
    try:
        with mmap.mmap(bar_fd, 4096, access=mmap.ACCESS_READ if args.probe else mmap.ACCESS_WRITE) as registers:
            def read(offset):
                return struct.unpack_from("<I", registers, offset)[0]

            def write(offset, value):
                struct.pack_into("<I", registers, offset, value)

            version = read(REG_VERSION)
            dimensions = read(REG_CAM_ERROR)
            print(f"version=0x{version:08x} size={dimensions >> 16 & 0x1fff}x{dimensions & 0x1fff} jpeg_mode={read(REG_JPEG_MODE)}")
            if args.probe:
                return
            validate_candidate(version, read(REG_CTRL), read(REG_JPEG_MODE))
            fd = os.open(args.device, os.O_RDONLY | os.O_TRUNC)
            try:
                validate_candidate(read(REG_VERSION), read(REG_CTRL), read(REG_JPEG_MODE))
                original_mode = read(REG_CAM_MODE)
                original_preprocess = read(REG_PREPROCESS)
                try:
                    write(REG_PREPROCESS, args.preprocess)
                    if read(REG_PREPROCESS) != args.preprocess:
                        raise RuntimeError("preprocessing mask did not latch")
                    write(REG_CAM_MODE, 2)
                    if read(REG_CAM_MODE) != 2:
                        raise RuntimeError("720p mode did not latch")
                    write(REG_JPEG_MODE, 1)
                    if read(REG_JPEG_MODE) != 1:
                        raise RuntimeError("JPEG mode did not latch; check candidate bit and REG_CAM_MODE")
                    counter_regs = (REG_INPUT_OVERFLOW, REG_OVERSIZE, REG_BUSY_DROP,
                                    REG_INPUT_FAULT, REG_MIPI_FIFO_OVERFLOW)
                    before = tuple(read(reg) for reg in counter_regs)
                    write(REG_CTRL, 1)
                    for index in range(args.frames):
                        payload = read_transfer(fd)
                        if read(REG_PREPROCESS_ACTIVE) != args.preprocess:
                            raise RuntimeError("preprocessing mode was not applied at frame start")
                        after = tuple(read(reg) for reg in counter_regs)
                        if any(after[position] != before[position] for position in (0, 1, 3, 4)):
                            raise RuntimeError(f"input/size overflow: before={before}, after={after}")
                        jpeg = jpeg_from_transfer(payload)
                        destination = args.output if args.frames == 1 else args.output.with_name(f"{args.output.stem}_{index:04d}.jpg")
                        if destination.exists():
                            raise FileExistsError(destination)
                        with destination.open("xb") as result:
                            result.write(jpeg)
                        print(f"{destination}: DMA={len(payload)} JPEG={len(jpeg)} counters={after}")
                        before = after
                finally:
                    write(REG_CTRL, 0)
                    write(REG_JPEG_MODE, 0)
                    write(REG_CAM_MODE, original_mode)
                    write(REG_PREPROCESS, original_preprocess)
            finally:
                os.close(fd)
    finally:
        os.close(bar_fd)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError) as error:
        print(f"capture failed: {error}", file=sys.stderr)
        sys.exit(1)
