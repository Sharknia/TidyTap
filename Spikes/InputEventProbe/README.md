# InputEventProbe

`InputEventProbe` is a disposable, pure-Swift macOS diagnostic for TidyTap MVP stage 0. It uses only public Core Graphics, AppKit, and Accessibility APIs. It does not use IOHID/private APIs, change system settings, access the network, or observe/store keyboard text and pointer coordinates.

The default mode is listen-only. It reports only the event kind and the minimum button/scroll fields needed to validate the frozen MVP rules:

- a non-continuous event with a line delta is a `discrete-mouse` candidate;
- continuous scroll with a direct phase or a recently observed public gesture is `trackpad`;
- momentum is `trackpad` only when linked to that gesture stream;
- all other continuous events are `unknown` and must remain unchanged in the product.

This is a behavioral classifier, not a hardware identity API. Core Graphics does not expose a public per-event device identifier here. The result therefore supports only the exact stage-0 hardware set and must not be generalized without a new decision.

## Build and test

```sh
cd Spikes/InputEventProbe
swift build
swift test
```

## Permissions

The observe-only probe requires **Input Monitoring** permission for the terminal (or the built executable). Add it at **System Settings > Privacy & Security > Input Monitoring**, quit the host process completely, and relaunch it. The probe only checks permission and exits with instructions when it is absent; it never opens Settings or requests a permission on its own.

`--synthesize-navigation` additionally requires **Accessibility** permission. The flag is deliberately opt-in. Without it the event tap is listen-only and never consumes or synthesizes input.

Permission checks:

- observe-only: `CGPreflightListenEventAccess()`;
- navigation: both listen access and `CGPreflightPostEventAccess()`;
- focused-window validation: public Accessibility `kAXFocusedWindowAttribute`.

## Run

```sh
# Safe default: observe only; Ctrl-C to stop
swift run InputEventProbe

# Timed sample with a final aggregate summary
swift run InputEventProbe --duration 30

# Explicitly exercise Safari/Finder navigation
swift run InputEventProbe --synthesize-navigation
```

Navigation mode recognizes Core Graphics button 3 as back and button 4 as forward. It posts `Command-[` or `Command-]` only when Safari (`com.apple.Safari`) or Finder (`com.apple.finder`) is the active application and Accessibility confirms a focused window. It sends once on the first down, suppresses repeats until up, and consumes the matching down/up pair. All buttons in all other apps pass through unchanged.

## Exact quantitative manual protocol

Before testing, use the supported MacBook Pro `Mac15,6` on macOS 26.6.2 (`25G83`), connect the VXE Mouse 1K Dongle, and make both the built-in trackpad and Apple Magic Trackpad available. Quit Scroll Reverser and do not run TidyTap at the same time. Start in observe-only mode and retain only aggregate pass/fail counts; the probe itself never writes an event log.

### Scroll classification gate

1. On the VXE mouse, turn the vertical wheel **50 notches in each direction**. Every event must report `class=discrete-mouse`; any VXE event reported as `trackpad`/`unknown` (which the product would pass through) is a failure.
2. On the built-in trackpad, perform **20 gestures in each vertical direction** and **20 gestures in each horizontal direction**, allowing momentum to complete. Every scroll and momentum event must report `class=trackpad`; any event classified `discrete-mouse` is a failure.
3. Repeat step 2 on the Apple Magic Trackpad: **20 gestures in each vertical direction** and **20 gestures in each horizontal direction**, including momentum. Any `discrete-mouse` classification is a failure.
4. Alternate between one VXE wheel action and one trackpad gesture for **20 device transitions**. A transition passes only when the VXE event remains `discrete-mouse` and every trackpad event remains `trackpad`.
5. The gate passes only with **zero misclassifications**: no trackpad event would be inverted and no VXE wheel event would pass through. On any failure, stop stage 0 and obtain approval for a revised scope/technical approach before building UI.

The frozen plan separately requires each trackpad's direction-by-direction 20 gesture coverage and the 20 alternations. Do not replace these counts with a duration-only run.

### Side-button identity

1. In observe-only mode, press each VXE side button separately and confirm matching down/up lines.
2. The physical back button must report `number=3`; the physical forward button must report `number=4`.
3. If and only if the hardware reports the two buttons reversed, change the two code constants. Do not add calibration UI.

### Safari/Finder navigation gate

Run with `--synthesize-navigation` only after the observed button numbers are known.

1. In an active, focused Safari window, press each button briefly **20 times**, then hold each button for **2 seconds 5 times**. Each press/hold must navigate exactly once.
2. Repeat the same **20 short presses and 5 two-second holds per button** in an active, focused Finder window.
3. Repeat in Safari and Finder with no available back/forward history. There must be no error and no other action.
4. Repeat in another foreground app. No navigation keystroke may be synthesized and the original down/up events must pass through.
5. Verify that an inactive Safari/Finder window and Safari/Finder without a focused window are not navigated.

### Permission states

For Input Monitoring and Accessibility separately, verify **denied**, **allowed**, and **allowed then revoked** states. Denied/revoked access must cause startup/tap failure or navigation refusal, never event modification. After allowing again, the probe must work without reinstallation. Permission changes normally require quitting and relaunching the probe/terminal process.

## Interpreting output

`verticalLines` and `horizontalLines` are Core Graphics line deltas. `phase` and `momentum` are public bit fields. Gesture lines contain only an AppKit event type. Button lines contain only number, direction, repeat state, and whether the pair was consumed. There are intentionally no cursor coordinates, window titles, URLs, keyboard events, or typed text.

The 750 ms gesture-link window is an explicit spike hypothesis, not an accepted production constant. The hardware protocol above determines whether it is viable. If any continuous VXE wheel events occur or any legitimate trackpad stream becomes `unknown`, the required response is to stop and revisit the technical approach—not silently broaden inversion.
