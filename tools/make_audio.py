#!/usr/bin/env python3
"""Render the original game's sound and music to WAV by running its own sound code in
SkoolKit's tracer (see zxsim.py). Nothing here is hand-made: every sample comes from
the user's copy of the game.

Usage (from rebuild/, with the SkoolKit venv's python):
  python -I tools/make_audio.py Sources/RockStar/Resources/audio [-j N]

48K beeper (snapshot decompiled/snap/sideA.z80):
  beeper_jingle<n>.wav   n = 0..7   `$812A` -> `$EDC9` with A = n
  beeper_sfx<n>.wav      n = 0, 1   `$8145` -> `$EDCC` with A = n
  beeper_practice_<seed>_<skill>.wav  `$80EE` -> P. Hiley composer `$EDC6`/`$F067`
128K AY (the headerless tape block, as loaded into RAM bank 1 of the 128K snapshot
in extracted/; driver entry points $C000 note, $C003 jingle, $C006 sfx):
  ay_jingle<n>.wav, ay_sfx<n>.wav, ay_practice_<seed>_<skill>.wav
The practice tune depends on a seed (0-31, `$BE57 & 31`), three voice bytes from the
stars' records (`$BEF2-$BEF4`) and the band's skill (`$BEF5`, chance of wrong notes).
A representative set is rendered: SEEDS x SKILLS, voices derived from the seed.
Output is 22,050 Hz 8-bit mono, with trailing silence trimmed.
"""
import audioop
import concurrent.futures
import os
import sys
import tempfile
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from zxsim import Sim, PROJ  # noqa: E402

SNAP128 = os.environ.get('RS_SNAP128') or os.path.join(PROJ, 'extracted', 'Rock Star Ate my Hamster (1989)(Codemasters)[t][128K].Z80',
                       'Rock Star Ate my Hamster (1989)(Codemasters)[t][128K].z80')
SEEDS = [0, 5, 10, 15, 16, 21, 26, 31]
SKILLS = [0, 50, 100, 200]
JINGLES, SFX = range(8), range(2)
# DI; page RAM bank 1 at $C000 (ROM 1): LD A,$11; LD BC,$7FFD; OUT (C),A
PAGE1 = ('raw', [0xF3, 0x3E, 0x11, 0x01, 0xFD, 0x7F, 0xED, 0x79])


def voices(seed):
    # INFERRED: a fixed voice triple per seed stands in for the stars' voice bytes.
    return seed % 8, (seed * 3 + 1) % 8, (seed * 5 + 2) % 8


def jobs():
    out = []
    for n in JINGLES:
        out.append(('beeper_jingle%d' % n, 'beeper', [(0xEDC9, n)]))
        out.append(('ay_jingle%d' % n, 'ay', [PAGE1, (0xC003, n)]))
    for n in SFX:
        out.append(('beeper_sfx%d' % n, 'beeper', [(0xEDCC, n)]))
        out.append(('ay_sfx%d' % n, 'ay', [PAGE1, (0xC006, n)]))
    for seed in SEEDS:
        v0, v1, v2 = voices(seed)
        for skill in SKILLS:
            # $80EE (48K): $EDCF=$BEF2 $EDD1=$BEF4 $EDD3=$BEF3 $EDD7=skill $EDD5=seed
            beeper = [('set', 0xBEF2, v0), ('set', 0xBEF3, v1), ('set', 0xBEF4, v2), ('set', 0xBEF5, skill),
                      (0x80EE, seed)]
            # $8116 -> $6970 (128K): $C009=$BEF2 $C00D=$BEF3 $C00B=$BEF4 $C011=skill $C00F=seed; CALL $C000
            ay = [PAGE1, ('set', 0xC009, v0), ('set', 0xC00D, v1), ('set', 0xC00B, v2), ('set', 0xC011, skill),
                  ('set', 0xC00F, seed), 0xC000]
            out.append(('beeper_practice_%d_%d' % (seed, skill), 'beeper', beeper))
            out.append(('ay_practice_%d_%d' % (seed, skill), 'ay', ay))
    return out


def convert(src, dst):
    """44.1 kHz 16-bit -> 22.05 kHz 8-bit unsigned, trailing silence trimmed."""
    w = wave.open(src)
    ch, width, rate = w.getnchannels(), w.getsampwidth(), w.getframerate()
    data = w.readframes(w.getnframes())
    w.close()
    if ch == 2:
        data = audioop.tomono(data, width, 0.5, 0.5)
    data, _ = audioop.ratecv(data, width, 1, rate, 22050, None)
    data = audioop.lin2lin(data, width, 1)
    data = audioop.bias(data, 1, 128)                       # signed -> unsigned 8-bit
    end = len(data)
    while end > 0 and abs(data[end - 1] - 128) < 2:
        end -= 1
    data = data[:min(len(data), end + 2205)]                # keep 0.1 s tail
    o = wave.open(dst, 'wb')
    o.setnchannels(1)
    o.setsampwidth(1)
    o.setframerate(22050)
    o.writeframes(data)
    o.close()


def render(job, outdir):
    name, kind, calls = job
    fd, tmp = tempfile.mkstemp(suffix='.wav')
    os.close(fd)
    try:
        if kind == 'ay':
            Sim(SNAP128).run(calls, tmp, maxops=600_000_000, extra=['--ay', '--beeper'])
        else:
            Sim().run(calls, tmp, maxops=600_000_000)
        convert(tmp, os.path.join(outdir, name + '.wav'))
        return name, None
    except Exception as e:                                  # e.g. no 128K snapshot
        return name, str(e).splitlines()[-1] if str(e) else repr(e)
    finally:
        os.unlink(tmp)


def main():
    outdir = sys.argv[1]
    n = int(sys.argv[sys.argv.index('-j') + 1]) if '-j' in sys.argv else os.cpu_count() or 4
    os.makedirs(outdir, exist_ok=True)
    todo = jobs()
    if not os.path.exists(SNAP128):
        print('no 128K snapshot (%s): AY tunes skipped' % SNAP128)
        todo = [j for j in todo if j[1] != 'ay']
    failed = []
    with concurrent.futures.ProcessPoolExecutor(n) as ex:
        for name, err in ex.map(render, todo, [outdir] * len(todo)):
            if err:
                failed.append((name, err))
    print('rendered %d of %d sounds into %s' % (len(todo) - len(failed), len(todo), outdir))
    for name, err in failed:
        print('  failed:', name, err)


if __name__ == '__main__':
    main()
