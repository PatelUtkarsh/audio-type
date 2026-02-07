import AVFoundation
import ServiceManagement
import SwiftUI

struct SettingsView: View {
  @AppStorage("launchAtLogin") private var launchAtLogin = false
  @State private var selectedModel = GroqModel.current
  @State private var selectedLanguage = TranscriptionLanguage.current
  @State private var apiKey: String = ""
  @State private var isApiKeySet: Bool = GroqEngine.isConfigured
  @State private var apiKeySaveError: String?

  var body: some View {
    Form {
      Section {
        LabeledContent("Hotkey") {
          Text("Hold fn")
            .foregroundColor(.secondary)
        }

        // Groq API Key
        HStack {
          SecureField("Groq API Key", text: $apiKey)
            .textFieldStyle(.roundedBorder)

          Button(isApiKeySet ? "Update" : "Save") {
            saveApiKey()
          }
          .disabled(apiKey.isEmpty)
        }

        if isApiKeySet {
          HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(AudioTypeTheme.coral)
              .font(.caption)
            Text("API key configured")
              .foregroundColor(.secondary)
              .font(.caption)
          }
        }

        if let error = apiKeySaveError {
          Text(error)
            .foregroundColor(.red)
            .font(.caption)
        }

        if !isApiKeySet {
          Button("Get free API key") {
            if let url = URL(string: "https://console.groq.com/keys") {
              NSWorkspace.shared.open(url)
            }
          }
          .font(.caption)
        }

        Picker("Model", selection: $selectedModel) {
          ForEach(GroqModel.allCases, id: \.self) { model in
            Text(model.displayName)
              .tag(model)
          }
        }
        .pickerStyle(.menu)
        .onChange(of: selectedModel) { newModel in
          GroqModel.current = newModel
        }

        Picker("Language", selection: $selectedLanguage) {
          ForEach(TranscriptionLanguage.allCases) { lang in
            Text(lang.displayName)
              .tag(lang)
          }
        }
        .pickerStyle(.menu)
        .onChange(of: selectedLanguage) { newLang in
          TranscriptionLanguage.current = newLang
        }
      } header: {
        Text("Transcription (Groq)")
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
          Text("2.1.0")
            .foregroundColor(.secondary)
        }

        Link("View on GitHub", destination: URL(string: "https://github.com/PatelUtkarsh/audio-type")!)
      } header: {
        Text("About")
      }
    }
    .formStyle(.grouped)
    .frame(width: 400, height: 420)
  }

  private func saveApiKey() {
    apiKeySaveError = nil
    do {
      try GroqEngine.setApiKey(apiKey)
      isApiKeySet = true
      apiKey = ""  // Clear the field after saving
      // Notify TranscriptionManager
      Task { @MainActor in
        TranscriptionManager.shared.onApiKeyChanged()
      }
    } catch {
      apiKeySaveError = "Failed to save: \(error.localizedDescription)"
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
        .foregroundColor(granted ? AudioTypeTheme.coral : .red)
      Text(granted ? "Granted" : "Not Granted")
        .foregroundColor(.secondary)
    }
  }
}
