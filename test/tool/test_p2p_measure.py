import unittest
from unittest.mock import patch

from tool.p2p_measure import capture, delta, parse_battery, parse_proc_stat


class MeasurementTest(unittest.TestCase):
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
        with patch('tool.p2p_measure.adb', side_effect=[package, '42', stat, '100', battery, package]) as call:
            sample = capture()
        self.assertEqual((sample['pid'], sample['cpu_ticks'], sample['charge_uah']), (42, 29, 5000))
        self.assertEqual(call.call_count, 6)
        with patch('tool.p2p_measure.adb', side_effect=[package, '42', stat, '100', battery, '']):
            with self.assertRaisesRegex(ValueError, 'firstInstallTime'):
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
