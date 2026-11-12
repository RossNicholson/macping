import SwiftUI

/// What drops down from the menu bar: every monitor at a glance, start or
/// stop them all, and the way back to the window
struct MenuBarPanel: View {
    @Environment(Monitor.self) private var monitor
    let openWindow: () -> Void
    let openHistory: () -> Void
    let close: () -> Void
    @State private var showingAbout = false

    private var watched: [Probe] { monitor.probes.filter { $0.target != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: "MacPing", subtitle: monitor.summary) {
                BouncingMascot(running: monitor.anyRunning, mood: monitor.downCount > 0 ? .worried : .happy)
            } actions: {
                HeaderIconButton(symbol: "clock.arrow.circlepath", help: "Status history") {
                    close()
                    openHistory()
                }
                HeaderIconButton(symbol: "info", help: "About MacPing") { showingAbout.toggle() }
                    .popover(isPresented: $showingAbout, arrowEdge: .bottom) {
                        AboutPopover(app: .macPing) { Mascot(size: 56) }
                    }
            }

            if watched.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing to watch yet")
                        .font(.display(18, relativeTo: .headline))
                        .textCase(.uppercase)
                    Text("Add hosts in the MacPing window and they show here, up or down.")
                        .font(.mono(10.5))
                        .opacity(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .pastelCard(AppColors.periwinkle)
                .padding(.horizontal, PanelMetrics.inset)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(watched) { probe in
                            PanelProbeRow(probe: probe)
                        }
                    }
                    .padding(.horizontal, PanelMetrics.inset)
                }
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if monitor.anyRunning {
                    PillButton(title: "Stop all", symbol: "stop.fill", circle: AppColors.coral) { monitor.stopAll() }
                } else {
                    PillButton(title: "Start all", symbol: "play.fill") { monitor.startAll() }
                        .disabled(watched.isEmpty)
                }
                Spacer()
                PillButton(title: "Open", symbol: "macwindow", circle: AppColors.butter) {
                    close()
                    openWindow()
                }
            }
            .padding(.horizontal, PanelMetrics.inset)
            .padding(.vertical, 12)

            PanelFooter {
                Text(monitor.runningCount == 0 ? "Not pinging" : "Pinging \(monitor.runningCount) host\(monitor.runningCount == 1 ? "" : "s")")
            }
        }
        .menuBarPanel()
    }
}

private struct PanelProbeRow: View {
    @Environment(Monitor.self) private var monitor
    let probe: Probe
    @State private var hovered = false

    var body: some View {
        let alias = monitor.alias(for: probe.target)
        HStack(spacing: 10) {
            Image(systemName: probe.status.symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(probe.status == .inactive ? AppColors.ground : probe.status.fill, in: Circle())
                .foregroundStyle(probe.status == .inactive ? AppColors.secondaryText : AppColors.ink)
            VStack(alignment: .leading, spacing: 1) {
                Text(alias ?? probe.target?.text ?? "")
                    .font(.mono(11.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.mono(9.5))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if hovered || !probe.isRunning {
                RoundIconButton(symbol: probe.isRunning ? "stop.fill" : "play.fill", size: 22,
                                help: probe.isRunning ? "Stop" : "Start") { monitor.toggle(probe) }
            } else if let ms = probe.stats.lastMs, probe.status == .up {
                Text(Probe.format(ms))
                    .font(.mono(10.5, weight: .medium))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(AppColors.text)
        .padding(8)
        .card(hovered: hovered)
        .onHover { hovered = $0 }
    }

    private var detail: String {
        var parts = [probe.status.label]
        if probe.isRunning, probe.stats.sent > 0 {
            parts.append("\(Int(probe.stats.lossPercent.rounded()))% lost")
        }
        if monitor.alias(for: probe.target) != nil, let target = probe.target { parts.append(target.text) }
        return parts.joined(separator: " · ")
    }
}
