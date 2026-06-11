import AVFoundation
import AppKit
import ServiceManagement
import Speech
import SwiftUI

struct SettingsView: View {
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

  // Launch at login state — source of truth is SMAppService.mainApp.status
  @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
  @State private var launchAtLoginRequiresApproval: Bool =
    SMAppService.mainApp.status == .requiresApproval
  @State private var launchAtLoginError: String?

  // Hotkey binding state
  @State private var hotKeyBinding: HotKeyBinding = HotKeyBindingStore.current
  @State private var isCapturingHotKey = false
  @State private var hotKeyCaptureWarning: String?
  @State private var hotKeyEventMonitor: Any?

  // Live typing state
  @State private var liveTyping: Bool = LiveTypingSetting.isEnabled

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
        hotKeyRow

        Toggle("Live Typing", isOn: $liveTyping)
          .onChange(of: liveTyping) { newValue in
            LiveTypingSetting.isEnabled = newValue
          }
        Text("Type at natural pauses while you hold the hotkey, instead of all at once on release.")
          .font(.caption)
          .foregroundColor(.secondary)

        Toggle("Launch at Login", isOn: $launchAtLogin)
          .onChange(of: launchAtLogin) { newValue in
            setLaunchAtLogin(newValue)
          }

        if launchAtLoginRequiresApproval {
          VStack(alignment: .leading, spacing: 4) {
            Text("Approval needed in System Settings → Login Items.")
              .font(.caption)
              .foregroundColor(.secondary)
            Button("Open Login Items") {
              openLoginItemsSettings()
            }
            .font(.caption)
          }
        }

        if let error = launchAtLoginError {
          Text(error)
            .font(.caption)
            .foregroundColor(.red)
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
          Text("2.4.1")
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
    .onAppear {
      refreshLaunchAtLoginStatus()
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: NSApplication.didBecomeActiveNotification
      )
    ) { _ in
      refreshLaunchAtLoginStatus()
    }
    .onDisappear {
      stopHotKeyCapture(save: false)
    }
  }

  // MARK: - Hotkey row

  @ViewBuilder
  private var hotKeyRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("Hotkey")
        Spacer()
        Text("Hold \(hotKeyBinding.displayName)")
          .foregroundColor(.secondary)
        Button(isCapturingHotKey ? "Cancel" : "Change…") {
          if isCapturingHotKey {
            stopHotKeyCapture(save: false)
          } else {
            startHotKeyCapture()
          }
        }
      }

      if isCapturingHotKey {
        Text("Press a modifier key… (Esc to cancel)")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      if let warning = hotKeyCaptureWarning {
        Text(warning)
          .font(.caption)
          .foregroundColor(.red)
      }
    }
  }

  // MARK: - Hotkey capture

  private func startHotKeyCapture() {
    hotKeyCaptureWarning = nil
    isCapturingHotKey = true

    // Remove any stale monitor before installing a new one.
    if let monitor = hotKeyEventMonitor {
      NSEvent.removeMonitor(monitor)
      hotKeyEventMonitor = nil
    }

    hotKeyEventMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.flagsChanged, .keyDown]
    ) { event in
      // Esc cancels capture.
      if event.type == .keyDown && event.keyCode == 53 {
        stopHotKeyCapture(save: false)
        return nil
      }

      if event.type == .flagsChanged {
        let keyCode = Int64(event.keyCode)
        if let binding = HotKeyBinding.recognize(keyCode: keyCode) {
          hotKeyBinding = binding
          HotKeyBindingStore.current = binding
          stopHotKeyCapture(save: true)
          return nil
        }
        // flagsChanged for an unrecognized key shouldn't normally happen, but
        // guard anyway.
        hotKeyCaptureWarning = "That key isn't supported. Try Shift, Cmd, Option, Control, fn, or Caps Lock."
        return nil
      }

      // Any other keyDown (letter, F-key, etc.) is rejected; stay in capture mode.
      hotKeyCaptureWarning = "Please press a modifier key (Shift, Cmd, Option, Control, fn, or Caps Lock)."
      return nil
    }
  }

  private func stopHotKeyCapture(save: Bool) {
    if let monitor = hotKeyEventMonitor {
      NSEvent.removeMonitor(monitor)
      hotKeyEventMonitor = nil
    }
    isCapturingHotKey = false
    if save {
      hotKeyCaptureWarning = nil
    }
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
    launchAtLoginError = nil
    let service = SMAppService.mainApp
    do {
      if enabled {
        try service.register()
      } else {
        try service.unregister()
      }
    } catch {
      launchAtLoginError = "Couldn't update login item: \(error.localizedDescription)"
    }
    // Always re-sync from the system after attempting a change so the toggle
    // reflects reality (including the .requiresApproval case where register()
    // succeeds but macOS is waiting on user consent).
    refreshLaunchAtLoginStatus()
  }

  private func refreshLaunchAtLoginStatus() {
    let status = SMAppService.mainApp.status
    launchAtLogin = (status == .enabled)
    launchAtLoginRequiresApproval = (status == .requiresApproval)
  }

  private func openLoginItemsSettings() {
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extensionPoint"
    ) {
      NSWorkspace.shared.open(url)
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
