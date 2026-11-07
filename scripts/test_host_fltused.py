import struct
import unittest

from host_fltused import EXTERNAL, SEARCH_ALIAS, SYMBOL_SIZE, WEAK_EXTERNAL, symbol_name, weaken


def data_object(*names):
    """An x64 COFF object whose .data holds one 4-byte global per name."""
    raw_data = 20 + 40
    size = 4 * len(names)
    symbol_table = raw_data + size
    header = struct.pack('<HHIIIHH', 0x8664, 1, 0, symbol_table, len(names), 0, 0)
    section = struct.pack('<8sIIIIIIHHI', b'.data', 0, 0, size, raw_data, 0, 0, 0, 0, 0xC0300040)
    symbols = b''.join(struct.pack('<8sIhHBB', name, 4 * i, 1, 0, EXTERNAL, 0) for i, name in enumerate(names))
    return header + section + bytes(size) + symbols + struct.pack('<I', 4)


def symbols(obj):
    symbol_table, count = struct.unpack_from('<II', obj, 8)
    string_table = symbol_table + count * SYMBOL_SIZE
    found = []
    index = 0
    while index < count:
        offset = symbol_table + index * SYMBOL_SIZE
        section, _, storage, aux = struct.unpack_from('<hHBB', obj, offset + 12)
        entry = {'index': index, 'name': symbol_name(obj, offset, string_table), 'section': section, 'storage': storage}
        if aux:
            entry['aux'] = struct.unpack_from('<II', obj, offset + SYMBOL_SIZE)
        found.append(entry)
        index += 1 + aux
    return found


class WeakenTest(unittest.TestCase):
    def test_renames_the_definition_and_adds_a_weak_external_with_it_as_default(self):
        obj = weaken(data_object(b'_tls_idx', b'_fltused'), b'_fltused', b'__rocco_host_fltused')
        self.assertEqual(symbols(obj), [
            {'index': 0, 'name': b'_tls_idx', 'section': 1, 'storage': EXTERNAL},
            {'index': 1, 'name': b'__rocco_host_fltused', 'section': 1, 'storage': EXTERNAL},
            {'index': 2, 'name': b'_fltused', 'section': 0, 'storage': WEAK_EXTERNAL, 'aux': (1, SEARCH_ALIAS)},
        ])

    def test_keeps_the_sections_and_their_data(self):
        before = data_object(b'_fltused')
        after = weaken(before, b'_fltused', b'__rocco_host_fltused')
        symbol_table, = struct.unpack_from('<I', before, 8)
        self.assertEqual(after[16:symbol_table], before[16:symbol_table])

    def test_requires_one_definition(self):
        with self.assertRaises(ValueError):
            weaken(data_object(b'_tls_idx'), b'_fltused', b'__rocco_host_fltused')
        with self.assertRaises(ValueError):
            weaken(data_object(b'_fltused', b'_fltused'), b'_fltused', b'__rocco_host_fltused')

    def test_rejects_an_object_with_data_after_its_symbol_table(self):
        obj = bytearray(data_object(b'_fltused'))
        struct.pack_into('<I', obj, 20 + 20, len(obj))
        with self.assertRaises(ValueError):
            weaken(bytes(obj), b'_fltused', b'__rocco_host_fltused')


if __name__ == '__main__':
    unittest.main()
