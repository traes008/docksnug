import AppKit
import ServiceManagement
import SwiftUI

final class AppStatus: ObservableObject {
    @Published var hasPermission = false
}

struct SettingsView: View {
    @ObservedObject var status: AppStatus
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                if status.hasPermission {
                    Text("DockSnug is running.")
                } else {
                    Text("DockSnug needs Accessibility access to resize your windows.")
                    Button("Open Accessibility Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }

            Section {
                Toggle("Open at Login", isOn: Binding(get: { opensAtLogin }, set: setOpensAtLogin))
                Button("Quit DockSnug") { NSApp.terminate(nil) }
            } footer: {
                Text("Runs in the background. Open the app again to get back here.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setOpensAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("DockSnug: could not change Open at Login: \(error)")
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}
