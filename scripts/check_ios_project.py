#!/usr/bin/env python3
"""Check configuration consistency. This does not replace an Xcode build."""
import json
import plistlib
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
ios = root / 'ios'
def check(condition, message):
    if not condition:
        raise SystemExit('FAILED: ' + message)

for path in ios.rglob('*.plist'):
    if not any(p in path.parts for p in ['Pods', 'ephemeral']):
        plistlib.loads(path.read_bytes())
for path in root.rglob('*.xcprivacy'):
    plistlib.loads(path.read_bytes())
app = plistlib.loads((ios / 'Runner/Info.plist').read_bytes())
check(app.get('TJAppGroup') == '$(TJ_APP_GROUP)', 'app App Group setting')
check(app.get('UIApplicationSceneManifest') is not None, 'UIScene lifecycle configuration')
check(app.get('FlutterDeepLinkingEnabled') is False, 'native widget URL routing')
check('NSLocationWhenInUseUsageDescription' in app, 'location permission description')
check('fetch' in app.get('UIBackgroundModes', []), 'background refresh mode')
identifiers = {'icu.tjschedule.refresh.tasks', 'icu.tjschedule.refresh.star'}
check(set(app.get('BGTaskSchedulerPermittedIdentifiers', [])) == identifiers, 'background identifiers')
delegate = (ios / 'Runner/AppDelegate.swift').read_text()
for identifier in identifiers:
    check(identifier in delegate, 'AppDelegate registration for ' + identifier)
for path in ['Runner/Runner.entitlements', 'TJWidgets/TJWidgets.entitlements']:
    ent = plistlib.loads((ios / path).read_bytes())
    check(ent.get('com.apple.security.application-groups') == ['$(TJ_APP_GROUP)'], path)
widget = plistlib.loads((ios / 'TJWidgets/Info.plist').read_bytes())
check(widget['TJAppGroup'] == app['TJAppGroup'], 'extension App Group setting')
check(widget['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension', 'widget extension type')
project = (ios / 'Runner.xcodeproj/project.pbxproj').read_text()
check('com.apple.product-type.app-extension' in project and 'dstSubfolderSpec = 13' in project, 'embedded widget target')
check('FlutterGeneratedPluginSwiftPackage' not in project, 'CocoaPods configuration is consistent')
check(set(re.findall(r'IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);', project)) == {'17.0'}, 'deployment targets')
check('TARGETED_DEVICE_FAMILY = "1,2"' in project, 'iPhone and iPad support')
app_id = re.search(r'^TJ_BUNDLE_ID\s*=\s*(.+)$', (ios / 'Config/App.xcconfig').read_text(), re.M)
check(app_id is not None, 'app bundle identifier')
for package in ['canvas_session_bridge', 'tj_ios_bridge']:
    text = (root / 'packages' / package / 'pubspec.yaml').read_text()
    check('ios:' in text and 'pluginClass:' in text, package + ' registration')
    check((root / 'packages' / package / 'ios' / (package + '.podspec')).is_file(), package + ' podspec')
check((root / 'packages/canvas_session_bridge/ios/Resources/canvas_rotation.js').read_bytes() ==
      (root / 'packages/canvas_session_bridge/android/src/main/assets/canvas_rotation.js').read_bytes(), 'Canvas rotation script parity')
icons = ios / 'Runner/Assets.xcassets/AppIcon.appiconset'
for entry in json.loads((icons / 'Contents.json').read_text())['images']:
    if entry.get('filename'):
        check((icons / entry['filename']).is_file(), 'app icon ' + entry['filename'])
print('iOS project configuration checks passed. Native compilation and device testing are still required.')
