#!/bin/sh
# Extract the game data from your own copy of the original ZX Spectrum tapes.
#
# Usage: tools/setup_assets.sh <side-A.tzx> <side-B.tzx>
#
# Side A holds the game code, side B the 50 rock star records ("data tape").
# Writes Sources/RockStar/Resources/ (text, graphics, scenes, rules tables, rock
# stars and audio/*.wav). Nothing from the original game is stored in
# this repository; these files are generated locally and ignored by git.
set -e
if [ $# -ne 2 ] || [ ! -f "$1" ] || [ ! -f "$2" ]; then
    echo "usage: $0 <side-A.tzx> <side-B.tzx>" >&2
    exit 2
fi
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SIDE_A=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
SIDE_B=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
WORK="$ROOT/.work"
VENV="$ROOT/.venv"

# SkoolKit simulates loading the tape, so memory matches the real game after load.
if [ ! -x "$VENV/bin/tap2sna.py" ]; then
    echo "Installing SkoolKit into .venv ..."
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet "skoolkit>=10"
fi

rm -rf "$WORK"
mkdir -p "$WORK/decompiled/snap" "$WORK/decompiled/tape_sideA" "$WORK/decompiled/tape_sideB"

echo "Splitting tapes ..."
python3 -I "$ROOT/tools/tzx_dump.py" "$SIDE_A" "$WORK/decompiled/tape_sideA" > /dev/null
python3 -I "$ROOT/tools/tzx_dump.py" "$SIDE_B" "$WORK/decompiled/tape_sideB" > /dev/null
CODE1=$(ls "$WORK/decompiled/tape_sideA/"*_CODE1.bin 2>/dev/null | head -1)
if [ -z "$CODE1" ]; then
    echo "error: $1 doesn't look like side A (no CODE1 block)" >&2
    exit 1
fi
[ "$CODE1" = "$WORK/decompiled/tape_sideA/04_CODE1.bin" ] || cp "$CODE1" "$WORK/decompiled/tape_sideA/04_CODE1.bin"
RECORDS=$(ls "$WORK/decompiled/tape_sideB/"*_headerless.bin 2>/dev/null | wc -l | tr -d ' ')
if [ "$RECORDS" -lt 50 ]; then
    echo "error: $2 doesn't look like side B (found $RECORDS rock star records, expected 50)" >&2
    exit 1
fi

echo "Loading side A in the emulator ..."
"$VENV/bin/python" "$VENV/bin/tap2sna.py" "$SIDE_A" "$WORK/decompiled/snap/sideA.z80" > /dev/null 2>&1
"$VENV/bin/python" -I "$ROOT/tools/snap_ram.py" "$WORK/decompiled/snap/sideA.z80" "$WORK/decompiled/snap/sideA_ram.bin"

"$VENV/bin/python" "$VENV/bin/tap2sna.py" -c machine=128 "$SIDE_A" "$WORK/decompiled/snap/sideA128.z80" > /dev/null 2>&1 || true

echo "Extracting game data ..."
python3 -I "$ROOT/tools/make_assets.py" "$WORK" "$ROOT/Sources/RockStar/Resources"

# The tools below run the original game's own code in SkoolKit's tracer.
export RS_PROJ="$WORK" RS_SKOOLKIT="$VENV/bin" RS_SNAP128="$WORK/decompiled/snap/sideA128.z80"
echo "Capturing scene graphics ..."
"$VENV/bin/python" -I "$ROOT/tools/make_scenes.py" "$ROOT/Sources/RockStar/Resources"
echo "Recording sound and music (takes a few minutes) ..."
"$VENV/bin/python" -I "$ROOT/tools/make_audio.py" "$ROOT/Sources/RockStar/Resources/audio"
rm -rf "$WORK"
echo "Done. Now run: swift run RockStar"
