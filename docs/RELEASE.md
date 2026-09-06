# TidyTap direct-distribution release

TidyTap public releases use Developer ID-signed, Apple-notarized DMGs. The
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

## Local Developer ID preview

When a fresh local worker needs the same Developer ID identity used by the
release build, pass the already-existing ignored signing config explicitly:

```sh
Scripts/package-preview-dmg.sh --developer-id-config /absolute/path/to/Config/LocalSigning.xcconfig
```

The supplied file is read in place; it is never copied or printed. This mode
requires a valid `TIDYTAP_DEVELOPMENT_TEAM` and matching
`TIDYTAP_DEVELOPER_ID_APPLICATION` identity already available in Keychain. It
passes that config to `xcodebuild -xcconfig` while keeping the Release target's
`Config/Signing.xcconfig` settings, so the app and plain `TidyTapHelper` retain
the Release signing identifiers, hardened runtime, and timestamping. The
script does not ad-hoc re-sign either executable in this mode.

Before publishing a local candidate, it verifies the configured Developer ID
certificate chain and team on the app, plain worker, and signed DMG; verifies
the app resource seal; mounts the DMG read-only; copies its app to an isolated
temporary location; and repeats the app, worker, and seal checks there. It
writes and verifies a SHA-256 sidecar. The output is commit-specific and never
overwrites a prior candidate:
`build/artifacts/TidyTap-<version>-preview-developer-id-<commit>/`.

Developer ID previews require a clean tracked and untracked worktree (ignored
signing configuration and build output are allowed). The script captures the
full HEAD before building and uses its first 12 characters in the filename.
It archives that commit into the temporary candidate's `sources/` directory
and builds the project there, so ignored Swift sources cannot enter the build.
The external signing config is still passed in place with `-xcconfig`, and
derived data remains inside the temporary candidate.
Immediately before publishing the pair, it checks that HEAD is unchanged and
the worktree is still clean. If either changed, it discards the temporary
candidate without consuming that output name. Commit source changes before
running this mode. The default ad-hoc mode does not require a clean worktree.

This is intentionally a local packaging preview. It does not install the app,
create tags or GitHub releases, or submit, staple, or validate a notarization.
It verifies signing continuity only; it does not claim to preserve or test
Accessibility or Input Monitoring consent. Compare designated requirements on
the resulting candidate separately when that acceptance evidence is needed.

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

For the preview-mode CLI, signature, non-release, and no-overwrite contracts:

```sh
Scripts/test-preview-dmg-workflow.sh
```

This combines static and missing-argument checks with disposable Git fixtures
that exercise the source guard and publication boundary using a fake build.
It tests clean success, ignored source exclusion from the committed snapshot
alongside allowed ignored build/config files, tracked/staged/untracked dirt before building, and
tracked/untracked edits or HEAD changes before publication. It does not run
a real build, sign, mount, install, notarize, or publish a release artifact.

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

For `0.1.1`, the maintainer requested publication after the completed automated
checks and distribution-artifact verification, with physical wheel, clean-account
TCC, and reboot checks remaining outstanding. Record those limits in the release
notes; successful signing or packaging is not evidence that manual checks passed.

## TidyTap Release skill

Use the versioned `.agents/skills/tidytap-release/SKILL.md` or the installed
`tidytap-release` skill for release requests. It reports the current project
version, latest published release, latest tag, branch state, worktree state,
and changes since the last release before recommending a semantic version.
The user selects the exact version before any version edit, tag, push, or public
release.

After the version is selected, the skill validates the clean final main commit,
reuses the local signing configuration and Keychain notary profile, invokes
`Scripts/package-release-dmg.sh`, and checks the exact DMG with
`Scripts/verify-release-artifact.sh`. Only a verified candidate may be tagged
and uploaded to a new GitHub Release. Existing tags and published releases are
never moved or overwritten.
