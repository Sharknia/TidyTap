#!/usr/bin/env python3
"""검토 후보의 서명·프로파일 메타데이터만 확인한다. 서버 동기화 시험은 아니다."""
import argparse
import datetime
import json
from pathlib import Path
import plistlib
import subprocess


def validate_claims(info, entitlements, profile, team, now=None):
    now = now or datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    identifier = info['TidyTapCloudKitContainerIdentifier']
    allowed = profile.get('Entitlements', {})
    app_id = entitlements.get('com.apple.application-identifier')
    environment = allowed.get('com.apple.developer.icloud-container-environment')
    def includes(values, value):
        return isinstance(values, list) and value in values
    checks = [
        includes(entitlements.get('com.apple.developer.icloud-container-identifiers'), identifier),
        includes(allowed.get('com.apple.developer.icloud-container-identifiers'), identifier),
        includes(entitlements.get('com.apple.developer.icloud-services'), 'CloudKit'),
        includes(allowed.get('com.apple.developer.icloud-services'), 'CloudKit'),
        bool(team) and includes(profile.get('TeamIdentifier'), team),
        entitlements.get('com.apple.developer.team-identifier') == team,
        profile.get('ProvisionsAllDevices') is True,
        bool(app_id) and app_id == allowed.get('com.apple.application-identifier'),
        bool(app_id) and app_id.endswith('.' + info['CFBundleIdentifier']),
        profile.get('ExpirationDate', datetime.datetime.min) > now,
        entitlements.get('com.apple.developer.icloud-container-environment') == 'Production',
        entitlements.get('com.apple.developer.aps-environment') == 'production',
        allowed.get('com.apple.developer.aps-environment') == 'production',
        environment == 'Production' or (isinstance(environment, list) and 'Production' in environment),
    ]
    if not all(checks):
        raise ValueError('CloudKit signature/profile metadata mismatch')


def inspect(app, require):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    identifier = info.get('TidyTapCloudKitContainerIdentifier', '')
    if not identifier or '$(' in identifier:
        if require:
            raise ValueError('CloudKit release requires a configured container and Developer ID profile')
        return {'configuration': 'local-only', 'server_sync': 'not_validated'}
    profile_path = app / 'Contents/embedded.provisionprofile'
    if not profile_path.is_file():
        raise ValueError('CloudKit release requires an embedded provisioning profile')
    subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(app)], capture_output=True, check=True)
    claim = subprocess.run(['/usr/bin/codesign', '--display', '--entitlements', '-', '--xml', str(app)],
                           capture_output=True, check=True)
    entitlements = plistlib.loads(claim.stdout)
    cms = subprocess.run(['/usr/bin/security', 'cms', '-D', '-i', str(profile_path)], capture_output=True, check=True)
    profile = plistlib.loads(cms.stdout)
    signature = subprocess.run(['/usr/bin/codesign', '-dvv', str(app)], capture_output=True, text=True, check=True)
    team = next((line.split('=', 1)[1] for line in signature.stderr.splitlines() if line.startswith('TeamIdentifier=')), '')
    validate_claims(info, entitlements, profile, team)
    return {'configuration': 'signed-cloudkit-metadata-matches', 'server_sync': 'not_validated'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('app', type=Path)
    parser.add_argument('--require-cloudkit', action='store_true')
    args = parser.parse_args()
    try:
        print(json.dumps(inspect(args.app, args.require_cloudkit)))
    except (ValueError, KeyError, TypeError, AttributeError, OSError, plistlib.InvalidFileException, subprocess.CalledProcessError):
        raise SystemExit('CloudKit signing configuration verification failed; no profile contents were logged.')
