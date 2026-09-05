import AppKit


final class NoriApp: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Menu-bar apps have no Dock icon; LSUIElement in Info.plist takes care of that.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.togglePanel()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.willTerminate()
    }
}
