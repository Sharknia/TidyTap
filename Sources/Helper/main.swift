import AppKit

let application = NSApplication.shared
let applicationDelegate = HelperAppDelegate()
application.delegate = applicationDelegate
withExtendedLifetime(applicationDelegate) {
    application.run()
}
