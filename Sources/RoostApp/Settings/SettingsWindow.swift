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
    /// Tall enough for English, which is the longer of the two languages here;
    /// Chinese leaves a few points of slack rather than resizing the window
    /// under the cursor when the language changes.
    static let size = CGSize(width: 460, height: 566)

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
            } header: {
                Text(strings.appSection)
            } footer: {
                note(strings.updatesNote)
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
