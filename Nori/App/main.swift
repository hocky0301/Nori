import AppKit

// Explicit entry point: there is no storyboard, so we must install the delegate ourselves.
let app = NSApplication.shared
let delegate = NoriApp()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
