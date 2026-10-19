# Run from the repository root: python3 -m unittest bench/test_machine.py

import datetime
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import machine


class MachineTest(unittest.TestCase):
    def test_slug_names_a_directory(self):
        self.assertEqual(machine.slug("Apple M5 Pro"), "apple-m5-pro")
        self.assertEqual(machine.slug("Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz"), "intel-r-core-tm-i7-9750h-cpu-2-60ghz")
        self.assertEqual(machine.slug("  "), "unknown")

    def test_reads_the_power_source_from_pmset(self):
        self.assertEqual(machine.power_from_pmset("Now drawing from 'AC Power'\n -InternalBattery-0"), "ac")
        self.assertEqual(machine.power_from_pmset("Now drawing from 'Battery Power'\n"), "battery")
        self.assertEqual(machine.power_from_pmset(""), "unknown")

    def test_reads_low_power_mode_from_pmset(self):
        self.assertFalse(machine.low_power_from_pmset("System-wide power settings:\n lowpowermode         0\n"))
        self.assertTrue(machine.low_power_from_pmset(" lowpowermode 1\n"))
        self.assertIsNone(machine.low_power_from_pmset(" sleep 1\n"))

    def test_reads_linux_files(self):
        self.assertEqual(machine.memory_from_meminfo("MemTotal:       16384 kB\nMemFree: 1 kB\n"), 16384 * 1024)
        self.assertEqual(machine.chip_from_cpuinfo("processor\t: 0\nmodel name\t: AMD Ryzen 9 7950X\n"), "AMD Ryzen 9 7950X")
        self.assertEqual(machine.power_from_supplies([("Battery", "0"), ("Mains", "1")]), "ac")
        self.assertEqual(machine.power_from_supplies([("Mains", "0")]), "battery")
        self.assertEqual(machine.power_from_supplies([]), "unknown")

    def test_this_machine_has_every_field(self):
        found = machine.machine(datetime.date(2026, 10, 19))
        self.assertEqual(found["date"], "2026-10-19")
        self.assertEqual(sorted(found), ["chip", "date", "low_power_mode", "memory_bytes", "model", "os", "power", "slug"])
        self.assertIn(found["power"], ["ac", "battery", "unknown"])


if __name__ == "__main__":
    unittest.main()
