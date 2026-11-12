import SwiftUI
import UniformTypeIdentifiers

/// A sheet's frame: title, body, and the buttons at the bottom
struct SheetChrome<Content: View, Buttons: View>: View {
    let title: String
    let subtitle: String
    var width: CGFloat = 460
    @ViewBuilder let content: Content
    @ViewBuilder let buttons: Buttons

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.display(26, relativeTo: .title))
                    .textCase(.uppercase)
                Text(subtitle)
                    .font(.mono(10.5))
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(AppColors.text)
            content
            HStack(spacing: 10) {
                Spacer()
                buttons
            }
        }
        .padding(20)
        .frame(width: width)
        .background(AppColors.ground)
    }
}

/// A multi-line box for hosts: typed, pasted, or a text file dropped on it
struct HostsEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 180
    @State private var targeted = false

    var body: some View {
        TextEditor(text: $text)
            .font(.mono(12))
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: minHeight)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .strokeBorder(targeted ? AppColors.ink : AppColors.hairline, lineWidth: targeted ? 2 : 1)
            }
            .dropDestination(for: URL.self) { urls, _ in
                let added = urls.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
                guard !added.isEmpty else { return false }
                text += (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + added.joined(separator: "\n")
                return true
            } isTargeted: { targeted = $0 }
    }
}

// MARK: - Add hosts

struct AddHostsSheet: View {
    @Environment(Monitor.self) private var monitor
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var count: Int { Target.list(from: text).count }

    var body: some View {
        SheetChrome(title: "Add hosts",
                    subtitle: "One per line, or separated by commas. host:port checks a TCP port. You can drop a text file here too.") {
            HostsEditor(text: $text)
        } buttons: {
            GhostButton(title: "Cancel") { dismiss() }
            PillButton(title: count == 0 ? "Start" : "Start \(count)", symbol: "play.fill") {
                monitor.addMany(text)
                dismiss()
            }
            .disabled(count == 0)
            .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Favourites

struct FavoritesSheet: View {
    @Environment(Monitor.self) private var monitor
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var confirmReplace = false
    @State private var editing: Favorite?

    var body: some View {
        SheetChrome(title: "Favourites",
                    subtitle: "Sets of hosts to load in one go. Saving keeps the hosts on screen and the column setting.",
                    width: 500) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField("Name for the hosts on screen", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .font(.mono(11))
                        .onSubmit(save)
                    PillButton(title: "Save", symbol: "star.fill", circle: AppColors.butter, action: save)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty
                                  || !monitor.probes.contains { Target(parsing: $0.input) != nil })
                }
                if monitor.favorites.isEmpty {
                    Text("No favourites yet.")
                        .font(.mono(10.5))
                        .foregroundStyle(AppColors.secondaryText)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(monitor.favorites) { favorite in
                                FavoriteRow(favorite: favorite,
                                            load: { monitor.load(favorite); dismiss() },
                                            edit: { editing = favorite },
                                            delete: { monitor.deleteFavorite(favorite) })
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
            }
        } buttons: {
            PillButton(title: "Done", symbol: "checkmark") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .alert("Replace \(newName)?", isPresented: $confirmReplace) {
            Button("Replace", role: .destructive) {
                monitor.saveFavorite(named: newName, replacing: true)
                newName = ""
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("There's already a favourite with that name.")
        }
        .sheet(item: $editing) { favorite in
            EditFavoriteSheet(favorite: favorite)
        }
    }

    private func save() {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if monitor.saveFavorite(named: newName) {
            newName = ""
        } else {
            confirmReplace = true
        }
    }
}

private struct FavoriteRow: View {
    let favorite: Favorite
    let load: () -> Void
    let edit: () -> Void
    let delete: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            SymbolTile(symbol: "star.fill", fill: AppColors.pastel(for: favorite.name), size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(favorite.name)
                    .font(.mono(12, weight: .semibold))
                Text("\(favorite.hosts.count) host\(favorite.hosts.count == 1 ? "" : "s") · "
                     + favorite.hosts.prefix(3).joined(separator: ", ")
                     + (favorite.hosts.count > 3 ? "…" : ""))
                    .font(.mono(9.5))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            RoundIconButton(symbol: "pencil", size: 24, fill: AppColors.ground, foreground: AppColors.text,
                            help: "Edit", action: edit)
            RoundIconButton(symbol: "trash", size: 24, fill: AppColors.ground, foreground: AppColors.destructive,
                            help: "Delete", action: delete)
            PillButton(title: "Load", symbol: "play.fill", action: load)
        }
        .foregroundStyle(AppColors.text)
        .padding(10)
        .card(hovered: hovered)
        .onHover { hovered = $0 }
    }
}

private struct EditFavoriteSheet: View {
    @Environment(Monitor.self) private var monitor
    @Environment(\.dismiss) private var dismiss
    let favorite: Favorite
    @State private var name: String
    @State private var hosts: String
    @State private var columns: Int

    init(favorite: Favorite) {
        self.favorite = favorite
        _name = State(initialValue: favorite.name)
        _hosts = State(initialValue: favorite.hosts.joined(separator: "\n"))
        _columns = State(initialValue: favorite.columns)
    }

    private var nameTaken: Bool {
        monitor.favorites.contains { $0 != favorite && $0.name.caseInsensitiveCompare(name.trimmingCharacters(in: .whitespaces)) == .orderedSame }
    }

    var body: some View {
        SheetChrome(title: "Edit favourite", subtitle: "Hosts one per line or separated by commas.") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.mono(11))
                if nameTaken {
                    SettingNote("There's already a favourite called that.")
                }
                HostsEditor(text: $hosts, minHeight: 160)
                Picker("Columns", selection: $columns) {
                    Text("Fit to window").tag(0)
                    ForEach(1...8, id: \.self) { Text("\($0)").tag($0) }
                }
                .font(.mono(11))
                .frame(width: 220)
            }
        } buttons: {
            GhostButton(title: "Cancel") { dismiss() }
            PillButton(title: "Save", symbol: "checkmark") {
                monitor.updateFavorite(favorite, name: name, hosts: Target.list(from: hosts).map(\.text), columns: columns)
                dismiss()
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || nameTaken)
            .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Aliases

struct AliasesSheet: View {
    @Environment(Monitor.self) private var monitor
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var name = ""

    var body: some View {
        SheetChrome(title: "Aliases",
                    subtitle: "Friendly names for hosts. They show on tiles, in alerts and in the status history.") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField("Host", text: $host)
                        .textFieldStyle(.roundedBorder)
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    PillButton(title: "Add", symbol: "plus", action: add)
                        .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty
                                  || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .font(.mono(11))
                if monitor.aliases.isEmpty {
                    Text("No aliases yet. You can also set one from a tile's tag button.")
                        .font(.mono(10.5))
                        .foregroundStyle(AppColors.secondaryText)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(monitor.aliases, id: \.host) { alias in
                                HStack(spacing: 10) {
                                    Text(alias.name)
                                        .font(.mono(12, weight: .semibold))
                                    Text(alias.host)
                                        .font(.mono(10.5))
                                        .foregroundStyle(AppColors.secondaryText)
                                    Spacer()
                                    RoundIconButton(symbol: "trash", size: 24, fill: AppColors.ground,
                                                    foreground: AppColors.destructive, help: "Remove") {
                                        monitor.setAlias("", for: alias.host)
                                    }
                                }
                                .foregroundStyle(AppColors.text)
                                .padding(10)
                                .card()
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                }
            }
        } buttons: {
            PillButton(title: "Done", symbol: "checkmark") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    private func add() {
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        monitor.setAlias(name, for: Target(parsing: host)?.host ?? host)
        host = ""
        name = ""
    }
}

// MARK: - About

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            AboutPopover(app: .macPing) {
                Mascot(size: 64)
            }
            HStack {
                Spacer()
                PillButton(title: "Done", symbol: "checkmark") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 18)
        }
        .background(AppColors.ground)
    }
}
