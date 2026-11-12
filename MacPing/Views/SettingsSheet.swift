import AppKit
import SwiftUI

struct SettingsSheet: View {
    @Environment(Monitor.self) private var monitor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = monitor.settings
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.display(26, relativeTo: .title))
                        .textCase(.uppercase)
                    Text("Changes to pinging apply from the next ping.")
                        .font(.mono(10.5))
                        .foregroundStyle(AppColors.secondaryText)
                }
                .foregroundStyle(AppColors.text)
                Spacer()
                PillButton(title: "Done", symbol: "checkmark") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Pinging")
                    SettingCard(title: "Every", detail: "How often each host is pinged.", trailing: {
                        PillPicker(selection: $settings.interval, options: AppSettings.intervals,
                                   track: AppColors.ground, label: Self.seconds)
                    })
                    SettingCard(title: "Wait for a reply", detail: "Longer than this counts as lost.", trailing: {
                        PillPicker(selection: $settings.timeout, options: AppSettings.timeouts,
                                   track: AppColors.ground, label: Self.seconds)
                    })
                    SettingCard(title: "Down after", detail: "Lost replies in a row before a host counts as down. Fewer are shown in yellow.", trailing: {
                        PillPicker(selection: $settings.downAfter, options: AppSettings.downAfterChoices,
                                   track: AppColors.ground) { "\($0)" }
                    })
                    SettingCard(title: "TTL", detail: "How many routers a ping may pass through. 64 suits almost everything.", trailing: {
                        NumberStepper(value: $settings.ttl, range: 1...255)
                    })
                    SettingCard(title: "Packet size", detail: "Bytes of data in each ping, after the 8-byte header.", trailing: {
                        NumberStepper(value: $settings.payloadSize, range: 0...1400, step: 8)
                    })

                    SectionLabel(text: "When a host goes down or comes back").padding(.top, 8)
                    SettingToggle(title: "Notifications", detail: "A notification for each host that goes down or comes back up.",
                                  isOn: $settings.notify)
                    SettingToggle(title: "Play a sound", detail: "A sound when a host goes down, and a lighter one when it's back.",
                                  isOn: $settings.playSound) {
                        if settings.playSound {
                            HStack(spacing: 8) {
                                Picker("Down sound", selection: $settings.downSound) {
                                    ForEach(AppSettings.sounds, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden()
                                .frame(width: 140)
                                GhostButton(title: "Play", symbol: "speaker.wave.2.fill") {
                                    NSSound(named: NSSound.Name(settings.downSound))?.play()
                                }
                            }
                            .font(.mono(11))
                        }
                    }
                    SettingToggle(title: "Write a log file", detail: "One line for each host that goes down or comes back, with the time.",
                                  isOn: $settings.logToFile) {
                        if settings.logToFile {
                            HStack(spacing: 8) {
                                Text((settings.logPath as NSString).abbreviatingWithTildeInPath)
                                    .font(.mono(10))
                                    .foregroundStyle(AppColors.secondaryText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                GhostButton(title: "Change…") { chooseLogFile(settings) }
                                GhostButton(title: "Show") {
                                    let url = URL(fileURLWithPath: (settings.logPath as NSString).expandingTildeInPath)
                                    if FileManager.default.fileExists(atPath: url.path) {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    } else {
                                        NSWorkspace.shared.open(url.deletingLastPathComponent())
                                    }
                                }
                            }
                        }
                    }

                    SectionLabel(text: "MacPing").padding(.top, 8)
                    SettingCard(title: "When MacPing opens", detail: "What to show in the window.") {
                        PillPicker(selection: $settings.startup, options: StartupMode.allCases,
                                   track: AppColors.ground, label: \.label)
                    } below: {
                        switch settings.startup {
                        case .favorite:
                            if monitor.favorites.isEmpty {
                                SettingNote("Save a favourite first, from the star menu.", isError: false)
                            } else {
                                Picker("Favourite", selection: $settings.startupFavorite) {
                                    Text("Choose…").tag(String?.none)
                                    ForEach(monitor.favorites) { Text($0.name).tag(Optional($0.name)) }
                                }
                                .font(.mono(11))
                                .frame(width: 260)
                            }
                        case .blank:
                            HStack(spacing: 8) {
                                Text("Empty monitors")
                                    .font(.mono(11))
                                    .foregroundStyle(AppColors.secondaryText)
                                NumberStepper(value: $settings.blankCount, range: 1...16)
                            }
                        case .lastSession:
                            EmptyView()
                        }
                    }
                    SettingToggle(title: "Keep on top", detail: "Keep the MacPing window above other windows.",
                                  isOn: $settings.alwaysOnTop)
                    SettingToggle(title: "Show in the menu bar",
                                  detail: "Up and down at a glance. Closing the window keeps MacPing pinging up there.",
                                  isOn: $settings.showInMenuBar)
                    SettingToggle(title: "Open at login",
                                  detail: settings.showInMenuBar ? "Start MacPing in the menu bar when you log in." : "Start MacPing when you log in.",
                                  isOn: Binding(get: { settings.openAtLoginEnabled }, set: { settings.setOpenAtLogin($0) })) {
                        if let error = settings.loginError { SettingNote(error) }
                    }
                    UpdateBlock(updater: monitor.updater, app: .macPing)
                }
                .padding([.horizontal, .bottom], 20)
            }
        }
        .frame(width: 560, height: 640)
        .background(AppColors.ground)
        .onChange(of: settings.interval) { monitor.applyOptions() }
        .onChange(of: settings.timeout) { monitor.applyOptions() }
        .onChange(of: settings.ttl) { monitor.applyOptions() }
        .onChange(of: settings.payloadSize) { monitor.applyOptions() }
    }

    static func seconds(_ value: TimeInterval) -> String {
        value < 1 ? "\(Int(value * 1000))ms" : "\(Int(value))s"
    }

    private func chooseLogFile(_ settings: AppSettings) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Status changes.log"
        panel.directoryURL = URL(fileURLWithPath: (settings.logPath as NSString).expandingTildeInPath).deletingLastPathComponent()
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { settings.logPath = url.path }
    }
}

/// A number with − and + buttons, in the house style
struct NumberStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1

    var body: some View {
        HStack(spacing: 6) {
            RoundIconButton(symbol: "minus", size: 22, fill: AppColors.ground, foreground: AppColors.text, help: "Less") {
                value = max(range.lowerBound, value - step)
            }
            .disabled(value <= range.lowerBound)
            Text("\(value)")
                .font(.mono(12, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 36)
                .foregroundStyle(AppColors.text)
            RoundIconButton(symbol: "plus", size: 22, fill: AppColors.ground, foreground: AppColors.text, help: "More") {
                value = min(range.upperBound, value + step)
            }
            .disabled(value >= range.upperBound)
        }
    }
}
