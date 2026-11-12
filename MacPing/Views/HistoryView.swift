import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Every host that went up or down, and every monitor started or stopped,
/// with filters and export. Its own window, so it can stay open beside the grid.
struct HistoryView: View {
    @Environment(Monitor.self) private var monitor
    @State private var kinds = Set(StatusEvent.Kind.allCases)
    @State private var search = ""
    @State private var newestFirst = true

    private var events: [StatusEvent] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let filtered = monitor.history.filter { event in
            kinds.contains(event.kind) && (query.isEmpty
                || event.host.localizedCaseInsensitiveContains(query)
                || (event.alias?.localizedCaseInsensitiveContains(query) ?? false))
        }
        return newestFirst ? filtered.reversed() : filtered
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Mascot(mood: monitor.downCount > 0 ? .worried : .happy, size: 40, disc: AppColors.butter)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Status history")
                        .font(.display(26, relativeTo: .title))
                        .textCase(.uppercase)
                    Text("\(monitor.history.count) change\(monitor.history.count == 1 ? "" : "s") since MacPing opened")
                        .font(.mono(10.5))
                        .foregroundStyle(AppColors.secondaryText)
                }
                .foregroundStyle(AppColors.text)
                Spacer()
                Menu {
                    ForEach(HistoryExport.Delimiter.allCases, id: \.self) { delimiter in
                        Button("Export as \(delimiter.label)…") { export(delimiter) }
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.mono(11, weight: .medium))
                }
                .fixedSize()
                .disabled(events.isEmpty)
                GhostButton(title: "Clear", symbol: "trash") { monitor.clearHistory() }
                    .disabled(monitor.history.isEmpty)
            }

            HStack(spacing: 8) {
                ForEach(StatusEvent.Kind.allCases, id: \.self) { kind in
                    FilterChip(title: kind.label, fill: kind.fill, on: kinds.contains(kind)) {
                        if kinds.contains(kind) { kinds.remove(kind) } else { kinds.insert(kind) }
                    }
                }
                Spacer()
                TextField("Filter hosts", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .font(.mono(11))
                    .frame(width: 180)
                Button { newestFirst.toggle() } label: {
                    Image(systemName: newestFirst ? "arrow.down" : "arrow.up")
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.text)
                .help(newestFirst ? "Newest first" : "Oldest first")
            }

            if events.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Text(monitor.history.isEmpty ? "Nothing yet. Changes show here as hosts go up and down." : "Nothing matches.")
                        .font(.mono(11))
                        .foregroundStyle(AppColors.secondaryText)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(events) { event in
                            HStack(spacing: 10) {
                                TagPill(text: event.kind.label, fill: event.kind.fill)
                                    .frame(width: 64, alignment: .leading)
                                Text(event.name)
                                    .font(.mono(11.5, weight: .semibold))
                                if event.alias != nil {
                                    Text(event.host)
                                        .font(.mono(10))
                                        .foregroundStyle(AppColors.secondaryText)
                                }
                                Spacer()
                                Text(Self.time.string(from: event.date))
                                    .font(.mono(10))
                                    .foregroundStyle(AppColors.secondaryText)
                                    .monospacedDigit()
                            }
                            .foregroundStyle(AppColors.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .card()
                        }
                    }
                }
            }
        }
        .padding(18)
        .padding(.top, 20)
        .frame(minWidth: 520, minHeight: 360)
        .background(AppColors.ground)
        .ignoresSafeArea(.container, edges: .top)
    }

    private func export(_ delimiter: HistoryExport.Delimiter) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MacPing history.\(delimiter.fileExtension)"
        panel.allowedContentTypes = [delimiter == .comma ? .commaSeparatedText : .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Exported in time order, whatever the list shows
        let ordered = newestFirst ? events.reversed() : events
        try? HistoryExport.text(ordered, delimiter: delimiter).write(to: url, atomically: true, encoding: .utf8)
    }
}

extension StatusEvent.Kind {
    var fill: Color {
        switch self {
        case .up: return AppColors.mint
        case .down: return AppColors.coral
        case .start: return AppColors.periwinkle
        case .stop: return AppColors.lilac
        }
    }
}

/// A capsule that filters a list on or off
struct FilterChip: View {
    let title: String
    let fill: Color
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: on ? "checkmark" : "circle")
                    .font(.system(size: 9, weight: .bold))
                Text(title.uppercased())
                    .font(.mono(10, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(on ? AppColors.ink : AppColors.secondaryText)
            .background(on ? fill : AppColors.surface, in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
