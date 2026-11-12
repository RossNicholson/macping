import AppKit
import Observation
import SwiftUI

/// Owns the main window, the history and traceroute windows, and the menu
/// bar item. With the menu bar item on, closing the window keeps MacPing
/// pinging up there (no Dock icon); with it off, closing the window quits.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let monitor = Monitor()
    let router = Router()
    private var window: NSWindow?
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var tracerouteWindows: [NSWindow] = []
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        router.openHistory = { [weak self] in self?.showHistory() }
        router.openSettings = { [weak self] in self?.showSettings() }
        router.openTraceroute = { [weak self] host in self?.showTraceroute(host) }
        monitor.settings.onChange = { [weak self] in self?.applySettings() }

        // Don't open windows or start pinging when hosting unit tests
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        #if DEBUG
        // `-demo YES`: sample monitors for screenshots, no pinging
        if UserDefaults.standard.bool(forKey: "demo") {
            Demo.load(into: monitor)
        } else {
            monitor.restore(arguments: Array(CommandLine.arguments.dropFirst()))
        }
        #else
        monitor.restore(arguments: Array(CommandLine.arguments.dropFirst()))
        #endif
        applySettings()
        Task { await monitor.updater.checkSilent() }
        // Opened at login: start quietly in the menu bar
        if monitor.settings.showInMenuBar, Self.launchedAtLogin {
            NSApp.setActivationPolicy(.accessory)
        } else {
            show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { show() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !monitor.settings.showInMenuBar
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stopAll()
    }

    // MARK: - Windows

    func show(_ sheet: Router.Sheet? = nil) {
        NSApp.setActivationPolicy(.regular)
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let sheet { router.sheet = sheet }
    }

    private func makeWindow() -> NSWindow {
        let content = MainView()
            .environment(monitor)
            .environment(router)
            .frame(minWidth: 640, minHeight: 420)
        let window = Self.window(title: "MacPing", size: NSSize(width: 980, height: 680), content: content)
        window.contentMinSize = NSSize(width: 640, height: 420)
        window.delegate = self
        if !window.setFrameUsingName("MainWindow") { window.center() }
        window.setFrameAutosaveName("MainWindow")
        window.level = windowLevel
        return window
    }

    /// Keep on top covers every MacPing window, or the others would open behind the main one
    private var windowLevel: NSWindow.Level { monitor.settings.alwaysOnTop ? .floating : .normal }

    func showHistory() {
        NSApp.setActivationPolicy(.regular)
        let window = historyWindow ?? {
            let window = Self.window(title: "Status History", size: NSSize(width: 640, height: 520),
                                     content: HistoryView().environment(monitor))
            window.delegate = self
            if !window.setFrameUsingName("HistoryWindow") { window.center() }
            window.setFrameAutosaveName("HistoryWindow")
            window.level = windowLevel
            return window
        }()
        historyWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings() {
        NSApp.setActivationPolicy(.regular)
        let window = settingsWindow ?? {
            let window = Self.window(title: "MacPing Settings", size: NSSize(width: 560, height: 680),
                                     content: SettingsView().environment(monitor))
            window.delegate = self
            window.contentMinSize = NSSize(width: 520, height: 360)
            if !window.setFrameUsingName("SettingsWindow") { window.center() }
            window.setFrameAutosaveName("SettingsWindow")
            window.level = windowLevel
            return window
        }()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// A window per traceroute, so several can run side by side
    func showTraceroute(_ host: String) {
        NSApp.setActivationPolicy(.regular)
        let session = TracerouteSession(host: host)
        let window = Self.window(title: host.isEmpty ? "Traceroute" : "Traceroute to \(host)",
                                 size: NSSize(width: 560, height: 560),
                                 content: TracerouteView(session: session))
        window.delegate = self
        window.level = windowLevel
        // Beside the main window if there's room, else centred; more cascade from there
        if let last = tracerouteWindows.last {
            window.setFrameTopLeftPoint(NSPoint(x: last.frame.minX + 28, y: last.frame.maxY - 28))
        } else if let main = self.window, main.isVisible, let screen = main.screen?.visibleFrame,
                  main.frame.maxX + 12 + window.frame.width <= screen.maxX {
            window.setFrameTopLeftPoint(NSPoint(x: main.frame.maxX + 12, y: main.frame.maxY))
        } else {
            window.center()
        }
        tracerouteWindows.append(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func window<Content: View>(title: String, size: NSSize, content: Content) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        tracerouteWindows.removeAll { $0 === closing }
        if closing === historyWindow { historyWindow = nil }
        if closing === settingsWindow { settingsWindow = nil }
        // Back to a menu bar app once no windows are left: no Dock icon
        let anyLeft = [window, historyWindow, settingsWindow].compactMap { $0 }
            .contains { $0 !== closing && ($0.isVisible || $0.isMiniaturized) }
            || !tracerouteWindows.isEmpty
        if monitor.settings.showInMenuBar, !anyLeft {
            DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
        }
    }

    // MARK: - Settings

    private func applySettings() {
        let level = windowLevel
        ([window, historyWindow, settingsWindow] + tracerouteWindows).forEach { $0?.level = level }
        if monitor.settings.showInMenuBar {
            if statusBar == nil {
                statusBar = StatusBarController(monitor: monitor,
                                                openWindow: { [weak self] in self?.show() },
                                                openHistory: { [weak self] in self?.showHistory() })
            }
        } else {
            statusBar?.remove()
            statusBar = nil
            // Without the menu bar item there must be a way back: keep the Dock icon
            if window?.isVisible != true { show() }
        }
    }

    /// Whether macOS opened us as a login item. The launch event says so for
    /// older login items; for SMAppService ones the best signal is that the
    /// setting is on and the Mac has only just started up.
    private static var launchedAtLogin: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        if event?.eventID == kAEOpenApplication,
           event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            return true
        }
        return AppSettings.openAtLogin && ProcessInfo.processInfo.systemUptime < 180
    }
}

/// The menu bar item: the ball icon, with a count when hosts are down, and
/// the shared menu bar panel that drops down from it
@MainActor
final class StatusBarController {
    private let monitor: Monitor
    private let statusItem: NSStatusItem
    private let panel: MenuBarPanelController

    init(monitor: Monitor, openWindow: @escaping () -> Void, openHistory: @escaping () -> Void) {
        self.monitor = monitor
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        let panel = MenuBarPanelController(statusItem: statusItem)
        self.panel = panel
        panel.setContent {
            MenuBarPanel(openWindow: openWindow, openHistory: openHistory,
                         close: { [weak panel] in panel?.close() })
                .environment(monitor)
        }
        observe()
    }

    func remove() {
        panel.close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// Re-renders the icon whenever a host goes up or down
    private func observe() {
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.observe()
                self?.panel.fitToContent()
            }
        }
    }

    private func update() {
        guard let button = statusItem.button else { return }
        let down = monitor.downCount
        button.image = MenuBarIcon.image(alert: down > 0)
        button.attributedTitle = down > 0
            ? NSAttributedString(string: " \(down)", attributes: [.foregroundColor: NSColor.systemRed])
            : NSAttributedString(string: "")
        button.toolTip = down > 0 ? "\(down) host\(down == 1 ? " is" : "s are") down" : "MacPing: \(monitor.summary)"
    }
}
