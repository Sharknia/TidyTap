import AppKit

let application = NSApplication.shared
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate
withExtendedLifetime(applicationDelegate) {
    application.run()
}
