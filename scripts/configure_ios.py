#!/usr/bin/env python3
"""Set signing identities without editing the Xcode project by hand."""
import argparse
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--team', required=True, help='10-character Apple Developer Team ID')
parser.add_argument('--bundle-id', required=True, help='An app identifier owned by that team')
parser.add_argument('--app-group', help='Defaults to group.<bundle-id>')
args = parser.parse_args()
if not re.fullmatch(r'[A-Z0-9]{10}', args.team):
    parser.error('--team must contain 10 uppercase letters/digits')
if not re.fullmatch(r'[A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z0-9-]+){2,}', args.bundle_id):
    parser.error('--bundle-id must be a reverse-domain identifier without wildcards')
group = args.app_group or 'group.' + args.bundle_id
if not re.fullmatch(r'group\.[A-Za-z0-9.-]+', group):
    parser.error('invalid --app-group')
path = Path(__file__).resolve().parents[1] / 'ios/Config/App.xcconfig'
path.write_text(
    '// Signing configuration; no private keys are stored here.\n'
    f'TJ_BUNDLE_ID = {args.bundle_id}\n'
    f'TJ_APP_GROUP = {group}\n'
    'CODE_SIGN_STYLE = Automatic\n'
    f'DEVELOPMENT_TEAM = {args.team}\n', encoding='utf-8')
print('Updated app, extension, and shared App Group signing configuration.')
