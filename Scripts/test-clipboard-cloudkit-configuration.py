#!/usr/bin/env python3
"""실제 서명/계정 없이 릴리즈 메타데이터 거부 조건을 검사한다."""
import copy
import datetime
import importlib.util
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('cloudkit_configuration',
    Path(__file__).with_name('verify-clipboard-cloudkit-configuration.py'))
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class CloudKitConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime.datetime(2026, 11, 13)
        self.info = {'TidyTapCloudKitContainerIdentifier': 'iCloud.synthetic', 'CFBundleIdentifier': 'test.synthetic'}
        self.claims = {
            'com.apple.developer.icloud-container-identifiers': ['iCloud.synthetic'],
            'com.apple.developer.icloud-services': ['CloudKit'],
            'com.apple.application-identifier': 'TESTTEAM01.test.synthetic',
            'com.apple.developer.team-identifier': 'TESTTEAM01',
            'com.apple.developer.icloud-container-environment': 'Production',
            'com.apple.developer.aps-environment': 'production',
        }
        self.profile = {'Entitlements': copy.deepcopy(self.claims), 'TeamIdentifier': ['TESTTEAM01'],
                        'ProvisionsAllDevices': True, 'ExpirationDate': datetime.datetime(2030, 1, 1)}

    def test_matching_synthetic_claims(self):
        checker.validate_claims(self.info, self.claims, self.profile, 'TESTTEAM01', self.now)

    def test_profile_mismatches_fail_closed(self):
        for key, value in [
            ('com.apple.developer.icloud-container-identifiers', []),
            ('com.apple.developer.icloud-container-identifiers', 'iCloud.synthetic'),
            ('com.apple.developer.aps-environment', 'development'),
            ('com.apple.application-identifier', 'OTHER.test.synthetic'),
            ('com.apple.developer.icloud-container-environment', 'NotProduction'),
        ]:
            with self.subTest(key=key, value=value):
                profile = copy.deepcopy(self.profile)
                profile['Entitlements'][key] = value
                with self.assertRaises(ValueError):
                    checker.validate_claims(self.info, self.claims, profile, 'TESTTEAM01', self.now)
        for key, value in [('ExpirationDate', datetime.datetime(2020, 1, 1)),
                           ('ProvisionsAllDevices', False), ('TeamIdentifier', ['OTHERTEAM1'])]:
            profile = copy.deepcopy(self.profile); profile[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                checker.validate_claims(self.info, self.claims, profile, 'TESTTEAM01', self.now)

    def test_local_preview_is_allowed_but_release_without_profile_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / 'TidyTap.app'
            (app / 'Contents').mkdir(parents=True)
            info = app / 'Contents/Info.plist'
            info.write_bytes(plistlib.dumps({'CFBundleIdentifier': 'test.synthetic'}))
            self.assertEqual(checker.inspect(app, False)['configuration'], 'local-only')
            with self.assertRaises(ValueError):
                checker.inspect(app, True)
            info.write_bytes(plistlib.dumps(self.info))
            with self.assertRaises(ValueError):
                checker.inspect(app, True)


if __name__ == '__main__':
    unittest.main()
