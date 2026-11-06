import unittest
from unittest.mock import patch

from tool.p2p_measure import capture, check_install, delta, parse_battery, parse_proc_stat, preflight


class MeasurementTest(unittest.TestCase):
    def test_preflight_reports_package_gate_and_battery_without_sampling_process(self):
        battery = 'AC powered: true\nUSB powered: false\nWireless powered: false\nstatus: 3\nCharge counter: 24000\n'
        with patch('tool.p2p_measure.adb', side_effect=['', 'package:org.tylog.tylog.profiletest\n', 'package:org.tylog.tylog.profiletest\n', battery]) as call:
            result = preflight()
        self.assertEqual(result['production_first_install_time'], None)
        self.assertFalse(result['package_gate_passed'])
        self.assertTrue(result['profiletest_installed'])
        self.assertEqual(result['charge_uah'], 24000)
        self.assertTrue(result['battery']['ac'])
        self.assertEqual(call.call_count, 4)
        with patch('tool.p2p_measure.adb', side_effect=['firstInstallTime=2026-11-05 15:27:02', 'package:org.tylog.tylog.profiletest\npackage:org.tylog.tylog\n', 'package:org.tylog.tylog.profiletest\npackage:org.tylog.tylog\n', battery]):
            self.assertTrue(preflight()['package_gate_passed'])
        with patch('tool.p2p_measure.adb', side_effect=['firstInstallTime=2026-11-05 15:27:02', 'package:org.tylog.tylog\n', 'package:org.tylog.tylog\n', battery]):
            self.assertFalse(preflight()['package_gate_passed'])

    def test_preflight_identifies_missing_uninstalled_and_inconsistent_production(self):
        battery = 'AC powered: true\nUSB powered: false\nWireless powered: false\nstatus: 4\nCharge counter: 20000\n'
        isolated = 'package:org.tylog.tylog.profiletest\n'
        production = 'package:org.tylog.tylog\n'
        cases = [
            ('', isolated, isolated, 'missing', False),
            ('', isolated, isolated + production, 'uninstalled', False),
            ('firstInstallTime=2026-11-05 15:27:02', isolated, isolated, 'inconsistent', False),
            ('firstInstallTime=2026-11-05 15:27:02', isolated + production, isolated + production, 'installed', True),
        ]
        for stamp, active, all_packages, state, passed in cases:
            with self.subTest(state=state), patch('tool.p2p_measure.adb', side_effect=[stamp, active, all_packages, battery]):
                result = preflight()
                self.assertEqual(result['production_package_state'], state)
                self.assertEqual(result['package_gate_passed'], passed)

    def test_sampling_gate_rejects_inconsistent_or_missing_packages(self):
        isolated = 'package:org.tylog.tylog.profiletest\n'
        production = 'package:org.tylog.tylog\n'
        stamp = 'firstInstallTime=2026-11-05 15:27:02'
        for active, known in ((isolated, isolated), (production, production),
                              (isolated + production, isolated)):
            with self.subTest(active=active, known=known), patch(
                'tool.p2p_measure.adb', side_effect=[stamp, active, known]
            ):
                with self.assertRaisesRegex(ValueError, 'package gate'):
                    check_install()
        with patch('tool.p2p_measure.adb', side_effect=[stamp, isolated + production, isolated + production]):
            check_install()

    def test_rejects_missing_or_changed_production_install_before_sampling(self):
        for output in ('', '    firstInstallTime=2026-11-05 15:27:03'):
            with self.subTest(output=output), patch('tool.p2p_measure.adb', return_value=output) as call:
                with self.assertRaisesRegex(ValueError, 'firstInstallTime'):
                    capture()
                self.assertEqual(call.call_count, 1)

    def test_capture_checks_install_on_both_sides_of_sample(self):
        package = 'firstInstallTime=2026-11-05 15:27:02'
        stat = '42 (test) S ' + ' '.join(str(x) for x in range(4, 23))
        battery = 'AC powered: true\nUSB powered: false\nWireless powered: false\nstatus: 2\nCharge counter: 5000\n'
        packages = 'package:org.tylog.tylog\npackage:org.tylog.tylog.profiletest\n'
        with patch('tool.p2p_measure.adb', side_effect=[package, packages, packages, '42', stat, '100', battery, package, packages, packages]) as call:
            sample = capture()
        self.assertEqual((sample['pid'], sample['cpu_ticks'], sample['charge_uah']), (42, 29, 5000))
        self.assertEqual(call.call_count, 10)
        with patch('tool.p2p_measure.adb', side_effect=[package, packages, packages, '42', stat, '100', battery, '']):
            with self.assertRaisesRegex(ValueError, 'firstInstallTime'):
                capture()
        with patch('tool.p2p_measure.adb', side_effect=[package, packages, packages, '42', stat, '100', battery, package, packages, '']):
            with self.assertRaisesRegex(ValueError, 'package gate'):
                capture()

    def test_proc_stat_handles_spaces_and_parentheses(self):
        self.assertEqual(parse_proc_stat('42 (test (worker)) S ' + ' '.join(str(x) for x in range(4, 23))), (29, 22))

    def test_battery_records_power_sources_and_status(self):
        self.assertEqual(parse_battery('  AC powered: true\n  USB powered: false\n  Wireless powered: false\n  status: 2\n  Charge counter: 5000\n'),
                         (5000, {'status': 2, 'ac': True, 'usb': False, 'wireless': False}))
        with self.assertRaises(ValueError):
            parse_battery('status: 2')

    def test_delta_rejects_process_restart_and_reports_cpu_and_charge(self):
        before = dict(pid=5, start_ticks=7, cpu_ticks=100, hz=100, monotonic=10, charge_uah=5000, charging='2')
        after = dict(pid=5, start_ticks=7, cpu_ticks=250, hz=100, monotonic=13, charge_uah=4800, charging='2')
        self.assertEqual(delta(before, after), dict(elapsed_seconds=3, cpu_seconds=1.5, average_cpu_percent=50, charge_delta_uah=-200, battery_status_before='2', battery_status_after='2'))
        after['start_ticks'] = 8
        with self.assertRaisesRegex(ValueError, 'restarted'):
            delta(before, after)


if __name__ == '__main__':
    unittest.main()
