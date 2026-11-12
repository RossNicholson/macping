import XCTest
import SwiftUI
@testable import MacPing

/// Renders the window, the panel and the other screens with demo monitors, for
/// the website and for checking the design, and draws the app icon. Skipped
/// unless SCREENSHOTS (or ICON_DIR) names an output folder: `make screenshots`,
/// `make icon`.
@MainActor
final class ScreenshotTests: XCTestCase {
    private func outputFolder(_ variable: String) throws -> URL {
        guard let dir = ProcessInfo.processInfo.environment[variable], !dir.isEmpty else {
            throw XCTSkip("Set \(variable) to render")
        }
        let url = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Demo settings in their own defaults, so the real app's are untouched
    private func demo() -> Monitor {
        let suite = "MacPingScreenshots"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let monitor = Monitor(settings: AppSettings(defaults: defaults), libraryURL: nil)
        Demo.load(into: monitor)
        return monitor
    }

    func testRenderWindow() throws {
        let out = try outputFolder("SCREENSHOTS")
        for dark in [false, true] {
            let monitor = demo()
            try Snapshot.png(MainView().environment(monitor).environment(Router()),
                             size: NSSize(width: 1080, height: 700), dark: dark,
                             to: out.appendingPathComponent("window\(dark ? "-dark" : "-light").png"))
        }
        let empty = demo()
        empty.replaceAll(with: [], start: false)
        for _ in 1..<4 { empty.add(start: false) }
        try Snapshot.png(MainView().environment(empty).environment(Router()), size: NSSize(width: 900, height: 600),
                         to: out.appendingPathComponent("window-empty.png"))
    }

    func testRenderPanel() throws {
        let out = try outputFolder("SCREENSHOTS")
        for dark in [false, true] {
            let monitor = demo()
            try Snapshot.panel(dark: dark, to: out.appendingPathComponent("panel\(dark ? "-dark" : "-light").png")) {
                MenuBarPanel(openWindow: {}, openHistory: {}, close: {}).environment(monitor)
            }
        }
    }

    func testRenderScreens() throws {
        let out = try outputFolder("SCREENSHOTS")
        let monitor = demo()
        for dark in [false, true] {
            try Snapshot.png(SettingsView().environment(monitor), size: NSSize(width: 560, height: 640), dark: dark,
                             to: out.appendingPathComponent("settings\(dark ? "-dark" : "").png"))
        }
        try Snapshot.png(HistoryView().environment(monitor), size: NSSize(width: 640, height: 520),
                         to: out.appendingPathComponent("history.png"))
        let trace = TracerouteSession(host: "1.1.1.1")
        trace.showDemo(address: "1.1.1.1", hops: Demo.hops)
        try Snapshot.png(TracerouteView(session: trace), size: NSSize(width: 560, height: 520),
                         to: out.appendingPathComponent("traceroute.png"))
        try Snapshot.png(FavoritesSheet().environment(monitor), size: NSSize(width: 500, height: 340),
                         to: out.appendingPathComponent("favorites.png"))
        try Snapshot.png(AddHostsSheet().environment(monitor), size: NSSize(width: 460, height: 330),
                         to: out.appendingPathComponent("add-hosts.png"))
    }

    func testRenderMascot() throws {
        let out = try outputFolder("SCREENSHOTS")
        try Snapshot.png(Mascot(size: 560, disc: nil).frame(width: 560, height: 560), size: NSSize(width: 560, height: 560),
                         to: out.appendingPathComponent("mascot.png"), transparent: true, exactPixels: true)
        let moods = HStack(spacing: 16) {
            Mascot(mood: .happy, size: 120)
            Mascot(mood: .worried, size: 120, disc: AppColors.coral)
            Mascot(mood: .happy, size: 120, bounce: 7)
            Mascot(size: 40)
        }.padding(20).background(AppColors.ground)
        try Snapshot.png(moods, size: NSSize(width: 560, height: 160), to: out.appendingPathComponent("mascot-moods.png"))
        let icons = HStack(spacing: 12) {
            Image(nsImage: MenuBarIcon.image(alert: false))
            Image(nsImage: MenuBarIcon.image(alert: true))
            Image(nsImage: MenuBarIcon.image(alert: false)).scaleEffect(4).frame(width: 90, height: 70)
            Image(nsImage: MenuBarIcon.image(alert: true)).scaleEffect(4).frame(width: 90, height: 70)
        }.padding(10).background(Color.white)
        try Snapshot.png(icons, size: NSSize(width: 260, height: 90), to: out.appendingPathComponent("menubar-icon.png"))
    }

    /// The app icon: the mascot on a mint squircle, at every size
    func testAppIcon() throws {
        let dir = try outputFolder("ICON_DIR")
        let sizes: [(String, CGFloat)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, pixels) in sizes {
            try Snapshot.png(AppIcon().frame(width: pixels, height: pixels), size: NSSize(width: pixels, height: pixels),
                             to: dir.appendingPathComponent("\(name).png"), transparent: true, exactPixels: true)
        }
    }
}

/// macOS icon grid: an 824/1024 rounded square with a soft shadow
private struct AppIcon: View {
    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            let tile = side * 824 / 1024
            ZStack {
                RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0xCDEFD9), AppColors.mint],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: tile, height: tile)
                    .shadow(color: .black.opacity(0.22), radius: side * 0.012, y: side * 0.01)
                Mascot(size: tile * 0.98, disc: nil)
            }
            .frame(width: side, height: side)
        }
    }
}
