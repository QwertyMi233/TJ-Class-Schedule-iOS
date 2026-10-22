#!/usr/bin/env python3
"""Run native tests on every available iOS 27 iPhone/iPad simulator.

The installed simulator set is recorded in a report; it is not proof that every
physical device supported by Apple has been tested.
"""
import json
import os
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / 'dist/ios-tests'
out.mkdir(parents=True, exist_ok=True)
inventory = json.loads(subprocess.check_output(
    ['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], text=True, timeout=60))
selected = []
for runtime, devices in inventory['devices'].items():
    if not re.search(r'\.iOS-27(?:-|$)', runtime):
        continue
    for device in devices:
        if device.get('isAvailable') and device['name'].startswith(('iPhone', 'iPad')):
            selected.append((runtime, device))
if not selected:
    raise SystemExit('No iOS 27 iPhone/iPad simulator is installed. Install an iOS 27 runtime in Xcode Settings → Platforms.')
# Use existing booted devices rather than XCTest clones; the hosted iOS 27
# runtime's Instruments service can fail to bless a freshly cloned simulator.
if os.environ.get('IOS_TEST_ALL') != '1':
    phones = [x for x in selected if x[1]['name'].startswith('iPhone')]
    tablets = [x for x in selected if x[1]['name'].startswith('iPad')]
    selected = phones[:1] + tablets[:1]
results = []
for runtime, device in selected:
    print('Testing', device['name'], runtime, flush=True)
    identifier = device['udid']
    log = out / (identifier + '.log')
    result_bundle = out / (identifier + '.xcresult')
    if result_bundle.exists():
        raise SystemExit('A result bundle already exists; move dist/ios-tests aside before rerunning.')
    command = ['xcodebuild', '-workspace', 'ios/Runner.xcworkspace', '-scheme', 'Runner',
               '-configuration', 'Debug', '-sdk', 'iphonesimulator',
               '-destination', 'id=' + identifier, '-resultBundlePath', str(result_bundle),
               '-parallel-testing-enabled', 'NO', '-maximum-concurrent-test-simulator-destinations', '1',
               'test', 'CODE_SIGN_IDENTITY=-']
    with log.open('w') as output:
        try:
            run = subprocess.run(command, cwd=root, stdout=output, stderr=subprocess.STDOUT, timeout=480)
            status = 'passed' if run.returncode == 0 else 'failed'
        except subprocess.TimeoutExpired:
            status = 'timed_out'
    results.append({'runtime': runtime, 'device': device['name'], 'udid': identifier, 'status': status})
    (out / 'matrix.json').write_text(json.dumps(results, ensure_ascii=False, indent=2))
    if status != 'passed':
        detail = log.read_text(errors='replace')
        print('\n'.join(detail.splitlines()[-70:]), flush=True)
        # A build/destination failure cannot be fixed by choosing another screen size.
        if 'Test Suite' not in detail and 'Test suite' not in detail:
            break
    if device.get('state') == 'Shutdown':
        subprocess.run(['xcrun', 'simctl', 'shutdown', identifier], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
if any(item['status'] != 'passed' for item in results):
    raise SystemExit('Some simulator tests failed. Inspect dist/ios-tests.')
print('Passed on', len(results), 'installed simulator configurations. Physical device acceptance is still required.')
