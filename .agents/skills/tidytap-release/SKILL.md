---
name: tidytap-release
description: Prepare and publish a TidyTap macOS release through the local Developer ID signing and notarized DMG workflow when the user asks to release, distribute, or publish TidyTap.
---

# TidyTap Release

Use this skill only for an explicit TidyTap release request such as “배포하자”, “릴리즈하자”, “DMG 배포”, or “release TidyTap”. It uses the release Mac’s existing Developer ID identity and notarytool profile. It does not create App Store Connect credentials, GitHub Actions signing secrets, or a new distribution service.

## Version gate

Before any tag, push, public release, or signing mutation, read the current project versions, latest published GitHub release, latest tag, current branch, worktree status, and commits since the last release. Report the distinction between the project version and the latest published version.

Recommend a version from the change set: patch for compatible fixes, minor for compatible features, and major for breaking changes. For a `0.x` project, use the same rule as a recommendation and explain the choice briefly. The user chooses the exact version. Ask for that version and wait unless the user already supplied one explicitly, such as “release 0.1.2”.

Until the user has selected the exact version, do not change version files, create or move tags, push branches or tags, create releases, or change signing configuration. Preparation that does not mutate release state is allowed.

## Preflight after version selection

Validate that the chosen value is `MAJOR.MINOR.PATCH`, is greater than the latest published version, has no existing published tag or release, and matches the app and embedded worker `MARKETING_VERSION`. Check that the release starts from a clean, reviewed branch. If the worktree is dirty, the branch is not the intended release branch, or the selected commit is not the final main commit, stop and explain the exact correction needed.

Preserve unrelated user changes. Never force-move an existing tag, overwrite a published release, or reuse an artifact merely because its filename matches. If an artifact directory already exists, verify its source commit, app version, plain helper layout, LaunchAgent plist, signature, notarization ticket, Gatekeeper assessment, and checksum; otherwise leave it untouched and build a fresh candidate.

## Local release workflow

Use the ignored `Config/LocalSigning.xcconfig` and existing Keychain identity/profile. Do not print or copy their values. Confirm the Developer ID certificate and notary profile are present and usable before starting the build; if they are expired or missing, request only the required credential action and stop.

Update only the project version/build metadata and current release documentation required for the selected version. Run the repository tests and the relevant release-order checks. Reuse `Scripts/package-release-dmg.sh`; do not duplicate its signing, notarization, stapling, Gatekeeper, checksum, or atomic publication logic.

After packaging, run `Scripts/verify-release-artifact.sh` against the exact DMG. It must confirm the expected app version, top-level `TidyTap.app`, executable plain `Contents/MacOS/TidyTapHelper`, `Contents/Library/LaunchAgents/com.sharknia.TidyTap.Agent.plist` targeting that helper, and the `.sha256` sidecar. Keep the DMG and sidecar together as the candidate.

Only after local verification passes should you create the tag on the verified final main commit, push the tag, and create the GitHub Release with the DMG and sidecar. Use a new release for the selected version; never overwrite a published release. If publication fails, leave the existing published state unchanged and report the exact safe retry action. Do not create a public release from an unverified or partially produced candidate.

Report the selected version, tag commit, branch/PR state, artifact paths, signature/notarization/Gatekeeper/checksum results, release URL, and any remaining manual acceptance checks. A release request authorizes the standard workflow after the user has selected the version; ask again only for a genuinely new credential, destructive conflict, or missing external approval.
