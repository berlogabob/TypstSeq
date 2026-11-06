#!/usr/bin/env python3
"""Capture read-only P30 process CPU and battery counters around a transfer."""
import argparse
import json
import re
import subprocess
import time
from pathlib import Path

ADB = str(Path.home() / 'Library/Android/sdk/platform-tools/adb')
SERIAL = 'XPH0219904001750'
PRODUCTION = 'org.tylog.tylog'
PACKAGE = 'org.tylog.tylog.profiletest'
INSTALL_TIME = '2026-11-05 15:27:02'


def adb(*args):
    return subprocess.check_output([ADB, '-s', SERIAL, 'shell', *args], text=True)


def production_install_time():
    output = adb('dumpsys', 'package', 'org.tylog.tylog')
    match = re.search(r'^\s*firstInstallTime=(.+?)\s*$', output, re.M)
    return match.group(1) if match else None


def check_install():
    if production_install_time() != INSTALL_TIME:
        raise ValueError('Production firstInstallTime missing or changed; device measurement refused')
    packages = adb('pm', 'list', 'packages').splitlines()
    all_packages = adb('pm', 'list', 'packages', '-u').splitlines()
    if (f'package:{PRODUCTION}' not in packages or
            f'package:{PRODUCTION}' not in all_packages or
            f'package:{PACKAGE}' not in packages):
        raise ValueError('Production or isolated package gate failed; device measurement refused')


def parse_proc_stat(output):
    fields = output[output.rfind(')') + 2:].split()
    return int(fields[11]) + int(fields[12]), int(fields[19])


def parse_battery(output):
    def field(name, pattern):
        match = re.search(r'^\s*' + name + r':\s*(' + pattern + r')\s*$', output, re.M | re.I)
        if not match:
            raise ValueError(f'Battery {name} unavailable')
        return match.group(1)

    state = {'status': int(field('status', r'\d+'))}
    for name in ('ac', 'usb', 'wireless'):
        state[name] = field(name + ' powered', 'true|false').lower() == 'true'
    return int(field('charge counter', r'-?\d+')), state


def preflight():
    installed_at = production_install_time()
    packages = adb('pm', 'list', 'packages').splitlines()
    all_packages = adb('pm', 'list', 'packages', '-u').splitlines()
    isolated = f'package:{PACKAGE}' in packages
    active = f'package:{PRODUCTION}' in packages
    known = f'package:{PRODUCTION}' in all_packages
    if (active and not known) or (installed_at is not None and not active):
        state = 'inconsistent'
    elif active:
        state = 'installed'
    elif known:
        state = 'uninstalled'
    else:
        state = 'missing'
    charge, battery = parse_battery(adb('dumpsys', 'battery'))
    return dict(production_first_install_time=installed_at,
                expected_first_install_time=INSTALL_TIME,
                profiletest_installed=isolated, production_package_state=state,
                package_gate_passed=state == 'installed' and installed_at == INSTALL_TIME and isolated,
                charge_uah=charge, battery=battery)


def capture():
    check_install()
    try:
        pid = int(adb('pidof', PACKAGE).strip())
        ticks, start = parse_proc_stat(adb('cat', f'/proc/{pid}/stat'))
        hz = int(adb('getconf', 'CLK_TCK').strip())
        charge, state = parse_battery(adb('dumpsys', 'battery'))
        if hz <= 0:
            raise ValueError('Invalid clock rate')
        return dict(pid=pid, start_ticks=start, cpu_ticks=ticks, hz=hz,
                    monotonic=time.monotonic(), charge_uah=charge, charging=state)
    finally:
        check_install()


def delta(before, after):
    if (before['pid'], before['start_ticks']) != (after['pid'], after['start_ticks']):
        raise ValueError('Test process restarted during measurement')
    elapsed = after['monotonic'] - before['monotonic']
    if elapsed <= 0 or before['hz'] != after['hz'] or after['cpu_ticks'] < before['cpu_ticks']:
        raise ValueError('Invalid measurement interval or CPU counter')
    cpu = (after['cpu_ticks'] - before['cpu_ticks']) / before['hz']
    return dict(elapsed_seconds=elapsed, cpu_seconds=cpu,
                average_cpu_percent=100 * cpu / elapsed,
                charge_delta_uah=after['charge_uah'] - before['charge_uah'],
                battery_status_before=before['charging'], battery_status_after=after['charging'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['preflight', 'begin', 'end'])
    parser.add_argument('state', type=Path, nargs='?', help='local temporary measurement state file')
    args = parser.parse_args()
    if args.action == 'preflight':
        if args.state is not None:
            parser.error('preflight takes no state file')
        result = preflight()
        print(json.dumps(result, indent=2))
        raise SystemExit(0 if result['package_gate_passed'] else 1)
    if args.state is None:
        parser.error('begin and end require a state file')
    if args.action == 'begin':
        sample = capture()
        with args.state.open('x') as stream:
            json.dump(sample, stream)
        print('Measurement started')
    else:
        before = json.loads(args.state.read_text())
        print(json.dumps(delta(before, capture()), indent=2))


if __name__ == '__main__':
    main()
