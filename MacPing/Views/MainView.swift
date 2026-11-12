import SwiftUI
import UniformTypeIdentifiers

/// Which sheet the main window is showing, and the other windows it can open.
/// The app delegate fills in the window openers.
@MainActor
@Observable
final class Router {
    enum Sheet: String, Identifiable {
        case addHosts, favorites, aliases, about
        var id: String { rawValue }
    }

    var sheet: Sheet?
    @ObservationIgnored var openHistory: () -> Void = {}
    @ObservationIgnored var openSettings: () -> Void = {}
    @ObservationIgnored var openTraceroute: (String) -> Void = { _ in }
}

struct MainView: View {
    @Environment(Monitor.self) private var monitor
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            TopBar()
            ProbeGrid()
                .padding([.horizontal, .bottom], 14)
        }
        .background(AppColors.ground)
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.openTraceroute) { router.openTraceroute($0) }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .addHosts: AddHostsSheet()
            case .favorites: FavoritesSheet()
            case .aliases: AliasesSheet()
            case .about: AboutSheet()
            }
        }
        .onDrop(of: [.fileURL, .plainText], isTargeted: nil) { providers in
            // A text file of hosts dropped on the window adds them all
            for provider in providers {
                if provider.canLoadObject(ofClass: URL.self) {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
                        Task { @MainActor in monitor.addMany(text) }
                    }
                } else if provider.canLoadObject(ofClass: String.self) {
                    _ = provider.loadObject(ofClass: String.self) { text, _ in
                        // A tile dropped between tiles isn't a list of hosts
                        guard let text, ProbeTile.draggedID(text) == nil else { return }
                        Task { @MainActor in monitor.addMany(text) }
                    }
                }
            }
            return true
        }
    }
}

/// The title, the mascot and the actions across the top of the window
private struct TopBar: View {
    @Environment(Monitor.self) private var monitor
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var monitor = monitor
        HStack(spacing: 12) {
            BouncingMascot(running: monitor.anyRunning, mood: monitor.downCount > 0 ? .worried : .happy, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.favoriteName ?? "MacPing")
                    .font(.display(28, relativeTo: .title))
                    .textCase(.uppercase)
                    .lineLimit(1)
                Text(monitor.summary)
                    .font(.mono(10.5))
                    .foregroundStyle(AppColors.secondaryText)
                    .contentTransition(.numericText())
            }
            .foregroundStyle(AppColors.text)
            Spacer(minLength: 12)

            PillButton(title: "Add", symbol: "plus", circle: AppColors.mint) { monitor.add() }
                .help("Add a monitor (⌘N). ⇧⌘N adds a list of hosts.")
            if monitor.anyRunning {
                PillButton(title: "Stop all", symbol: "stop.fill", circle: AppColors.coral) { monitor.stopAll() }
            } else {
                PillButton(title: "Start all", symbol: "play.fill", circle: AppColors.mint) { monitor.startAll() }
                    .disabled(!monitor.probes.contains { Target(parsing: $0.input) != nil })
            }

            Menu {
                Picker("Columns", selection: $monitor.columns) {
                    Text("Fit to window").tag(0)
                    Divider()
                    ForEach(1...8, id: \.self) { Text("\($0) column\($0 == 1 ? "" : "s")").tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                ToolbarCircle(symbol: "square.grid.2x2")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .help("Columns")

            Menu {
                if monitor.favorites.isEmpty {
                    Text("No favourites yet")
                } else {
                    ForEach(monitor.favorites) { favorite in
                        Button(favorite.name) { monitor.load(favorite) }
                    }
                }
                Divider()
                Button("Save these hosts as a favourite…") { router.sheet = .favorites }
                Button("Manage favourites…") { router.sheet = .favorites }
                Button("Manage aliases…") { router.sheet = .aliases }
            } label: {
                ToolbarCircle(symbol: "star")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .help("Favourites and aliases")

            HeaderIconButton(symbol: "point.topleft.down.to.point.bottomright.curvepath", help: "Traceroute (⌘T)") {
                router.openTraceroute("")
            }
            HeaderIconButton(symbol: "clock.arrow.circlepath", help: "Status history (⌘Y)") { router.openHistory() }
            HeaderIconButton(symbol: "gearshape", help: "Settings (⌘,)") { router.openSettings() }
            HeaderIconButton(symbol: "info", help: "About MacPing") { router.sheet = .about }
        }
        .padding(.horizontal, 18)
        .padding(.top, 38)
        .padding(.bottom, 14)
    }
}

/// A round icon like HeaderIconButton, as a menu's label
private struct ToolbarCircle: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppColors.text)
            .frame(width: 30, height: 30)
            .background(AppColors.surface, in: Circle())
            .contentShape(Circle())
    }
}

/// The monitors, filling the window like vmPing's grid. Each tile gets an equal
/// share of the space; when they'd get too small, the grid scrolls instead.
struct ProbeGrid: View {
    @Environment(Monitor.self) private var monitor
    static let spacing: CGFloat = 10
    static let minHeight: CGFloat = 150
    static let minWidth: CGFloat = 260

    var body: some View {
        GeometryReader { geometry in
            let count = max(1, monitor.probes.count)
            let columns = Self.columns(count: count, setting: monitor.columns, size: geometry.size)
            let rows = Int(ceil(Double(count) / Double(columns)))
            let fitted = (geometry.size.height - Self.spacing * CGFloat(rows - 1)) / CGFloat(rows)
            let height = max(Self.minHeight, fitted)
            let layout = Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: columns)
            let width = (geometry.size.width - Self.spacing * CGFloat(columns - 1)) / CGFloat(columns)

            ScrollView {
                LazyVGrid(columns: layout, spacing: Self.spacing) {
                    ForEach(monitor.probes) { probe in
                        ProbeTile(probe: probe, compact: width < 320 || height < 190)
                            .frame(height: height)
                    }
                }
            }
            .scrollDisabled(fitted >= Self.minHeight)
            .scrollIndicators(.automatic)
        }
    }

    /// The column count: the setting, or the one whose tiles come out closest
    /// to a wide rectangle, with as few empty spaces as possible
    static func columns(count: Int, setting: Int, size: CGSize) -> Int {
        if setting > 0 { return setting }
        let byWidth = max(1, Int((size.width + spacing) / (minWidth + spacing)))
        let idealAspect = 1.6
        var best = (columns: 1, score: Double.infinity)
        for columns in 1...max(1, min(count, byWidth)) {
            let rows = Int(ceil(Double(count) / Double(columns)))
            let width = (size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let height = max(minHeight, (size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows))
            let empty = Double(columns * rows - count) / Double(columns)
            let score = abs(log(Double(width / height) / idealAspect)) + empty * 0.5
            if score < best.score { best = (columns, score) }
        }
        return best.columns
    }
}
