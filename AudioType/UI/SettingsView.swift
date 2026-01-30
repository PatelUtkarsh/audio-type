import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("selectedModel") private var selectedModel = "base.en"
    
    var body: some View {
        Form {
            Section {
                LabeledContent("Hotkey") {
                    Text("Cmd + Shift + Space")
                        .foregroundColor(.secondary)
                }
                
                Picker("Model", selection: $selectedModel) {
                    Text("Tiny (75 MB) - Fastest").tag("tiny.en")
                    Text("Base (142 MB) - Recommended").tag("base.en")
                    Text("Small (466 MB) - Better accuracy").tag("small.en")
                }
                .pickerStyle(.menu)
            } header: {
                Text("Transcription")
            }
            
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        setLaunchAtLogin(newValue)
                    }
            } header: {
                Text("General")
            }
            
            Section {
                HStack {
                    Text("Microphone")
                    Spacer()
                    PermissionStatusView(granted: checkMicrophonePermission())
                }
                
                HStack {
                    Text("Accessibility")
                    Spacer()
                    PermissionStatusView(granted: Permissions.checkAccessibility())
                }
                
                Button("Open Accessibility Settings") {
                    Permissions.openAccessibilitySettings()
                }
            } header: {
                Text("Permissions")
            }
            
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
                
                Link("View on GitHub", destination: URL(string: "https://github.com")!)
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 350)
    }
    
    private func checkMicrophonePermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to set launch at login: \(error)")
        }
    }
}

struct PermissionStatusView: View {
    let granted: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(granted ? .green : .red)
            Text(granted ? "Granted" : "Not Granted")
                .foregroundColor(.secondary)
        }
    }
}

import AVFoundation
