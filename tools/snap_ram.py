#!/usr/bin/env python3
"""Dump a 48K Spectrum snapshot's RAM as a flat 64K image (ROM area zeroed).

Usage: snap_ram.py <snapshot.z80|.sna|.szx> <out.bin>
Run with the tools venv python (needs SkoolKit). File offset == Z80 address.
"""
import sys

from skoolkit.snapshot import Snapshot

ram = bytes(Snapshot.get(sys.argv[1]).ram(-1))  # 49152 bytes from 16384
with open(sys.argv[2], "wb") as f:
    f.write(bytes(16384) + ram[:49152])
