# TidyTap direct-distribution release

`0.1.1` is distributed as a Developer ID-signed, Apple-notarized DMG. The
repository never contains a certificate, private key, Apple ID, app-specific
password, App Store Connect API key, or a notarytool profile export.

Both preview and public DMGs include an `Applications` shortcut and a short
bilingual `Install TidyTap.txt` note. Drag `TidyTap.app` onto the shortcut
(`TidyTap.app`을 Applications 폴더로 드래그) to install it.

## Local ad-hoc preview

Build a Release-optimized package without a Developer ID signing identity:

```sh
Scripts/package-preview-dmg.sh
```

The script creates the pair together at
`build/artifacts/TidyTap-<version>-preview-adhoc/`. It uses a local ad-hoc
signature: the embedded helper is signed first, then the parent app is sealed.
Before publication it verifies the helper and parent app, mounts the DMG
read-only, copies the app to an isolated temporary location, and verifies both
signatures again. Its `.sha256` sidecar
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
`Contents/MacOS/TidyTapHelper` independently against the configured Developer ID team,
creates the DMG, then signs the **DMG container itself** with that identity and
a secure timestamp. It verifies the DMG's signature, Developer ID authority,
Team ID, and timestamp before submitting that exact DMG to notarytool. It then
waits for acceptance, staples and validates the ticket, assesses the DMG with
Gatekeeper, and writes a SHA-256 sidecar next to the DMG. Every build and
verification step runs in a unique
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

For a no-network regression check of the release ordering and fail-closed
publication boundary, run:

```sh
Scripts/test-release-dmg-workflow.sh
```

It is a static check only: it does not build, sign, notarize, install, or
publish an artifact.

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

## GitHub Actions release automation

The repository includes a tag-only release workflow in
`.github/workflows/release-dmg.yml`. It runs on a `vMAJOR.MINOR.PATCH` tag and
can be retried from Actions with `workflow_dispatch` by entering the existing
tag in the `tag` field. The workflow checks that the tag commit is an ancestor
of `origin/main`, that the tag version equals Xcode's `MARKETING_VERSION`, and
that the arm64 runner exposes a macOS 26 or newer SDK. It then reuses
`Scripts/package-release-dmg.sh` and verifies the mounted DMG contains the
versioned app, the executable plain `TidyTapHelper`, and the LaunchAgent plist
that points at that helper.

The workflow creates or resumes a draft GitHub Release only after all build,
signing, notarization, staple, Gatekeeper, checksum, and bundle-content checks
pass. It replaces assets only while that release remains a draft, then
publishes the draft only after both the DMG and its `.sha256` sidecar upload.
An already published release with the same tag is never overwritten and causes
the workflow to fail clearly. A failed upload leaves a draft that a later
workflow_dispatch run for the same tag can safely resume.

The release workflow uses the `release` GitHub environment. Configure these
environment secrets before the first real tag run; the workflow does not
create or upload them:

| Secret | Purpose |
| --- | --- |
| `TIDYTAP_DEVELOPMENT_TEAM` | Apple Team ID used by the project signing config |
| `TIDYTAP_DEVELOPER_ID_APPLICATION` | Exact `Developer ID Application: ... (TEAMID)` identity name |
| `TIDYTAP_DEVELOPER_ID_CERTIFICATE_P12_BASE64` | Base64 export of the Developer ID certificate and private key |
| `TIDYTAP_DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password for that P12 export |
| `TIDYTAP_NOTARY_API_KEY_P8_BASE64` | Base64 App Store Connect API private key for `notarytool` |
| `TIDYTAP_NOTARY_KEY_ID` | App Store Connect API key ID |
| `TIDYTAP_NOTARY_ISSUER_ID` | App Store Connect API issuer ID |

Use an environment required reviewer for the first release job and keep the
secrets scoped to this repository's release environment. The job imports the
certificate into a temporary keychain, stores a fixed CI-only notary profile
(`tidytap-ci-notary`) in that keychain, writes the ignored local xcconfig, and
deletes the keychain, decoded files, config, and notes in an `always()` cleanup
step. The local `notarytool` profile name is not itself a hosted-runner
credential.

Pull requests use `.github/workflows/ci.yml`, which runs tests and static
release-order checks without any signing or notarization secrets. The
`macos-26` GitHub-hosted arm64 runner is selected to match this project's
`ARCHS = arm64` and `MACOSX_DEPLOYMENT_TARGET = 26.0`; the workflow checks the
actual SDK before building. The GitHub-hosted runner label and available Xcode
images can change, so a runner or SDK failure should be treated as an explicit
compatibility update rather than silently switching to a self-hosted machine.

The `0.1.1` app and embedded worker marketing versions are recorded in the
project on this branch. Create `v0.1.1` only from the corresponding main
commit after the remaining product acceptance checks; this automation branch
does not create a tag or release.
