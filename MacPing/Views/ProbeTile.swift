import SwiftUI
import UniformTypeIdentifiers

/// One monitor in the grid: coloured by status, with its log and totals.
/// Stopped, the host can be typed or changed; Return starts it.
struct ProbeTile: View {
    @Environment(Monitor.self) private var monitor
    @Environment(\.openTraceroute) private var openTraceroute
    let probe: Probe
    var compact = false

    @State private var draft = ""
    @State private var hoveringLog = false
    @State private var editingAlias = false
    @State private var dropTargeted = false
    @FocusState private var fieldFocused: Bool

    private var status: ProbeStatus { probe.status }
    private var alias: String? { monitor.alias(for: probe.target) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if probe.isRunning || !probe.lines.isEmpty {
                log
                stats
            } else {
                Spacer(minLength: 0)
                hint
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(status.foreground)
        .environment(\.onPastel, status != .inactive)
        .background(status.fill, in: RoundedRectangle(cornerRadius: Radius.block, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
                .strokeBorder(dropTargeted ? AppColors.ink : .clear, lineWidth: 2)
        }
        .animation(.easeInOut(duration: 0.25), value: status)
        .contextMenu { actions }
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(Self.draggedID) else {
                // Text dropped on a tile: hosts, as on the rest of the window
                guard !Target.list(from: items.joined(separator: "\n")).isEmpty else { return false }
                monitor.addMany(items.joined(separator: "\n"))
                return true
            }
            guard let dragged = monitor.probes.first(where: { $0.id == id }) else { return false }
            withAnimation(.easeInOut(duration: 0.2)) { monitor.move(dragged, before: probe) }
            return true
        } isTargeted: { dropTargeted = $0 }
        .onAppear { draft = probe.input }
        .onChange(of: probe.input) { _, new in if !fieldFocused { draft = new } }
        // Filled in while the field had focus (a dropped list, say)
        .onChange(of: probe.isRunning) { draft = probe.input }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(alias ?? probe.target?.text ?? "Empty monitor"), \(status.label)")
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: status.symbol)
                .font(.system(size: 15, weight: .semibold))
                .opacity(status == .inactive ? 0.5 : 1)
                .help(statusHelp)

            if probe.isRunning {
                VStack(alignment: .leading, spacing: 1) {
                    Text(alias ?? probe.target?.host ?? probe.input)
                        .font(.display(compact ? 18 : 22, relativeTo: .headline))
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle)
                        .font(.mono(9.5))
                        .opacity(0.72)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                TextField("Host, IP or host:port", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.mono(12, weight: .medium))
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(AppColors.ground.opacity(status == .inactive ? 1 : 0.6),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .focused($fieldFocused)
                    .onSubmit(startFromField)
                    .accessibilityLabel("Host to watch")
            }

            Spacer(minLength: 4)
            buttons
        }
        .contentShape(Rectangle())
        .draggable(Self.dragPrefix + probe.id.uuidString) {
            Text(alias ?? probe.target?.text ?? "Monitor")
                .font(.mono(11, weight: .medium))
                .padding(8)
                .background(status.fill, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var buttons: some View {
        HStack(spacing: 4) {
            RoundIconButton(symbol: probe.isRunning ? "stop.fill" : "play.fill", size: 24,
                            help: probe.isRunning ? "Stop" : "Start") {
                if probe.isRunning { monitor.stop(probe) } else { startFromField() }
            }
            .disabled(!probe.isRunning && Target(parsing: draft) == nil)
            Menu { actions } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(AppColors.ink.opacity(0.08), in: Circle())
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .help("More")
            .popover(isPresented: $editingAlias, arrowEdge: .bottom) {
                AliasPopover(host: probe.target?.host ?? "", initial: alias ?? "") { name in
                    monitor.setAlias(name, for: probe.target?.host ?? "")
                    editingAlias = false
                }
            }
        }
    }

    /// The tile's menu, from its ⋯ button or a right-click
    @ViewBuilder private var actions: some View {
        if let target = probe.target {
            Button(probe.isRunning ? "Stop" : "Start") { monitor.toggle(probe) }
            if !target.isPortCheck {
                Button("Traceroute to \(target.host)") { openTraceroute(target.host) }
            }
            Button(alias == nil ? "Add an Alias…" : "Change Alias…") { editingAlias = true }
            Divider()
        }
        let index = monitor.probes.firstIndex { $0.id == probe.id } ?? 0
        Button("Move Earlier") { withAnimation(.easeInOut(duration: 0.2)) { monitor.move(probe, by: -1) } }
            .disabled(index == 0)
        Button("Move Later") { withAnimation(.easeInOut(duration: 0.2)) { monitor.move(probe, by: 1) } }
            .disabled(index >= monitor.probes.count - 1)
        Divider()
        Button("Remove", role: .destructive) {
            withAnimation(.easeInOut(duration: 0.2)) { monitor.remove(probe) }
        }
    }

    /// Tiles are dragged as text with this in front, so the window's own drop
    /// (a list of hosts) can tell a tile from typed text
    nonisolated static let dragPrefix = "macping-tile:"

    nonisolated static func draggedID(_ text: String) -> UUID? {
        guard text.hasPrefix(dragPrefix) else { return nil }
        return UUID(uuidString: String(text.dropFirst(dragPrefix.count)))
    }

    private var subtitle: String {
        guard let target = probe.target else { return "" }
        var parts: [String] = []
        if alias != nil { parts.append(target.text) }
        if let address = probe.resolvedAddress, address != target.host {
            parts.append(address)
        }
        if let port = target.port, alias == nil { parts.append("port \(port)") }
        parts.append(status.label.lowercased())
        return parts.joined(separator: " · ")
    }

    private var statusHelp: String {
        switch status {
        case .indeterminate: return "Some replies lost; \(monitor.settings.downAfter) in a row counts as down"
        case .error(let message): return message
        default: return status.label
        }
    }

    private func startFromField() {
        guard Target(parsing: draft) != nil else { return }
        if draft != probe.input || probe.target == nil {
            monitor.retarget(probe, to: draft)
        } else {
            monitor.start(probe)
        }
        fieldFocused = false
    }

    // MARK: - Log

    private var log: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(probe.lines) { line in
                        LogLine(line: line, compact: compact).id(line.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
            }
            .scrollIndicators(.never)
            .background(AppColors.ink.opacity(status == .inactive ? 0.05 : 0.07),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onHover { hoveringLog = $0 }
            .onChange(of: probe.lines.last?.id) { _, last in
                // Reading back through the log: don't jump to the bottom
                guard let last, !hoveringLog else { return }
                reader.scrollTo(last, anchor: .bottom)
            }
            .onAppear { if let last = probe.lines.last?.id { reader.scrollTo(last, anchor: .bottom) } }
        }
        .frame(maxHeight: .infinity)
    }

    private var stats: some View {
        let s = probe.stats
        var parts = ["\(s.sent) sent", "\(Int(s.lossPercent.rounded()))% lost"]
        if let average = s.averageMs { parts.append("avg \(Probe.format(average))") }
        if !compact, let low = s.minMs, let high = s.maxMs, high > low {
            parts.append("\(Probe.format(low).replacingOccurrences(of: " ms", with: ""))–\(Probe.format(high))")
        }
        return Text(parts.joined(separator: " · "))
            .font(.mono(9.5, weight: .medium))
            .opacity(0.8)
            .lineLimit(1)
            .monospacedDigit()
    }

    private var hint: some View {
        Text(probe.target == nil
             ? "Type a host and press Return. Add :port to check a TCP port."
             : "Press play or Return to start.")
            .font(.mono(10))
            .foregroundStyle(status == .inactive ? AppColors.secondaryText : AppColors.ink.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct LogLine: View {
    let line: ProbeLine
    let compact: Bool

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if !compact {
                Text(Self.time.string(from: line.date))
                    .opacity(0.55)
            }
            Text(line.repeats > 1 ? "\(line.text)  ×\(line.repeats)" : line.text)
                .fontWeight(line.kind == .lost || line.kind == .error ? .semibold : .regular)
                .opacity(line.kind == .info ? 0.7 : 1)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.mono(10.5))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Names a host: the alias shows on its tile, in alerts and in the history
struct AliasPopover: View {
    let host: String
    let save: (String) -> Void
    @State private var name: String

    init(host: String, initial: String, save: @escaping (String) -> Void) {
        self.host = host
        self.save = save
        _name = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PopoverHeader(title: "Alias", subtitle: "A name to show for \(host). Leave it empty to show the host.")
            TextField("e.g. Office router", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.mono(11))
                .onSubmit { save(name) }
            HStack {
                Spacer()
                PillButton(title: "Save", symbol: "checkmark") { save(name) }
            }
        }
        .popoverChrome(width: 280)
    }
}

/// Opens the traceroute window for a host; set by the app delegate
struct OpenTracerouteKey: EnvironmentKey {
    static let defaultValue: @MainActor (String) -> Void = { _ in }
}

extension EnvironmentValues {
    var openTraceroute: @MainActor (String) -> Void {
        get { self[OpenTracerouteKey.self] }
        set { self[OpenTracerouteKey.self] = newValue }
    }
}
