# CapsLockProbe

`CapsLockProbe` is a macOS-only technical spike for the TidyTap Caps Lock contract. It is intentionally **read-only by default and in the supplied CLI**: no command in this package invokes the mutation routines. It exists to inspect the live state and show the exact safe plan that a future helper integration may execute only after a separately stored activation backup is available.

## Safety contract

- HID usage `0x700000039` (Caps Lock) is paired only with `0x70000006d` (F18).
- Apply refuses if Caps Lock already has any other mapping.
- Apply appends only that pair; it retains every unrelated HID mapping.
- Restore removes only that exact pair.
- Symbolic hotkey `60` is set to the F18 entry while all other entries are retained.
- Restore replaces hotkey 60 with its saved backup only when its present value still equals the TidyTap F18 entry. A user change after activation is reported as a conflict and is never overwritten.

The core contains explicit `SystemProbe.apply` and `SystemProbe.restore` routines to prove the proposed operating-system calls, but the executable does not expose them. Those routines set the complete `UserKeyMapping` property payload, and write only after their in-memory conflict checks. The F18 hotkey value uses virtual keycode `79` with modifier mask `8388608`, read from the supported macOS 26.6.2 target during this read-only spike. Do not call them from an ad-hoc REPL against a personal machine. Integration must first provide durable backup storage and user confirmation.

## Build and tests

```sh
cd Spikes/CapsLockProbe
swift build
swift test
swift run caps-lock-probe inspect
swift run caps-lock-probe plan-apply
```

`inspect` and both `plan-*` commands read the current HID/defaults state only. They never write `hidutil` properties or defaults.

## Manual validation protocol (future controlled integration)

1. On the target Mac, save `hidutil property --get UserKeyMapping` and `defaults export com.apple.symbolichotkeys -` outside this package. Record the target's macOS build.
2. Verify exactly two input sources are enabled. Confirm Caps Lock has no existing mapping. If it does, stop: do not overwrite it.
3. In a disposable test account or after a verified backup, invoke the future helper's explicit Apply action once. Re-inspect and confirm every old HID entry remains plus only Caps Lock→F18, and that only `AppleSymbolicHotKeys[60]` changed.
4. Set input source switching to F18 and test 20 taps plus a 5-second hold. Each tap must switch once; the hold must not enable Caps Lock, type uppercase, or repeat switching.
5. Change hotkey 60 manually after activation, then request Restore. It must report a conflict and leave that new user value untouched.
6. Repeat activation without changing hotkey 60, then restore. Confirm only Caps Lock→F18 is removed, the saved hotkey-60 value returns, and unrelated HID and hotkey entries are unchanged.
7. Run the full test suite again and archive the before/after exports with the validation report. Do not proceed to UI implementation until this passes on macOS 26.6.2.

## Important integration note

The MVP plan requires `/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u` to refresh the keyboard shortcut after a defaults write. This spike intentionally does not invoke it; manual validation must establish whether it works without administrator or accessibility permission before the Caps Lock feature is accepted.
