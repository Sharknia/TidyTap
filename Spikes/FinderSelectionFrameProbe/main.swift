import AppKit
import ApplicationServices
func attr(_ e: AXUIElement, _ key: String) -> CFTypeRef? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e,key as CFString,&v) == .success ? v : nil }
func element(_ v: CFTypeRef?) -> AXUIElement? { guard let v, CFGetTypeID(v)==AXUIElementGetTypeID() else{return nil};return unsafeBitCast(v,to:AXUIElement.self) }
func rect(_ e:AXUIElement)->String {
 guard let p=attr(e,kAXPositionAttribute), let s=attr(e,kAXSizeAttribute), CFGetTypeID(p)==AXValueGetTypeID(), CFGetTypeID(s)==AXValueGetTypeID() else{return "unavailable"}
 var point=CGPoint.zero;var size=CGSize.zero
 guard AXValueGetValue(unsafeBitCast(p,to:AXValue.self),.cgPoint,&point), AXValueGetValue(unsafeBitCast(s,to:AXValue.self),.cgSize,&size) else{return "invalid"}
 return "x=\(point.x) y=\(point.y) w=\(size.width) h=\(size.height)"
}
let app=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.finder").first!
let ax=AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(ax,0.2)
func dump() {
guard let focus=element(attr(ax,kAXFocusedUIElementAttribute)) else{print("no focus");exit(1)}
func info(_ e:AXUIElement)->String { "\(attr(e,kAXRoleAttribute) as? String ?? "?") id=\(attr(e,kAXIdentifierAttribute) as? String ?? "-") \(rect(e))" }
print("focus \(info(focus))")
if let w=element(attr(ax,kAXFocusedWindowAttribute)){print("window \(rect(w))")}
for key in [kAXSelectedChildrenAttribute,kAXSelectedRowsAttribute] {
 guard let selected=attr(focus,key) as? [AXUIElement] else{print("\(key): unavailable");continue}
 print("\(key): \(selected.count)")
 for e in selected.prefix(5) {
  print("item \(info(e))")
  for c in (attr(e,kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(2) {
   print(" child \(info(c))")
   for g in (attr(c,kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(3){print("  child \(info(g))")}
  }
 }
}

}

dump()
