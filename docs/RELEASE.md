# TidyTap direct-distribution release

`0.1.0` is distributed as a Developer ID-signed, Apple-notarized DMG. The
repository never contains a certificate, private key, Apple ID, app-specific
password, App Store Connect API key, or a notarytool profile export.

## Local unsigned preview

Build a Release-optimized package without any signing identity:

```sh
Scripts/package-preview-dmg.sh
```

The script creates the pair together at
`build/artifacts/TidyTap-<version>-preview-unsigned/`. Its `.sha256` sidecar
contains only the DMG basename, so the two files can be copied to another
directory and checked there with `shasum -a 256 -c <sidecar>`. It is only
suitable for local development: Gatekeeper will not accept it as a public
distribution package. The generated files are ignored by Git.

## Prerequisites for a public DMG

The release operator needs all of the following on the release Mac:

1. A valid **Developer ID Application** signing identity, including its private
   key, in the login keychain.
2. A notarytool keychain profile that is already able to authenticate with
   Apple's notary service. Keep its name local; do not export credentials into
   this repository.
3. A local config created by copying the example:

   ```sh
   cp Config/LocalSigning.xcconfig.example Config/LocalSigning.xcconfig
   ```

   Fill only these values in the ignored local file:

   ```xcconfig
   TIDYTAP_DEVELOPMENT_TEAM = ABCDE12345
   TIDYTAP_DEVELOPER_ID_APPLICATION = Developer ID Application: Legal Name (ABCDE12345)
   TIDYTAP_NOTARYTOOL_KEYCHAIN_PROFILE = local-notary-profile-name
   ```

`TIDYTAP_DEVELOPMENT_TEAM` must match the Team ID in the Developer ID identity.
The profile name refers to credentials stored in Keychain, not to a file in the
repository.

## Build, sign, notarize, staple

Before creating a public candidate, check the project configuration:

```sh
Scripts/verify-release-build-settings.sh --require-local
```

Then run the one-shot release workflow:

```sh
Scripts/package-release-dmg.sh
```

It archives the Release scheme, verifies the outer app and embedded
`TidyTapHelper.app` independently against the configured Developer ID team,
creates the DMG, submits it to notarytool, waits for acceptance, staples and
validates the ticket, assesses the DMG with Gatekeeper, and writes a SHA-256
sidecar next to the DMG. Every build and verification step runs in a unique
temporary candidate directory. Only after all checks succeed does an atomic
rename publish the pair together at `build/artifacts/TidyTap-<version>/`.
An existing package directory is never overwritten.

Routine Xcode, codesign, notarytool, stapler, and Gatekeeper metadata is
captured rather than printed. On failure the script emits a short, path- and
credential-sanitized diagnostic excerpt with a concrete next check; it never
prints local config values, keychain credentials, or notarization secrets.

The workflow fails before archiving if any of the local config, Team ID,
Developer ID identity, or usable notarytool profile is absent. It does not
upload to GitHub or install the app.

## Final manual checks

After the script succeeds, retain the generated DMG and `.sha256` sidecar as
the exact candidate. Verify a copied pair, if needed, with:

```sh
Scripts/verify-dmg-sidecar.sh path/to/TidyTap-<version>.dmg
```

On the supported Mac and clean macOS user account, run
the acceptance checks in `docs/MVP_PLAN.md`, including first launch through
Gatekeeper. Only after those checks may a maintainer create the GitHub Release
and upload the two generated files.
