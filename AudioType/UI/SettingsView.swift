import AVFoundation
import ServiceManagement
import SwiftUI

struct SettingsView: View {
  @AppStorage("launchAtLogin") private var launchAtLogin = false
  @State private var selectedModel: WhisperModel = WhisperModel.current
  @State private var isDownloading = false
  @State private var downloadError: String?

  var body: some View {
    Form {
      Section {
        LabeledContent("Hotkey") {
          Text(TranscriptionManager.shared.currentHotkey.displayName)
            .foregroundColor(.secondary)
        }

        Picker("Model", selection: $selectedModel) {
          ForEach(WhisperModel.allCases, id: \.self) { model in
            HStack {
              Text(model.displayName)
              if WhisperEngine.isModelDownloaded(model) {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundColor(.green)
                  .font(.caption)
              }
            }
            .tag(model)
          }
        }
        .pickerStyle(.menu)
        .onChange(of: selectedModel) { newModel in
          handleModelChange(newModel)
        }
        .disabled(isDownloading)

        if isDownloading {
          HStack {
            ProgressView()
              .scaleEffect(0.8)
            Text("Downloading model...")
              .foregroundColor(.secondary)
          }
        }

        if let error = downloadError {
          Text(error)
            .foregroundColor(.red)
            .font(.caption)
        }
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
          Text("1.1.0")
            .foregroundColor(.secondary)
        }

        Link("View on GitHub", destination: URL(string: "https://github.com")!)
      } header: {
        Text("About")
      }
    }
    .formStyle(.grouped)
    .frame(width: 400, height: 400)
  }

  private func handleModelChange(_ newModel: WhisperModel) {
    downloadError = nil

    // Check if model is already downloaded
    if WhisperEngine.isModelDownloaded(newModel) {
      WhisperModel.current = newModel
      // Notify to reload engine
      NotificationCenter.default.post(name: .modelChanged, object: newModel)
      return
    }

    // Need to download
    isDownloading = true
    Task {
      do {
        try await WhisperEngine.downloadModelFile(newModel)
        await MainActor.run {
          isDownloading = false
          WhisperModel.current = newModel
          NotificationCenter.default.post(name: .modelChanged, object: newModel)
        }
      } catch {
        await MainActor.run {
          isDownloading = false
          downloadError = "Failed to download: \(error.localizedDescription)"
          // Revert selection
          selectedModel = WhisperModel.current
        }
      }
    }
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

extension Notification.Name {
  static let modelChanged = Notification.Name("modelChanged")
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
