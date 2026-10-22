#!/usr/bin/env python3
"""Choose an installed Xcode 27.1+ on a macOS CI runner."""
import re
import subprocess
from pathlib import Path

choices = []
for app in Path('/Applications').glob('Xcode*.app'):
    tool = app / 'Contents/Developer/usr/bin/xcodebuild'
    if not tool.is_file():
        continue
    text = subprocess.check_output([str(tool), '-version'], text=True)
    match = re.search(r'Xcode (\d+)(?:\.(\d+))?', text)
    if match:
        version = (int(match[1]), int(match[2] or 0))
        if version >= (27, 1):
            choices.append((version, app))
if not choices:
    raise SystemExit('This runner has no Xcode 27.1+. Use an updated macOS image or a self-hosted Mac.')
version, app = max(choices, key=lambda value: value[0])
subprocess.run(['sudo', 'xcode-select', '--switch', str(app / 'Contents/Developer')], check=True)
print('Selected', app.name)
