**Evidence**

- Source visual truth: `/Users/crobat/.codex/generated_images/01a06cb1-420d-7423-b2f7-c2334115b2a6/exec-cc3cfd22-5aeb-4fce-85db-78816df09e54.png` (1536×1024 px).
- Source window crop: `work/design-reference-window.png` (760×800 px).
- Implementation: `work/liquid-glass-normal.png` (1120×1300 px, 560×650 pt at 2×).
- Normalized implementation: `work/design-implementation-normalized.png` (689×800 px).
- Combined comparison: `work/design-qa-comparison.png`.
- Compared state: Korean, light appearance, Caps Lock enabled, Accessibility and Input Monitoring allowed.

The reference includes rendered window chrome and a surrounding concept canvas. The implementation capture contains the production settings content only. The implementation is taller because the approved correction requires two explicit permission rows below both mouse functions.

**Verified Scope**

This QA pass verifies layout, localized copy, permission-state presentation, action wiring, and native AppKit hierarchy/geometry. It does not claim visual verification of the live composited glass material.

**Findings**

- No actionable P0, P1, or P2 mismatch remains within the verified layout/state/native-hierarchy scope. The implementation preserves the reference hierarchy: compact icon/title header, keyboard card, combined mouse card, general card, native switches, and compact footer.
- Typography uses system fonts at native control sizes with the same title/caption hierarchy. Korean and English copies fit without truncation.
- Spacing is compact and consistent at 560×650 pt. The mouse permission block is grouped below both mouse feature rows.
- Production colors are semantic AppKit colors. Allowed, missing, and not-checked states have distinct icon, text, and accessibility values.
- The reviewed app icon is loaded from the existing `TidyTap.icns`; feature icons are SF Symbols.
- Copy explicitly states that Accessibility is needed for wheel reversal and side buttons, while Input Monitoring is needed for wheel reversal only.

**Material Capture Limitation**

`NSGlassEffectView` and `NSVisualEffectView` do not composite their live backdrop in a never-ordered host window. The PNG renderer therefore uses a documented semantic system-color fallback surface while instantiating the same production `SettingsViewController`, icon, controls, copy, layout, and state logic. These PNGs are valid layout/state evidence, but they are not screenshots of the live glass material. The native path is covered separately by tests asserting an `NSVisualEffectView` root, three `NSGlassEffectView` cards, correctly assigned `contentView` objects, and nonzero descendant geometry. A live material screenshot was intentionally not taken because opening a window was prohibited.

**Focused State Evidence**

- `work/liquid-glass-both-denied.png`: both permission rows show missing independently.
- `work/liquid-glass-ax-allowed-im-denied.png`: Accessibility shows allowed while Input Monitoring shows missing.
- English equivalents use the `-en.png` suffix and come from the same string catalog.

The original full-view captures are readable enough to evaluate the permission labels, status colors, buttons, and switch alignment, so separate cropped detail images were not needed.

**Comparison History**

- Initial P0 capture issue: native effect views produced a black/blank cache image and `contentView` had conflicting manual edge constraints.
- Fix: removed constraints that duplicated `NSGlassEffectView`'s own content constraints, added native nonzero-geometry tests, and made the renderer explicitly use semantic fallback surfaces for the never-ordered capture.
- Post-fix evidence: the six Korean/English PNGs above show the complete production hierarchy and all requested permission states.

**Implementation Checklist**

- [x] Production native glass hierarchy and semantic colors.
- [x] Mouse permission rows below both mouse functions.
- [x] Independent UUID-routed permission actions.
- [x] No automatic feature enablement and no Caps Lock permission row.
- [x] Korean and English offscreen state fixtures.
- [x] Hostless layout, action, and permission-state tests.

**Follow-up Polish**

- P3: visually inspect live glass translucency and switch accent when a user explicitly permits opening the app window.

final result: passed
