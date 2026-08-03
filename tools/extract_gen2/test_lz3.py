# tools/extract_gen2/test_lz3.py
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from extract_gen2 import lz3


class Lz3Test(unittest.TestCase):
    def test_literal(self):
        # cmd=0 (LITERAL), length field = 3-1 = 2 -> header 0b000_00010 = 0x02
        data = bytes([0x02, 0x41, 0x42, 0x43, 0xFF])
        self.assertEqual(lz3.decompress(data), b"ABC")

    def test_iterate(self):
        # cmd=1 (ITERATE) << 5 = 0x20, length field = 5-1 = 4 -> 0x24
        data = bytes([0x24, 0x99, 0xFF])
        self.assertEqual(lz3.decompress(data), bytes([0x99]) * 5)

    def test_alternate(self):
        # cmd=2 (ALTERNATE) << 5 = 0x40, length field = 6-1 = 5 -> 0x45
        data = bytes([0x45, 0xAA, 0xBB, 0xFF])
        self.assertEqual(lz3.decompress(data), bytes([0xAA, 0xBB, 0xAA, 0xBB, 0xAA, 0xBB]))

    def test_zero(self):
        # cmd=3 (ZERO) << 5 = 0x60, length field = 4-1 = 3 -> 0x63
        data = bytes([0x63, 0xFF])
        self.assertEqual(lz3.decompress(data), bytes(4))

    def test_repeat_negative_offset(self):
        # 3 literal bytes "ABC", then REPEAT 3 bytes from offset -3
        # (back to the start of "ABC"): cmd=4<<5=0x80, length field=3-1=2 -> 0x82,
        # offset byte with bit7 set, magnitude 3 -> 0x83
        data = bytes([0x02, 0x41, 0x42, 0x43, 0x82, 0x83, 0xFF])
        self.assertEqual(lz3.decompress(data), b"ABCABC")

    def test_repeat_positive_offset(self):
        # 3 literal bytes "XYZ", then REPEAT 3 bytes from the start of the
        # whole output (positive offset 0x0000): cmd=4<<5=0x80, length
        # field=3-1=2 -> 0x82, offset hi=0x00 (bit7 clear), lo=0x00
        data = bytes([0x02, 0x58, 0x59, 0x5A, 0x82, 0x00, 0x00, 0xFF])
        self.assertEqual(lz3.decompress(data), b"XYZXYZ")

    def test_flip_bit_reverses_each_byte(self):
        # 1 literal byte 0b10110000 (0xB0), then FLIP 1 byte from offset -1
        # cmd=5<<5=0xA0, length field=1-1=0 -> 0xA0, offset byte 0x81 (bit7 set, magnitude 1)
        data = bytes([0x00, 0xB0, 0xA0, 0x81, 0xFF])
        # 0xB0 = 0b10110000 -> bit-reversed = 0b00001101 = 0x0D
        self.assertEqual(lz3.decompress(data), bytes([0xB0, 0x0D]))

    def test_long_command(self):
        # LZ_LONG (cmd=7): real command in bits 2-4 of the header.
        # header = 111 xxx yy -> want inner cmd=0 (LITERAL), so xxx=000:
        # header = 0b111_000_yy. Want length 32 (needs the 10-bit form):
        # length field = 32 - 1 = 31 = 0b0000011111 -> hi(2 bits)=00, lo(8 bits)=0b00011111=0x1F
        header = 0b11100000  # cmd bits 000 -> LITERAL, length hi = 00
        data = bytes([header, 0x1F]) + bytes(range(32)) + bytes([0xFF])
        self.assertEqual(lz3.decompress(data), bytes(range(32)))


if __name__ == "__main__":
    unittest.main()
