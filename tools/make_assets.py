#!/usr/bin/env python3
"""Build the rebuild's data bundle from the original Spectrum game files.

Usage: make_assets.py <project_dir> <out_resources_dir>

Reads decompiled/snap/sideA_ram.bin (flat 64K, offset == address) and
decompiled/tape_sideB/*.bin, and writes:
  font.bin        96 glyphs (ASCII 0x20-0x7F) x 6 rows, from $86A7 + 6*code
  messages.json   all messages as part lists, resolved at runtime:
                    {"t":"text","v":...} | {"t":"rand","v":[...]}
                    {"t":"str","v":slot} | {"t":"num","v":slot}
  gamedata.json   rules tables: RNG table ($BE59), 30 rival bands (chart
                  entries $ABC8/$AC5E, song choices $7CE7), name strings
                  ($ACF4), suggested band names ($C6E2), rank/royalty tables
  graphics.json   scene sprite lists, attribute lists, box table, big font,
                  loading screen
  rockstars.json  name, stats (10 bytes) and portrait (240 bytes, hex,
                  1bpp 40x48 row-major) for each of the 50 tape records
The output is generated from the user's own copy and is not committed anywhere.
"""
import glob
import json
import os
import sys

MSG_TABLE, DICT, RAND_TABLE, FONT = 0xB1C5, 0xDDE5, 0xC803, 0x86A7


def phrase_at(ram, addr):
    out = []
    while True:
        b = ram[addr]
        out.append(chr(b & 0x7F))
        addr += 1
        if b & 0x80:
            return "".join(out), addr


def nth_phrase(ram, start, n):
    addr = start
    for _ in range(n):
        while not ram[addr] & 0x80:
            addr += 1
        addr += 1
    return phrase_at(ram, addr)[0]


def rand_group(ram, idx):
    addr = RAND_TABLE
    for _ in range(idx):
        while ram[addr] != 0xFF:
            addr += 1
        addr += 1
    return [nth_phrase(ram, addr + 1, i) for i in range(ram[addr] + 1)]  # byte = highest index


def messages(ram):
    n_phrases = count_phrases(ram)
    out, addr = [], MSG_TABLE
    while addr < DICT:
        refs = []
        while ram[addr] != 0xFF:
            refs.append((ram[addr], ram[addr + 1]))
            addr += 2
        addr += 1
        parts = ref_parts(ram, refs, n_phrases)
        if parts is None:
            return out
        out.append(parts)
    return out


def count_phrases(ram):
    n, a = 0, DICT
    while ram[a] != 0:
        a = phrase_at(ram, a)[1]
        n += 1
    return n


def ref_parts(ram, refs, n_phrases):
    """Decode (B, C) refs in the same order as the printer at $A8F5:
    bit5 = number slot, bit6 = string slot, bit7 = random group, else phrase."""
    parts = []
    for b, c in refs:
        if b & 0x20:
            parts.append({"t": "num", "v": c})
        elif b & 0x40:
            parts.append({"t": "str", "v": c})
        elif b & 0x80:
            parts.append({"t": "rand", "v": rand_group(ram, (b & 7) * 256 + c)})
        else:
            n = b * 256 + c
            if n >= n_phrases:
                return None
            parts.append({"t": "text", "v": nth_phrase(ram, DICT, n)})
    return parts


def ref_strings(ram, addr, count):
    """$FF-terminated (B, C) ref strings, e.g. the name list at $ACF4."""
    n_phrases = count_phrases(ram)
    out = []
    for _ in range(count):
        refs = []
        while ram[addr] != 0xFF:
            refs.append((ram[addr], ram[addr + 1]))
            addr += 2
        addr += 1
        out.append(ref_parts(ram, refs, n_phrases))
    return out


def game_data(ram):
    """Tables used by the rules model (addresses from notes/rules_*.md)."""
    rivals = []
    for s in range(30):
        rivals.append({
            "single": list(ram[0xABC8 + 5 * s: 0xABC8 + 5 * s + 5]),
            "album": list(ram[0xAC5E + 5 * s: 0xAC5E + 5 * s + 5]),
            "songChoices": list(ram[0x7CE7 + 3 * s: 0x7CE7 + 3 * s + 3]),
            "albumTitle": 57 - s,
        })
    return {
        "rngTable": list(ram[0xBE59:0xBE59 + 64]),
        "rivals": rivals,
        "respawnScores": list(ram[0xC7FC:0xC7FC + 6]),
        "respawnStart": ram[0xC7FB],
        "nameStrings": ref_strings(ram, 0xACF4, 58),
        "bandNames": ref_strings(ram, 0xC6E2, 8),
        "videoRankTable": list(ram[0xC7E7:0xC7E7 + 10]),
        "fameRankTable": list(ram[0xC7F1:0xC7F1 + 10]),
        "royaltyPercent": list(ram[0xC71F:0xC71F + 6]),
        "studioDays": list(ram[0xBE99:0xBE99 + 6]),
    }


def rockstars(tape_dir):
    stars = []
    for fn in sorted(glob.glob(os.path.join(tape_dir, "*.bin"))):
        rec = open(fn, "rb").read()
        name = ""
        for b in rec[0xF0:0x104]:
            if b == 0:
                break
            name += chr(b & 0x7F)
            if b & 0x80:
                break
        stars.append({"name": name.strip(), "stats": list(rec[0x104:0x10E]), "portrait": rec[:240].hex()})
    return stars


def graphics(ram, proj):
    """Scene sprite lists ($8434), attribute lists ($830F), box table ($AEB0),
    big font ($90B5) and the loading screen (tape block CODE1)."""
    lists, sprites, p = [], {}, 0x8434
    for _ in range(23):                       # $7D41 uses lists 0..22
        entries = []
        while ram[p] != 0xFF:
            addr = ram[p] * 256 + ram[p + 1]
            entries.append({"sprite": "%04X" % addr, "y": ram[p + 2],
                            "col": ram[p + 3] & 0x7F, "mirror": bool(ram[p + 3] & 0x80)})
            if "%04X" % addr not in sprites:
                w, h = ram[addr], ram[addr + 1]
                sprites["%04X" % addr] = {"w": w, "h": h, "data": ram[addr + 2:addr + 2 + w * h].hex()}
            p += 4
        lists.append(entries)
        p += 1
    for addr in (0x9489,):                    # newspaper body-text filler ($8160)
        w, h = ram[addr], ram[addr + 1]
        sprites["%04X" % addr] = {"w": w, "h": h, "data": ram[addr + 2:addr + 2 + w * h].hex()}
    attrs, a = [], 0x830F
    while a < 0x8434:
        l = []
        while ram[a] != 0xFF:
            l.append([ram[a], ram[a + 1]])
            a += 2
        attrs.append(l)
        a += 1
    boxes, b = [], 0xAEB0
    while ram[b] != 0xFF and len(boxes) < 256:
        boxes.append(list(ram[b:b + 4]))
        b += 4
    big = ram[0x90B5 + 28 * 0x20:0x90B5 + 28 * 0x5B]
    scr = open(os.path.join(proj, "decompiled/tape_sideA/04_CODE1.bin"), "rb").read()[:6912]
    credits = bytes(b & 0x7F for b in ram[0x7C19:ram.index(0xFF, 0x7C19)]).decode("ascii")
    return {"credits": credits, "spriteLists": lists, "sprites": sprites, "attrLists": attrs, "boxes": boxes,
            "bigFont": big.hex(), "loadingScreen": scr.hex()}


def main():
    proj, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    ram = open(os.path.join(proj, "decompiled/snap/sideA_ram.bin"), "rb").read()
    font = b"".join(ram[FONT + 6 * c : FONT + 6 * c + 6] for c in range(0x20, 0x80))
    open(os.path.join(out, "font.bin"), "wb").write(font)
    msgs = messages(ram)
    json.dump(msgs, open(os.path.join(out, "messages.json"), "w"))
    stars = rockstars(os.path.join(proj, "decompiled/tape_sideB"))
    json.dump(stars, open(os.path.join(out, "rockstars.json"), "w"))
    json.dump(graphics(ram, proj), open(os.path.join(out, "graphics.json"), "w"))
    data = game_data(ram)
    json.dump(data, open(os.path.join(out, "gamedata.json"), "w"))
    print(f"font {len(font)} bytes, {len(msgs)} messages, {len(stars)} rock stars")


if __name__ == "__main__":
    main()
