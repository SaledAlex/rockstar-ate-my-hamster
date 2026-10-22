#!/usr/bin/env python3
"""Scene layers that the original draws with code rather than sprite lists, captured
by running $7D41 in SkoolKit's tracer (see zxsim.py).

Usage: python -I tools/make_scenes.py Sources/RockStar/Resources   (SkoolKit venv python)

Writes scenes.json:
  limo["<flag>-<stars>"]   cells drawn by $A2EB/$7DD1 in the limousine (band seated
                           when $6239 = 1), keyed "row,col" -> 8 bytes hex. Portraits
                           are blank here; the rebuild stores the head slices itself.
  studio["<stars>"]        cells drawn by $A2E6 in the studio (window frame tiles).
  heads                    $A6AA: [bytes wide, rows, pixel y, column] of the 4 head slices.
"""
import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from zxsim import PROJ, Sim  # noqa: E402
from skoolkit.snapshot import Snapshot  # noqa: E402


def screen_cells(path):
    m = Snapshot.get(path).memory
    cells = {}
    for r in range(24):
        for c in range(32):
            rows = []
            for k in range(8):
                y = r * 8 + k
                rows.append(m[0x4000 | ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2) | c])
            cells[(r, c)] = bytes(rows)
    return cells


def render(scene, flag, stars, patch, tmp):
    s = Sim()
    s.band(stars)
    for i in range(4):                                  # blank portraits
        s.poke(0x9AA9 if i == 0 else 0x5BC6 + 240 * i, [0] * 240)
    for a in patch:
        s.poke(a, 0xC9)                                 # RET
    s.run([0x6274, ('set', 0xBEB7, scene), ('set', 0x6239, flag), 0xA9F8, 0x7E80], tmp)
    return screen_cells(tmp)


def layer(scene, flag, stars, patch, tmp):
    full = render(scene, flag, stars, (), tmp)
    base = render(scene, flag, stars, patch, tmp)
    return {'%d,%d' % k: v.hex() for k, v in full.items() if v != base[k]}


def main():
    out = sys.argv[1]
    fd, tmp = tempfile.mkstemp(suffix='.z80')
    os.close(fd)
    try:
        limo = {'%d-%d' % (f, n): layer(2, f, n, (0xA2EB, 0x7DD1), tmp) for f in (0, 1) for n in (1, 2, 3, 4)}
        studio = {'%d' % n: layer(4, 0, n, (0xA2E6,), tmp) for n in (1, 2, 3, 4)}
    finally:
        os.unlink(tmp)
    ram = open(os.path.join(PROJ, 'decompiled', 'snap', 'sideA_ram.bin'), 'rb').read()
    heads = [[ram[0xA6AA + 6 * i], ram[0xA6AB + 6 * i], ram[0xA6AC + 6 * i], ram[0xA6AD + 6 * i]] for i in range(4)]
    json.dump({'limo': limo, 'studio': studio, 'heads': heads}, open(os.path.join(out, 'scenes.json'), 'w'))
    print('scenes.json:', {k: len(v) for k, v in limo.items()}, {k: len(v) for k, v in studio.items()}, heads)


if __name__ == '__main__':
    main()
