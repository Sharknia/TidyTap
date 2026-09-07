import Foundation

let backend = CGEventTapBackend()
do {
    try backend.install(
        configuration: EventTapConfiguration(
            reverseMouseScroll: false,
            sideButtonNavigation: false,
            finderCutPasteEnabled: true
        ),
        captureSideButtons: false
    ) { _ in .passThrough }
    print("Finder cut/paste probe running. Press Control-C to stop.")
    RunLoop.main.run()
} catch {
    fputs("Could not install event tap: \(error)\n", stderr)
    exit(1)
}
