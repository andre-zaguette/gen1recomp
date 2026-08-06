"""LZ3 decompressor, used by Pokemon Gold/Silver/Crystal for most graphics.

Ported from pret/pokecrystal's home/decompress.asm (Decompress::), read
directly from https://github.com/pret/pokecrystal/blob/master/home/decompress.asm
during planning -- see docs/superpowers/plans/2026-08-03-gen2-crystal-extraction-skeleton.md
for the command-byte layout this mirrors. This module only decompresses
(the game never needs re-compressing at runtime).
"""

LZ_END = 0xFF

CMD_LITERAL = 0
CMD_ITERATE = 1
CMD_ALTERNATE = 2
CMD_ZERO = 3
CMD_REPEAT = 4
CMD_FLIP = 5
CMD_REVERSE = 6
CMD_LONG = 7


def _flip_byte(value):
    result = 0
    for bit in range(8):
        if value & (1 << bit):
            result |= 1 << (7 - bit)
    return result


def decompress(data):
    """Decode one LZ_END-terminated LZ3 stream from the start of `data`."""
    out = bytearray()
    pos = 0
    start_pos = 0  # output length at stream start; REPEAT/FLIP/REVERSE positive offsets are relative to this

    def read_byte():
        nonlocal pos
        value = data[pos]
        pos += 1
        return value

    while True:
        header = read_byte()
        if header == LZ_END:
            break
        cmd = (header >> 5) & 0x7
        if cmd == CMD_LONG:
            cmd = (header >> 2) & 0x7
            hi = header & 0x3
            lo = read_byte()
            length = ((hi << 8) | lo) + 1
        else:
            length = (header & 0x1F) + 1

        if cmd == CMD_LITERAL:
            out.extend(data[pos:pos + length])
            pos += length
        elif cmd == CMD_ITERATE:
            value = read_byte()
            out.extend(bytes([value]) * length)
        elif cmd == CMD_ALTERNATE:
            a, b = data[pos], data[pos + 1]
            pos += 2
            for i in range(length):
                out.append(a if i % 2 == 0 else b)
        elif cmd == CMD_ZERO:
            out.extend(bytes(length))
        elif cmd in (CMD_REPEAT, CMD_FLIP, CMD_REVERSE):
            offset_byte = read_byte()
            if offset_byte & 0x80:
                magnitude = offset_byte & 0x7F
                src = len(out) - magnitude - 1
            else:
                lo = read_byte()
                src = start_pos + ((offset_byte << 8) | lo)
            if cmd == CMD_REPEAT:
                for i in range(length):
                    out.append(out[src + i])
            elif cmd == CMD_FLIP:
                for i in range(length):
                    out.append(_flip_byte(out[src + i]))
            else:
                for i in range(length):
                    out.append(out[src - i])
        else:
            raise ValueError(f"unknown LZ3 command {cmd}")
    return bytes(out)
