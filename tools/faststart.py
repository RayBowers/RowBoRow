#!/usr/bin/env python3
"""Move the moov atom to the front of an MP4 (like `ffmpeg -movflags +faststart`), in place.

Usage: faststart.py file.mp4 [more.mp4 ...]
Pure Python, no dependencies. Files whose moov is already before mdat are left untouched.
Moving moov ahead of mdat shifts the media data, so every chunk offset in the stco/co64
tables is increased by the size of moov.
"""
import struct
import sys

CONTAINERS = {b"moov", b"trak", b"mdia", b"minf", b"stbl", b"edts", b"udta"}


def atoms(data, start, end):
    """Yield (type, offset, size, header_size) for each atom in data[start:end]."""
    pos = start
    while pos + 8 <= end:
        size, kind = struct.unpack(">I4s", data[pos:pos + 8])
        header = 8
        if size == 1:
            size = struct.unpack(">Q", data[pos + 8:pos + 16])[0]
            header = 16
        elif size == 0:
            size = end - pos
        if size < header:
            raise ValueError("corrupt atom at %d" % pos)
        yield kind, pos, size, header
        pos += size


def shift_offsets(moov, delta):
    """Add delta to every stco/co64 chunk offset inside the moov atom (a bytearray)."""
    def walk(start, end):
        for kind, pos, size, header in atoms(moov, start, end):
            if kind in CONTAINERS:
                walk(pos + header, pos + size)
            elif kind in (b"stco", b"co64"):
                count = struct.unpack(">I", moov[pos + header + 4:pos + header + 8])[0]
                table = pos + header + 8
                fmt, width = (">I", 4) if kind == b"stco" else (">Q", 8)
                for i in range(count):
                    at = table + i * width
                    value = struct.unpack(fmt, moov[at:at + width])[0] + delta
                    moov[at:at + width] = struct.pack(fmt, value)
    walk(0, len(moov))


def faststart(path):
    data = open(path, "rb").read()
    top = list(atoms(data, 0, len(data)))
    kinds = [t[0] for t in top]
    if b"moov" not in kinds or b"mdat" not in kinds:
        raise ValueError("no moov/mdat in " + path)
    if kinds.index(b"moov") < kinds.index(b"mdat"):
        return False
    _, mpos, msize, _ = top[kinds.index(b"moov")]
    moov = bytearray(data[mpos:mpos + msize])
    shift_offsets(moov, msize)
    # Order: ftyp (and anything else before mdat), moov, then the rest minus the old moov.
    first_mdat = top[kinds.index(b"mdat")][1]
    out = data[:first_mdat] + bytes(moov) + data[first_mdat:mpos] + data[mpos + msize:]
    open(path, "wb").write(out)
    return True


if __name__ == "__main__":
    for p in sys.argv[1:]:
        print(("faststart: " if faststart(p) else "already fast: ") + p)
