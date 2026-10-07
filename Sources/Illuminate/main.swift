import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu-bar only: no Dock icon, no main menu. Also set via LSUIElement in Info.plist.
app.setActivationPolicy(.accessory)
app.run()
