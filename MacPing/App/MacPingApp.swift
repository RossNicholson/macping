import SwiftUI

@main
struct MacPingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The windows and the menu bar item are managed by AppDelegate, so
        // MacPing can keep pinging in the menu bar with its window closed.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appInfo) {
                    Button("About MacPing") { appDelegate.show(.about) }
                }
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { appDelegate.show(.settings) }
                        .keyboardShortcut(",", modifiers: .command)
                }
                CommandGroup(replacing: .newItem) {
                    Button("New Monitor") {
                        appDelegate.show()
                        appDelegate.monitor.add()
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    Button("Add Hosts…") { appDelegate.show(.addHosts) }
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                }
                CommandMenu("Monitor") {
                    Button("Start All") { appDelegate.monitor.startAll() }
                        .keyboardShortcut("r", modifiers: .command)
                    Button("Stop All") { appDelegate.monitor.stopAll() }
                        .keyboardShortcut(".", modifiers: .command)
                    Divider()
                    Button("Traceroute…") { appDelegate.showTraceroute("") }
                        .keyboardShortcut("t", modifiers: .command)
                    Button("Status History") { appDelegate.showHistory() }
                        .keyboardShortcut("y", modifiers: .command)
                    Divider()
                    Button("Favourites…") { appDelegate.show(.favorites) }
                        .keyboardShortcut("d", modifiers: .command)
                    Button("Aliases…") { appDelegate.show(.aliases) }
                }
            }
    }
}
