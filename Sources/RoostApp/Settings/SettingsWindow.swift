import AppKit
import SwiftUI
import RoostCore

/// The settings window.
///
/// An accessory app has no Dock icon to click and no menu bar item, so this is
/// the one place with room to explain what a switch actually does -- and the
/// one visible way out of the app.
@MainActor
final class SettingsWindowController {
    private let model: RoostModel
    private var window: NSWindow?

    init(model: RoostModel) {
        self.model = model
    }

    func show() {
        model.refreshHookState()

        let window = window ?? make()
        self.window = window
        window.center()
        // Accessory apps are never active, and a window nobody can type into
        // is not a settings window.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func make() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsView.size),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.title = model.strings.settingsTitle
        // The title bar belongs to AppKit, so the view hands it the wording
        // again whenever the language changes underneath it.
        window.contentView = NSHostingView(rootView: SettingsView(model: model) { [weak window] title in
            window?.title = title
        })
        return window
    }
}

struct SettingsView: View {
    /// Shorter than the form it holds, which is fine: a grouped form on macOS
    /// is backed by a scroll view, so the switches below the fold are a scroll
    /// away rather than gone.
    ///
    /// Sized to the screen rather than to the content, because the content
    /// outgrew the screen: the full form is around 960 pt and a 14-inch
    /// MacBook Pro has about 957 pt of usable height, so a window tall enough
    /// to show all of it would hang off the bottom of the display it was
    /// centred on.
    static let size = CGSize(width: 460, height: 640)

    @Bindable var model: RoostModel
    let retitle: (String) -> Void

    private var strings: Strings { model.strings }

    var body: some View {
        Form {
            Section {
                LabeledContent(strings.version, value: model.currentVersion)
                LabeledContent(strings.update) {
                    if let update = model.update {
                        Button(strings.download(update.version)) {
                            NSWorkspace.shared.open(update.page)
                        }
                    } else {
                        Text(strings.upToDate).foregroundStyle(.secondary)
                    }
                }
                Toggle(strings.checkAutomatically, isOn: $model.checksForUpdates)
                    .toggleStyle(.switch)
                if LoginItem.needsApproval {
                    LabeledContent(strings.openAtLogin) {
                        HStack(spacing: 8) {
                            Text(strings.loginNeedsApproval).foregroundStyle(.secondary)
                            Button(strings.openSystemSettings) { LoginItem.openSystemSettings() }
                        }
                    }
                } else {
                    Toggle(strings.openAtLogin, isOn: Binding(
                        get: { model.opensAtLogin },
                        set: { model.setOpensAtLogin($0) }
                    ))
                    .toggleStyle(.switch)
                }
            } header: {
                Text(strings.appSection)
            } footer: {
                note("\(strings.updatesNote)\n\n\(strings.loginNote)")
            }

            Section {
                Toggle(strings.watchAgent(.codex), isOn: Binding(
                    get: { model.watchesCodex },
                    set: { model.setWatchesCodex($0) }
                ))
                .toggleStyle(.switch)
            } header: {
                Text(strings.agentsSection)
            } footer: {
                note(strings.codexNote)
            }

            Section {
                Toggle(strings.playSounds, isOn: Binding(
                    get: { model.sounds.isOn },
                    set: { model.sounds.isOn = $0; if $0 { model.sounds.play(.waiting) } }
                ))
                .toggleStyle(.switch)
            } header: {
                Text(strings.soundSection)
            } footer: {
                note(strings.soundsNote)
            }

            Section {
                Toggle(strings.showUsage, isOn: Binding(
                    get: { model.showsUsage },
                    set: { model.setShowsUsage($0) }
                ))
                .toggleStyle(.switch)
            } header: {
                Text(strings.usageSection)
            } footer: {
                note(strings.usageNote)
            }

            Section {
                Picker(strings.interfaceLanguage, selection: $model.languageChoice) {
                    ForEach(LanguageChoice.allCases, id: \.self) { choice in
                        Text(strings.name(of: choice)).tag(choice)
                    }
                }
            } header: {
                Text(strings.languageSection)
            } footer: {
                note(strings.languageNote)
            }

            Section {
                Toggle(strings.answerPrompts, isOn: Binding(
                    get: { model.answersPrompts },
                    set: { model.setAnswersPrompts($0) }
                ))
                .toggleStyle(.switch)
            } header: {
                Text(strings.approvalsSection)
            } footer: {
                note(strings.approvalsNote)
            }

            Section {
                HStack {
                    Spacer()
                    Button(strings.quit) { NSApplication.shared.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.size.width, height: Self.size.height)
        .onChange(of: model.language, initial: true) { retitle(strings.settingsTitle) }
    }

    private func note(_ body: String) -> some View {
        Text(body)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
