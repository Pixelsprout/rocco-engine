# Run from the repository root: python3 -m unittest scripts/test_make_windows_import_libs.py

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import make_windows_import_libs as libs

UCRTBASE = (
    "; The C runtime names the host calls.\n"
    "LIBRARY \"ucrtbase.dll\"\n"
    "EXPORTS\n"
    "\n"
    "free\n"
    "malloc ; sokol\n"
)


class ParseTest(unittest.TestCase):
    def test_reads_the_library_and_the_exports_and_drops_comments(self):
        self.assertEqual(libs.parse(UCRTBASE), {"library": "ucrtbase.dll", "exports": ["free", "malloc"]})

    def test_rejects_an_export_before_exports(self):
        with self.assertRaises(ValueError):
            libs.parse("LIBRARY \"ucrtbase.dll\"\nfree\nEXPORTS\nmalloc\n")

    def test_rejects_a_file_with_no_library_line(self):
        with self.assertRaises(ValueError):
            libs.parse("EXPORTS\nfree\n")

    def test_rejects_a_second_library_line(self):
        with self.assertRaises(ValueError):
            libs.parse("LIBRARY \"a.dll\"\nLIBRARY \"b.dll\"\nEXPORTS\nfree\n")


class ValidateTest(unittest.TestCase):
    def rejects(self, stem, library, exports):
        with self.assertRaises(ValueError):
            libs.validate(stem, {"library": library, "exports": exports})

    def test_accepts_a_sorted_list_for_the_file_name(self):
        libs.validate("ucrtbase", libs.parse(UCRTBASE))

    def test_accepts_a_library_name_in_another_case(self):
        libs.validate("kernel32", {"library": "KERNEL32.dll", "exports": ["ExitProcess"]})

    def test_rejects_a_library_that_does_not_match_the_file_name(self):
        self.rejects("ucrtbase", "msvcrt.dll", ["free"])

    def test_rejects_a_library_that_is_not_a_dll(self):
        self.rejects("ucrtbase", "ucrtbase", ["free"])

    def test_rejects_no_exports(self):
        self.rejects("ucrtbase", "ucrtbase.dll", [])

    def test_rejects_an_unsorted_list(self):
        self.rejects("ucrtbase", "ucrtbase.dll", ["malloc", "free"])

    def test_rejects_a_name_twice(self):
        self.rejects("ucrtbase", "ucrtbase.dll", ["free", "free"])

    def test_rejects_a_name_that_is_not_a_c_identifier(self):
        self.rejects("ucrtbase", "ucrtbase.dll", ["free", "malloc@8"])

    def test_rejects_a_data_export(self):
        self.rejects("ucrtbase", "ucrtbase.dll", ["_environ DATA"])


class RenderTest(unittest.TestCase):
    def test_writes_only_the_library_and_the_exports(self):
        self.assertEqual(
            libs.render(libs.parse(UCRTBASE)),
            "LIBRARY \"ucrtbase.dll\"\nEXPORTS\nfree\nmalloc\n",
        )


if __name__ == "__main__":
    unittest.main()
