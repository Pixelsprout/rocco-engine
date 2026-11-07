import struct
import unittest

from host_fltused import EXTERNAL, STATIC, SYMBOL_SIZE, fltused_object, localize


def symbols(obj):
    symbol_table, count = struct.unpack_from('<II', obj, 8)
    found = []
    index = 0
    while index < count:
        offset = symbol_table + index * SYMBOL_SIZE
        name = obj[offset:offset + 8].rstrip(b'\0')
        section, _, storage, aux = struct.unpack_from('<hHBB', obj, offset + 12)
        found.append((name, section, storage))
        index += 1 + aux
    return found


def with_long_name(name):
    """A one-symbol object whose name lives in the string table."""
    obj = bytearray(fltused_object())
    symbol_table, _ = struct.unpack_from('<II', obj, 8)
    struct.pack_into('<II', obj, symbol_table, 0, 4)
    strings = name + b'\0'
    return bytes(obj[:-4]) + struct.pack('<I', 4 + len(strings)) + strings


class HostFltusedTest(unittest.TestCase):
    def test_object_defines_one_global_fltused_in_data(self):
        obj = fltused_object()
        self.assertEqual(struct.unpack_from('<H', obj, 0)[0], 0x8664)
        self.assertEqual(obj[20:28].rstrip(b'\0'), b'.data')
        self.assertEqual(struct.unpack_from('<I', obj, 60)[0], 0x9875)
        self.assertEqual(symbols(obj), [(b'_fltused', 1, EXTERNAL)])

    def test_localize_makes_the_definition_static(self):
        self.assertEqual(symbols(localize(fltused_object(), b'_fltused')), [(b'_fltused', 1, STATIC)])

    def test_localize_reads_names_from_the_string_table(self):
        obj = localize(with_long_name(b'a_symbol_longer_than_eight'), b'a_symbol_longer_than_eight')
        self.assertEqual(symbols(obj)[0][2], STATIC)

    def test_localize_requires_one_definition(self):
        with self.assertRaises(ValueError):
            localize(fltused_object(), b'_tls_index')
        with self.assertRaises(ValueError):
            localize(localize(fltused_object(), b'_fltused'), b'_fltused')


if __name__ == '__main__':
    unittest.main()
