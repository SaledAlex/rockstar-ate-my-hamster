#!/usr/bin/env python3
"""List and extract data blocks from a ZX Spectrum .tzx tape image.

Usage: tzx_dump.py <file.tzx> [<out_dir>]

Prints one line per TZX block. Standard ROM headers are decoded
(type/name/length/start). With out_dir, every data block payload
(flag byte and checksum stripped) is written as NN_<name>.bin, where
the name comes from the preceding ROM header when there is one.
"""
import os
import struct
import sys

HEADER_TYPES = {0: "Program", 1: "Number array", 2: "Character array", 3: "Bytes"}


def read_blocks(data):
    if data[:8] != b"ZXTape!\x1a":
        raise SystemExit("not a TZX file")
    pos = 10
    while pos < len(data):
        bid = data[pos]
        pos += 1
        if bid == 0x10:  # standard speed data
            pause, n = struct.unpack_from("<HH", data, pos)
            yield bid, "std", data[pos + 4 : pos + 4 + n]
            pos += 4 + n
        elif bid == 0x11:  # turbo speed data
            n = int.from_bytes(data[pos + 15 : pos + 18], "little")
            yield bid, "turbo", data[pos + 18 : pos + 18 + n]
            pos += 18 + n
        elif bid == 0x12:
            pos += 4
            yield bid, "pure tone", None
        elif bid == 0x13:
            pos += 1 + 2 * data[pos]
            yield bid, "pulse seq", None
        elif bid == 0x14:  # pure data
            n = int.from_bytes(data[pos + 7 : pos + 10], "little")
            yield bid, "pure data", data[pos + 10 : pos + 10 + n]
            pos += 10 + n
        elif bid == 0x15:
            n = int.from_bytes(data[pos + 5 : pos + 8], "little")
            pos += 8 + n
            yield bid, "direct rec", None
        elif bid == 0x19:
            n = struct.unpack_from("<I", data, pos)[0]
            pos += 4 + n
            yield bid, "generalized data (not decoded)", None
        elif bid == 0x20:
            pos += 2
            yield bid, "pause", None
        elif bid == 0x21:
            n = data[pos]
            yield bid, "group start: " + data[pos + 1 : pos + 1 + n].decode("latin-1"), None
            pos += 1 + n
        elif bid in (0x22, 0x25, 0x27):
            yield bid, "group/loop/call end", None
        elif bid == 0x24:
            pos += 2
            yield bid, "loop start", None
        elif bid == 0x2A:
            pos += 4
            yield bid, "stop if 48K", None
        elif bid == 0x2B:
            pos += 5
            yield bid, "signal level", None
        elif bid == 0x30:
            n = data[pos]
            yield bid, "text: " + data[pos + 1 : pos + 1 + n].decode("latin-1"), None
            pos += 1 + n
        elif bid == 0x31:
            n = data[pos + 1]
            pos += 2 + n
            yield bid, "message", None
        elif bid == 0x32:
            n = struct.unpack_from("<H", data, pos)[0]
            body = data[pos + 2 : pos + 2 + n]
            info, p = [], 1
            for _ in range(body[0]):
                ln = body[p + 1]
                info.append(body[p + 2 : p + 2 + ln].decode("latin-1"))
                p += 2 + ln
            yield bid, "archive info: " + " | ".join(info), None
            pos += 2 + n
        elif bid == 0x33:
            pos += 1 + 3 * data[pos]
            yield bid, "hardware", None
        elif bid == 0x35:
            n = struct.unpack_from("<I", data, pos + 16)[0]
            pos += 20 + n
            yield bid, "custom info", None
        elif bid == 0x5A:
            pos += 9
            yield bid, "glue", None
        else:
            raise SystemExit(f"unsupported block 0x{bid:02x} at {pos - 1}")


def main():
    path = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else None
    if out:
        os.makedirs(out, exist_ok=True)
    data = open(path, "rb").read()
    pending_name = None
    for i, (bid, desc, payload) in enumerate(read_blocks(data)):
        line = f"{i:02d} 0x{bid:02x} {desc}"
        if payload is not None:
            flag = payload[0] if payload else None
            line += f" len={len(payload)} flag={flag}"
            if bid == 0x10 and flag == 0 and len(payload) == 19:
                typ = payload[1]
                name = payload[2:12].decode("latin-1").rstrip()
                dlen, p1, p2 = struct.unpack_from("<HHH", payload, 12)
                line += f" HEADER {HEADER_TYPES.get(typ, typ)} '{name}' len={dlen} param1={p1} param2={p2}"
                pending_name = name
            elif out:
                body = payload[1:-1] if bid == 0x10 else payload
                safe = "".join(c if c.isalnum() else "_" for c in (pending_name or "headerless"))
                fn = os.path.join(out, f"{i:02d}_{safe}.bin")
                open(fn, "wb").write(body)
                line += f" -> {os.path.basename(fn)}"
                pending_name = None
        print(line)


if __name__ == "__main__":
    main()
