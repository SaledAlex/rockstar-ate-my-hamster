"""Run the original game's own code in SkoolKit's tracer (shared by the asset tools).

The project's snapshot is patched in memory (game state, star records, a stub of
CALLs at $5B80), written to a temporary .z80 and run with trace.py, which writes
a PNG, WAV or snapshot. Needs SkoolKit 10 (set RS_SKOOLKIT to its bin directory;
the default is ../tools/venv/bin next to the project). Run the tools with that
venv's python.
"""
import glob
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.environ.get('RS_PROJ') or os.path.normpath(os.path.join(HERE, '..', '..'))
SKOOLKIT = os.environ.get('RS_SKOOLKIT') or os.path.normpath(os.path.join(PROJ, '..', 'tools', 'venv', 'bin'))
STUB = 0x5B80

sys.path.insert(0, os.path.join(SKOOLKIT, '..', 'lib', 'python%d.%d' % sys.version_info[:2], 'site-packages'))
from skoolkit.snapshot import Snapshot  # noqa: E402


def stub_code(calls):
    """calls: addr | (addr, A) | (addr, A, BC) | ('set', addr, byte) | ('raw', [bytes])."""
    code = []
    for c in calls:
        if isinstance(c, tuple) and c[0] == 'raw':     # ('raw', [opcodes])
            code += list(c[1])
            continue
        if isinstance(c, tuple) and c[0] == 'set':
            code += [0x3E, c[2], 0x32, c[1] & 0xFF, c[1] >> 8]
            continue
        addr, a, bc = (c + (None, None))[:3] if isinstance(c, tuple) else (c, None, None)
        if a is not None:
            code += [0x3E, a]
        if bc is not None:
            code += [0x01, bc & 0xFF, bc >> 8]
        code += [0xCD, addr & 0xFF, addr >> 8]
    return code


def star_records(n=4):
    recs = []
    for fn in sorted(glob.glob(os.path.join(PROJ, 'decompiled', 'tape_sideB', '*.bin')))[:n]:
        recs.append(open(fn, 'rb').read())
    return recs


class Sim:
    def __init__(self, snapshot=None):
        self.path = snapshot or os.path.join(PROJ, 'decompiled', 'snap', 'sideA.z80')
        self.snap = Snapshot.get(self.path)

    def poke(self, addr, data):
        if isinstance(data, int):
            data = [data]
        for i, b in enumerate(data):
            self.snap.memory[addr + i] = b & 0xFF

    def peek(self, addr, n=1):
        return [self.snap.memory[addr + i] for i in range(n)]

    def text(self, addr, s, terminator=0):
        self.poke(addr, list(s.encode('ascii')) + [terminator])

    def band(self, stars=4):
        """A plausible band: the first `stars` tape records hired into slots 0-3.
        Call $64A9 after $6274 to set the band name (STR0) to suggestion 0."""
        self.poke(0xBF24, stars)
        self.poke(0xBF25, stars)
        for i, rec in enumerate(star_records(4)):
            dest = 0x9AA9 if i == 0 else 0x5BC6 + 240 * i
            self.poke(dest, rec[:240])
            self.poke(0x613F + 4 * i, rec[0x109:0x10D])
            self.poke(0x619D + i, 0 if i < stars else 0x80)

    def run(self, calls, out, stop=None, maxops=60_000_000, start=None, extra=(), regs=()):
        code = stub_code(calls)
        self.poke(STUB, code)
        fd, tmp = tempfile.mkstemp(suffix='.z80')
        os.close(fd)
        try:
            self.snap.write(tmp)
            args = [os.path.join(SKOOLKIT, 'python'), '-I', os.path.join(SKOOLKIT, 'trace.py'),
                    '--start', str(start if start is not None else STUB),
                    '--stop', str(stop if stop is not None else STUB + len(code))]
            if maxops:
                args += ['-m', str(maxops)]
            for r in regs:
                args += ['-r', r]
            args += list(extra) + [tmp, out]
            r = subprocess.run(args, capture_output=True, text=True)
            if r.returncode != 0:
                raise RuntimeError(r.stderr.strip() or r.stdout.strip())
            return r.stdout
        finally:
            os.unlink(tmp)
