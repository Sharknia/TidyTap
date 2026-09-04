import Foundation
import CapsLockProbeCore

func usage() {
    print("Usage: caps-lock-probe inspect | plan-apply | plan-restore")
    print("All commands are read-only. Apply/restore are deliberately not exposed until manual validation authorizes integration.")
}

do {
    switch CommandLine.arguments.dropFirst().first {
    case "inspect":
        let snapshot = try SystemProbe.inspect()
        print("HID mappings: \(snapshot.mappings)")
        print("Symbolic hotkey 60: \(snapshot.hotkeys[SymbolicHotkey60.identifier].map(String.init(describing:)) ?? "<unset>")")
    case "plan-apply":
        let snapshot = try SystemProbe.inspect()
        let planned = try HIDMappingMerger.apply(to: snapshot.mappings)
        print("Would set HID mappings: \(planned)")
        print("Would set symbolic hotkey 60 to F18 while preserving \(snapshot.hotkeys.count - (snapshot.hotkeys["60"] == nil ? 0 : 1)) other hotkeys.")
    case "plan-restore":
        let snapshot = try SystemProbe.inspect()
        print("Would remove only \(HIDMapping.tidyTapCapsLock) from \(snapshot.mappings.count) HID mappings.")
        print("Restore needs the activation backup and will refuse if hotkey 60 is no longer TidyTap's F18 entry.")
    default: usage()
    }
} catch { fputs("error: \(error.localizedDescription)\n", stderr); exit(1) }
