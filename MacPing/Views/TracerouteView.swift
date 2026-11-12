import AppKit
import SwiftUI

/// One traceroute run, fed by `Traceroute` from its thread
@MainActor
@Observable
final class TracerouteSession {
    var host: String
    private(set) var hops: [Hop] = []
    private(set) var running = false
    private(set) var address: String?
    private(set) var result: String?
    @ObservationIgnored private var trace: Traceroute?

    init(host: String = "") {
        self.host = host
    }

    func start() {
        let host = Target(parsing: host)?.host ?? host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        trace?.cancel()
        hops = []
        address = nil
        result = nil
        running = true
        let trace = Traceroute()
        self.trace = trace
        trace.run(host: host) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, self.trace === trace else { return }
                self.handle(event)
            }
        }
    }

    func stop() {
        trace?.cancel()
        trace = nil
        if running { result = "Stopped" }
        running = false
    }

    private func handle(_ event: Traceroute.Event) {
        switch event {
        case .resolved(let address):
            self.address = address
        case .hop(let hop):
            hops.append(hop)
        case .named(let number, let name):
            if let index = hops.firstIndex(where: { $0.number == number }) { hops[index].name = name }
        case .finished(let reached):
            running = false
            result = reached ? "Reached in \(hops.count) hop\(hops.count == 1 ? "" : "s")"
                             : "Didn't reach \(host) in \(hops.count) hops"
        case .failed(let message):
            running = false
            result = message
        }
    }

    /// Screenshots: a finished trace, without sending anything
    func showDemo(address: String, hops: [Hop]) {
        self.address = address
        self.hops = hops
        result = "Reached in \(hops.count) hops"
    }

    /// The hops as text, for copying
    var text: String {
        var lines = ["Traceroute to \(host)" + (address.map { " (\($0))" } ?? "")]
        for hop in hops {
            var line = String(format: "%2d  ", hop.number)
            if let address = hop.address {
                line += hop.name.map { "\($0) (\(address))" } ?? address
                if let ms = hop.ms { line += "  \(Probe.format(ms))" }
            } else {
                line += "*"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}

struct TracerouteView: View {
    @Bindable var session: TracerouteSession
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SymbolTile(symbol: "point.topleft.down.to.point.bottomright.curvepath", fill: AppColors.periwinkle, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Traceroute")
                        .font(.display(26, relativeTo: .title))
                        .textCase(.uppercase)
                    Text(status)
                        .font(.mono(10.5))
                        .foregroundStyle(AppColors.secondaryText)
                }
                .foregroundStyle(AppColors.text)
                Spacer()
            }

            HStack(spacing: 8) {
                TextField("Host or IP", text: $session.host)
                    .textFieldStyle(.plain)
                    .font(.mono(12, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(AppColors.surface, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                    .focused($fieldFocused)
                    .onSubmit { session.start() }
                if session.running {
                    PillButton(title: "Stop", symbol: "stop.fill", circle: AppColors.coral) { session.stop() }
                } else {
                    PillButton(title: "Trace", symbol: "play.fill") { session.start() }
                        .disabled(session.host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                RoundIconButton(symbol: "doc.on.doc", size: 30, fill: AppColors.surface, foreground: AppColors.text,
                                help: "Copy the hops") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.text, forType: .string)
                }
                .disabled(session.hops.isEmpty)
            }

            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(session.hops) { hop in
                            HopRow(hop: hop).id(hop.number)
                        }
                        if session.running {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Hop \(session.hops.count + 1)…")
                                    .font(.mono(10.5))
                                    .foregroundStyle(AppColors.secondaryText)
                                Spacer()
                            }
                            .padding(10)
                            .id(-1)
                        }
                    }
                }
                .onChange(of: session.hops.count) { reader.scrollTo(-1, anchor: .bottom) }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(18)
        .padding(.top, 20)
        .frame(minWidth: 480, minHeight: 360)
        .background(AppColors.ground)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            if session.host.isEmpty { fieldFocused = true } else if session.hops.isEmpty { session.start() }
        }
        .onDisappear { session.stop() }
    }

    private var status: String {
        if let result = session.result { return result }
        if session.running { return "Tracing \(session.host)" + (session.address.map { " (\($0))" } ?? "") + "…" }
        return "The routers between your Mac and a host"
    }
}

private struct HopRow: View {
    let hop: Hop

    var body: some View {
        HStack(spacing: 12) {
            Text("\(hop.number)")
                .font(.display(20, relativeTo: .headline))
                .frame(width: 30, height: 30)
                .background(hop.reachedTarget ? AppColors.mint : (hop.address == nil ? AppColors.surface : AppColors.butter),
                            in: Circle())
                .foregroundStyle(hop.address == nil && !hop.reachedTarget ? AppColors.secondaryText : AppColors.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(hop.name ?? hop.address ?? "No answer")
                    .font(.mono(11.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if hop.name != nil, let address = hop.address {
                    Text(address)
                        .font(.mono(10))
                        .foregroundStyle(AppColors.secondaryText)
                } else if hop.address == nil {
                    Text("This router doesn't reply to traceroutes")
                        .font(.mono(10))
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
            Spacer()
            if let ms = hop.ms {
                Text(Probe.format(ms))
                    .font(.mono(11, weight: .medium))
                    .monospacedDigit()
            } else {
                Text("*").font(.mono(11)).foregroundStyle(AppColors.secondaryText)
            }
        }
        .foregroundStyle(AppColors.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .card()
    }
}
