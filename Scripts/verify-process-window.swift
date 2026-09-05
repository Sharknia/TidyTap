import CoreGraphics
import Darwin
import Foundation

guard CommandLine.arguments.count == 4,
      let processID = Int(CommandLine.arguments[1]),
      let expectedContentWidth = Double(CommandLine.arguments[2]),
      let expectedContentHeight = Double(CommandLine.arguments[3]) else {
    fputs("usage: verify-process-window <pid> <content-width> <content-height>\n", stderr)
    exit(2)
}

guard let windowInfo = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)
        as? [[String: Any]] else {
    fputs("Could not read the Core Graphics window list.\n", stderr)
    exit(1)
}

func integer(_ value: Any?) -> Int? {
    (value as? NSNumber)?.intValue
}

func number(_ value: Any?) -> Double? {
    (value as? NSNumber)?.doubleValue
}

let ownerPIDKey = kCGWindowOwnerPID as String
let layerKey = kCGWindowLayer as String
let boundsKey = kCGWindowBounds as String
let nameKey = kCGWindowName as String

let ownedLayerZero = windowInfo.filter {
    integer($0[ownerPIDKey]) == processID && integer($0[layerKey]) == 0
}
let normalWindows = ownedLayerZero.filter { window in
    guard let bounds = window[boundsKey] as? [String: Any],
          let width = number(bounds["Width"]),
          let height = number(bounds["Height"]) else {
        return false
    }
    // AppKit also publishes menu-related 30 px surfaces at layer zero. Those
    // are not normal application windows and were the original false signal.
    return width >= 100 && height >= 100
}

guard normalWindows.count == 1,
      let bounds = normalWindows[0][boundsKey] as? [String: Any],
      let width = number(bounds["Width"]),
      let height = number(bounds["Height"]) else {
    let summary = ownedLayerZero.map { window -> String in
        let name = window[nameKey] as? String ?? "<unnamed>"
        return "\(name):\(window[boundsKey] ?? "<no-bounds>")"
    }.joined(separator: ", ")
    fputs(
        "Expected exactly one normal layer-0 window for PID \(processID); " +
            "found \(normalWindows.count). Owned layer-0 windows: \(summary)\n",
        stderr
    )
    exit(1)
}

let widthMatches = abs(width - expectedContentWidth) <= 4
// CGWindow reports the frame including the title bar; the requested AppKit
// content height is therefore the lower bound rather than the exact frame.
let heightMatches = height >= expectedContentHeight && height <= expectedContentHeight + 64
guard widthMatches && heightMatches else {
    fputs(
        "Unexpected normal window frame: \(Int(width))x\(Int(height)); " +
            "expected content near \(Int(expectedContentWidth))x\(Int(expectedContentHeight)).\n",
        stderr
    )
    exit(1)
}

print(
    "Verified one normal layer-0 window for PID \(processID): " +
        "\(Int(width))x\(Int(height)) frame for " +
        "\(Int(expectedContentWidth))x\(Int(expectedContentHeight)) content."
)
