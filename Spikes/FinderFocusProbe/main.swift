import AppKit
import ApplicationServices

func read(_ element: AXUIElement, _ name: String) -> (AXError, CFTypeRef?) {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return (error, value)
}

// Inspection mode reads Finder even when the tool runner activates Codex.
let candidate = CommandLine.arguments.contains("--inspect-finder")
    ? NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
    : NSWorkspace.shared.frontmostApplication
guard let app = candidate,
      app.bundleIdentifier == "com.apple.finder" else {
    print("PASS: Finder is not frontmost")
    exit(0)
}
let finder = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(finder, 0.2)
let (error, value) = read(finder, kAXFocusedUIElementAttribute)
guard error == .success, let value,
      CFGetTypeID(value) == AXUIElementGetTypeID() else {
    print("PASS: focus error=\(error.rawValue)")
    exit(0)
}
let focused = unsafeBitCast(value, to: AXUIElement.self)
var chain: [[String: String]] = []
var node: AXUIElement? = focused
for _ in 0..<8 {
    guard let current = node else { break }
    var info: [String: String] = [:]
    for key in [kAXRoleAttribute, kAXSubroleAttribute, kAXIdentifierAttribute] {
        let (status, value) = read(current, key)
        info[key] = status == .success ? (value as? String ?? "non-string") : "error:\(status.rawValue)"
    }
    chain.append(info)
    let (_, parent) = read(current, kAXParentAttribute)
    node = parent.flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? unsafeBitCast($0, to: AXUIElement.self) : nil }
}
let role = chain.first?[kAXRoleAttribute] ?? ""
let id = chain.first?[kAXIdentifierAttribute] ?? ""
let direct = (role == "AXOutline" && id == "ListView") ||
    (role == "AXList" && ["IconView", "GalleryView"].contains(id))
let column = role == "AXList" && chain.dropFirst().contains { $0[kAXIdentifierAttribute] == "ColumnView" }
print("\(direct || column ? "ALLOW" : "PASS"): \(chain)")
