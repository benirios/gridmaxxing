import AppKit
import SwiftUI
import PrivateBridge
import ServiceManagement

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = Controller()
    private var item: NSStatusItem!
    private var setup: NSWindow?
    private var toggle: NSMenuItem!
    private var loginItem: NSMenuItem!
    private let loginPreference = "openAtLogin"
    private var loginRegistrationFailed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Mission Grid")
        let menu = NSMenu()
        let title = NSMenuItem(title: "Mission Grid", action: nil, keyEquivalent: "")
        menu.addItem(title)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Setup & handoff test…", action: #selector(showSetup), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        toggle = NSMenuItem(title: "Start navigation", action: #selector(toggleNavigation), keyEquivalent: "")
        toggle.target = self; menu.addItem(toggle)
        menu.addItem(.separator())
        loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self; menu.addItem(loginItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Mission Grid", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        item.menu = menu
        controller.menuChanged = { [weak self] in
            guard let self else { return }
            self.toggle.title = self.controller.enabled ? "Pause navigation" : "Start navigation"
            title.title = "Mission Grid · \(self.controller.gridColumns)×\(self.controller.gridRows)"
            self.toggle.isEnabled = !self.controller.starting
            self.item.button?.appearsDisabled = !self.controller.enabled
        }
        menu.autoenablesItems = false
        registerLoginItemIfWanted()
        controller.launch()
        showSetup()
    }

    private func registerLoginItemIfWanted() {
        let wanted = UserDefaults.standard.object(forKey: loginPreference) as? Bool ?? true
        if wanted && SMAppService.mainApp.status != .enabled && SMAppService.mainApp.status != .requiresApproval {
            do { try SMAppService.mainApp.register() }
            catch { loginRegistrationFailed = true; NSLog("Mission Grid login item: %@", error.localizedDescription) }
        }
        updateLoginItem()
    }

    private func updateLoginItem() {
        let status = SMAppService.mainApp.status
        loginItem.state = status == .enabled ? .on : .off
        loginItem.title = status == .requiresApproval ? "Open at Login (enable in System Settings)" :
            (loginRegistrationFailed ? "Open at Login (registration failed)" : "Open at Login")
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        do {
            if service.status == .enabled {
                try service.unregister()
                UserDefaults.standard.set(false, forKey: loginPreference)
            } else {
                try service.register()
                UserDefaults.standard.set(true, forKey: loginPreference)
            }
            loginRegistrationFailed = false
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
        updateLoginItem()
    }

    @objc func showSetup() {
        if setup == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 850),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Mission Grid"
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 640, height: 600)
            window.contentView = NSHostingView(rootView: SetupView(controller: controller))
            window.center()
            setup = window
        }
        NSApp.activate(ignoringOtherApps: true)
        setup?.makeKeyAndOrderFront(nil)
    }
    @objc private func toggleNavigation() { if controller.enabled { controller.pause() } else { showSetup(); controller.start() } }
    @objc private func quitApp() { controller.pause(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { controller.pause() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

if CommandLine.arguments.contains("--diagnose") {
    // Read-only: no anchors, trackpad listener, capture, permission prompts, or switches.
    print("Spaces API symbols: \(MGSpacesAvailable() ? "available" : "unavailable")")
    print("Trackpad API/device: \(MGTouchAvailable() ? "available" : "unavailable")")
    print("Accessibility: \(AXIsProcessTrusted() ? "granted" : "not granted")")
    print("Screen Recording: \(CGPreflightScreenCaptureAccess() ? "granted" : "not granted")")
    print("Open at Login: \(SMAppService.mainApp.status) (\(SMAppService.mainApp.status.rawValue))")
    do {
        let state = try Spaces().read()
        print("Layout: \(state.ids.count) desktops ready; current desktop \((state.ids.firstIndex(of: state.current) ?? 0) + 1)")
    } catch { print("Layout: \(error.localizedDescription)") }
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
