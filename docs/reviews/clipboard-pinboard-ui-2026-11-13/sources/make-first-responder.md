<!--
{
  "availability" : [
    "macOS: -"
  ],
  "documentType" : "symbol",
  "framework" : "AppKit",
  "identifier" : "/documentation/AppKit/NSWindow/makeFirstResponder(_:)",
  "metadataVersion" : "0.1.0",
  "role" : "Instance Method",
  "symbol" : {
    "kind" : "Instance Method",
    "modules" : [
      "AppKit"
    ],
    "preciseIdentifier" : "c:objc(cs)NSWindow(im)makeFirstResponder:"
  },
  "title" : "makeFirstResponder(_:)"
}
-->

# makeFirstResponder(_:)

Attempts to make a given responder the first responder for the window.

```
func makeFirstResponder(_ responder: NSResponder?) -> Bool
```

## Parameters

`responder`

The responder to set as the window’s first responder. `nil` makes the window its first responder.

## Return Value

<doc://com.apple.documentation/documentation/Swift/true> when the operation is successful; otherwise, <doc://com.apple.documentation/documentation/Swift/false>.

## Discussion

If `responder` isn’t already the first responder, this method first sends a [`resignFirstResponder()`](/documentation/AppKit/NSResponder/resignFirstResponder()) message to the object that is the first responder. If that object refuses to resign, it remains the first responder, and this method immediately returns <doc://com.apple.documentation/documentation/Swift/false>. If the current first responder resigns, this method sends a [`becomeFirstResponder()`](/documentation/AppKit/NSResponder/becomeFirstResponder()) message to `responder`. If `responder` does not accept first responder status, the `NSWindow` object becomes first responder; in this case, the method returns <doc://com.apple.documentation/documentation/Swift/true> even if `responder` refuses first responder status.

If `responder` is `nil`, this method still sends [`resignFirstResponder()`](/documentation/AppKit/NSResponder/resignFirstResponder()) to the current first responder. If the current first responder refuses to resign, it remains the first responder and this method immediately returns <doc://com.apple.documentation/documentation/Swift/false>. If the current first responder returns <doc://com.apple.documentation/documentation/Swift/true> from [`resignFirstResponder()`](/documentation/AppKit/NSResponder/resignFirstResponder()), the window is made its own first responder and this method returns <doc://com.apple.documentation/documentation/Swift/true>.

The Application Kit framework uses this method to alter the first responder in response to mouse-down events; you can also use it to explicitly set the first responder from within your program. The `responder` object is typically an `NSView` object in the window’s view hierarchy. If this method is called explicitly, first send [`acceptsFirstResponder`](/documentation/AppKit/NSResponder/acceptsFirstResponder) to `responder`, and do not call [`makeFirstResponder(_:)`](/documentation/AppKit/NSWindow/makeFirstResponder(_:)) if [`acceptsFirstResponder`](/documentation/AppKit/NSResponder/acceptsFirstResponder) returns <doc://com.apple.documentation/documentation/Swift/false>.

Use [`initialFirstResponder`](/documentation/AppKit/NSWindow/initialFirstResponder) to the set the first responder to be used when the window is brought onscreen for the first time.

## See Also

[`func becomeFirstResponder() -> Bool`](/documentation/AppKit/NSResponder/becomeFirstResponder())

Notifies the receiver that it’s about to become first responder in its [`NSWindow`](/documentation/AppKit/NSWindow).

[`func resignFirstResponder() -> Bool`](/documentation/AppKit/NSResponder/resignFirstResponder())

Notifies the receiver that it’s been asked to relinquish its status as first responder in its window.



---

Copyright &copy; 2026 Apple Inc. All rights reserved. | [Terms of Use](https://www.apple.com/legal/internet-services/terms/site.html) | [Privacy Policy](https://www.apple.com/privacy/privacy-policy)