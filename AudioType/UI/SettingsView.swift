import AVFoundation
import ServiceManagement
import Speech
import SwiftUI

struct SettingsView: View {
  @AppStorage("launchAtLogin") private var launchAtLogin = false
  @State private var selectedEngine = TranscriptionEngineType.current
  @State private var selectedGroqModel = GroqModel.current
  @State private var selectedOpenAIModel = OpenAIModel.current
  @State private var selectedLanguage = TranscriptionLanguage.current

  // Groq key state
  @State private var groqApiKey: String = ""
  @State private var isGroqKeySet: Bool = GroqEngine.isConfigured
  @State private var groqKeySaveError: String?

  // OpenAI key state
  @State private var openaiApiKey: String = ""
  @State private var isOpenAIKeySet: Bool = OpenAIEngine.isConfigured
  @State private var openaiKeySaveError: String?

  var body: some View {
    Form {
      // MARK: - Engine Selection
      Section {
        Picker("Engine", selection: $selectedEngine) {
          ForEach(TranscriptionEngineType.allCases) { engine in
            Text(engine.displayName)
              .tag(engine)
          }
        }
        .pickerStyle(.menu)
        .onChange(of: selectedEngine) { newEngine in
          TranscriptionEngineType.current = newEngine
          Task { @MainActor in
            TranscriptionManager.shared.onEngineConfigChanged()
          }
        }

        let activeName = TranscriptionManager.shared.activeEngineName
        if !activeName.isEmpty {
          HStack(spacing: 4) {
            Image(systemName: "cpu")
              .font(.caption)
            Text("Active: \(activeName)")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      } header: {
        Text("Transcription Engine")
      }

      // MARK: - Groq Settings
      Section {
        apiKeyField(
          label: "Groq API Key",
          text: $groqApiKey,
          isSet: isGroqKeySet,
          saveError: groqKeySaveError,
          onSave: saveGroqKey
        )

        if !isGroqKeySet {
          Button("Get free API key") {
            openURL("https://console.groq.com/keys")
          }
          .font(.caption)
        }

        Picker("Model", selection: $selectedGroqModel) {
          ForEach(GroqModel.allCases, id: \.self) { model in
            Text(model.displayName).tag(model)
          }
        }
        .pickerStyle(.menu)
        .onChange(of: selectedGroqModel) { newModel in
          GroqModel.current = newModel
        }
      } header: {
        Text("Groq (Cloud)")
      }

      // MARK: - OpenAI Settings
      Section {
        apiKeyField(
          label: "OpenAI API Key",
          text: $openaiApiKey,
          isSet: isOpenAIKeySet,
          saveError: openaiKeySaveError,
          onSave: saveOpenAIKey
        )

        if !isOpenAIKeySet {
          Button("Get API key") {
            openURL("https://platform.openai.com/api-keys")
          }
          .font(.caption)
        }

        Picker("Model", selection: $selectedOpenAIModel) {
          ForEach(OpenAIModel.allCases, id: \.self) { model in
            Text(model.displayName).tag(model)
          }
        }
        .pickerStyle(.menu)
        .onChange(of: selectedOpenAIModel) { newModel in
          OpenAIModel.current = newModel
        }
      } header: {
        Text("OpenAI (Cloud)")
      }

      // MARK: - Apple Speech Settings
      Section {
        HStack {
          Text("Availability")
          Spacer()
          if AppleSpeechEngine.isSupported {
            HStack(spacing: 4) {
              Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AudioTypeTheme.coral)
                .font(.caption)
              Text("Supported")
                .foregroundColor(.secondary)
                .font(.caption)
            }
          } else {
            Text("Not supported")
              .foregroundColor(.secondary)
              .font(.caption)
          }
        }

        HStack {
          Text("Permission")
          Spacer()
          PermissionStatusView(
            granted: Permissions.isSpeechRecognitionAuthorized
          )
        }

        if !Permissions.isSpeechRecognitionAuthorized {
          Button("Grant Speech Recognition") {
            Task {
              _ = await Permissions.checkSpeechRecognition()
            }
          }
          .font(.caption)
        }
      } header: {
        Text("Apple Speech (On-Device)")
      }

      // MARK: - Language
      Section {
        Picker("Language", selection: $selectedLanguage) {
          ForEach(TranscriptionLanguage.allCases) { lang in
            Text(lang.displayName).tag(lang)
          }
        }
        .pickerStyle(.menu)
        .onChange(of: selectedLanguage) { newLang in
          TranscriptionLanguage.current = newLang
        }
      } header: {
        Text("Language")
      }

      // MARK: - General
      Section {
        LabeledContent("Hotkey") {
          Text("Hold fn")
            .foregroundColor(.secondary)
        }

        Toggle("Launch at Login", isOn: $launchAtLogin)
          .onChange(of: launchAtLogin) { newValue in
            setLaunchAtLogin(newValue)
          }
      } header: {
        Text("General")
      }

      // MARK: - Permissions
      Section {
        HStack {
          Text("Microphone")
          Spacer()
          PermissionStatusView(granted: checkMicPermission())
        }

        HStack {
          Text("Accessibility")
          Spacer()
          PermissionStatusView(
            granted: Permissions.checkAccessibility()
          )
        }

        Button("Open Accessibility Settings") {
          Permissions.openAccessibilitySettings()
        }
      } header: {
        Text("Permissions")
      }

      // MARK: - About
      Section {
        HStack {
          Text("Version")
          Spacer()
          Text("2.1.0")
            .foregroundColor(.secondary)
        }

        Link(
          "View on GitHub",
          destination: URL(
            string: "https://github.com/PatelUtkarsh/audio-type"
          )!
        )
      } header: {
        Text("About")
      }
    }
    .formStyle(.grouped)
    .frame(width: 400, height: 680)
  }

  // MARK: - Shared API key field

  @ViewBuilder
  private func apiKeyField(
    label: String,
    text: Binding<String>,
    isSet: Bool,
    saveError: String?,
    onSave: @escaping () -> Void
  ) -> some View {
    HStack {
      SecureField(label, text: text)
        .textFieldStyle(.roundedBorder)

      Button(isSet ? "Update" : "Save") {
        onSave()
      }
      .disabled(text.wrappedValue.isEmpty)
    }

    if isSet {
      HStack(spacing: 4) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(AudioTypeTheme.coral)
          .font(.caption)
        Text("API key configured")
          .foregroundColor(.secondary)
          .font(.caption)
      }
    }

    if let error = saveError {
      Text(error)
        .foregroundColor(.red)
        .font(.caption)
    }
  }

  // MARK: - Actions

  private func saveGroqKey() {
    groqKeySaveError = nil
    do {
      try GroqEngine.setApiKey(groqApiKey)
      isGroqKeySet = true
      groqApiKey = ""
      Task { @MainActor in
        TranscriptionManager.shared.onApiKeyChanged()
      }
    } catch {
      groqKeySaveError = "Failed to save: \(error.localizedDescription)"
    }
  }

  private func saveOpenAIKey() {
    openaiKeySaveError = nil
    do {
      try OpenAIEngine.setApiKey(openaiApiKey)
      isOpenAIKeySet = true
      openaiApiKey = ""
      Task { @MainActor in
        TranscriptionManager.shared.onEngineConfigChanged()
      }
    } catch {
      openaiKeySaveError = "Failed to save: \(error.localizedDescription)"
    }
  }

  private func checkMicPermission() -> Bool {
    AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
  }

  private func openURL(_ string: String) {
    if let url = URL(string: string) {
      NSWorkspace.shared.open(url)
    }
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
