import ServiceManagement

/// Whether Roost starts with the Mac.
///
/// Worth offering because of what this app is: something that answers a
/// question from the corner of your eye is no use if remembering to open it is
/// the first step. There is no Dock icon and no menu bar item to notice it by
/// either, so an unlaunched Roost is an invisible one.
@MainActor
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// macOS remembers a login item the user has switched off in System
    /// Settings and hands it back as "requires approval", which no amount of
    /// registering from here will change.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func set(_ on: Bool) {
        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
