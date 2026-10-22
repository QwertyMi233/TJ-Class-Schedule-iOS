#!/usr/bin/env python3
"""Package an actually built iPhoneOS .app; never invent a binary from sources."""
import plistlib
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
app = root / 'build/ios/iphoneos/Runner.app'
if not (app / 'Runner').is_file():
    raise SystemExit('No device build found. Run flutter build ios --release --no-codesign first.')
if not (app / 'PlugIns/TJWidgets.appex').is_dir():
    raise SystemExit('Widget extension is missing; refusing to package an incomplete build.')
info = plistlib.loads((app / 'Info.plist').read_bytes())
if info.get('DTPlatformName') != 'iphoneos':
    raise SystemExit('A simulator build cannot be packaged as a device IPA.')
out = root / 'dist/TJ-Class-Schedule-iOS-unsigned.ipa'
out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(app.rglob('*')):
        if path.is_file():
            archive.write(path, 'Payload/Runner.app/' + path.relative_to(app).as_posix())
print(out)
print('Unsigned IPA: signing is required for installation on a standard iPhone or iPad.')
