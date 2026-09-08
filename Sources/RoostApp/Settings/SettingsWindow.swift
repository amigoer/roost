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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "Roost Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        return window
    }
}

struct SettingsView: View {
    @Bindable var model: RoostModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: model.currentVersion)
                LabeledContent("Update") {
                    if let update = model.update {
                        Button("Download \(update.version)") {
                            NSWorkspace.shared.open(update.page)
                        }
                    } else {
                        Text("Up to date").foregroundStyle(.secondary)
                    }
                }
                Toggle("Check automatically", isOn: $model.checksForUpdates)
                    .toggleStyle(.switch)
            } header: {
                Text("Roost")
            } footer: {
                Text("Checks the public releases page every six hours and sends nothing but the request. Installing an update stays manual.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Answer permission prompts in the island", isOn: Binding(
                    get: { model.answersPrompts },
                    set: { model.setAnswersPrompts($0) }
                ))
                .toggleStyle(.switch)
            } header: {
                Text("Approvals")
            } footer: {
                Text("Adds one hook to ~/.claude/settings.json, pointing at the helper inside this app. Turning it off takes the entry back out. With Roost closed, or no answer within a minute, sessions prompt exactly as they do now.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Force a state", selection: $model.presetName) {
                    ForEach(RoostModel.presets, id: \.name) { preset in
                        Text(preset.name).tag(preset.name)
                    }
                }
            } header: {
                Text("Preview")
            } footer: {
                Text("Holds the island in one state so the design can be judged without waiting for a session to produce it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Quit Roost") { NSApplication.shared.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
    }
}
