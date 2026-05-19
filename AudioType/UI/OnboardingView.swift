import AVFoundation
import Speech
import SwiftUI

struct OnboardingView: View {
  @State private var microphoneGranted = false
  @State private var accessibilityGranted = false
  @State private var speechRecognitionGranted = false
  @State private var anyCloudKeyConfigured = GroqEngine.isConfigured || OpenAIEngine.isConfigured
  @State private var apiKeyText = ""
  @State private var apiKeySaveError: String?
  @State private var didAutoComplete = false

  // Poll every 2 seconds to pick up permission changes the user made in
  // System Settings. Cheaper than the previous 0.5s cadence and we stop
  // polling entirely once everything's ready (see onReceive below).
  let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

  let onComplete: () -> Void

  var body: some View {
    VStack(spacing: 24) {
      // Header
      VStack(spacing: 8) {
        Image(systemName: "mic.fill")
          .font(.system(size: 48))
          .foregroundColor(AudioTypeTheme.coral)

        Text("Welcome to AudioType")
          .font(.title)
          .fontWeight(.semibold)

        Text("Voice-to-text for your Mac")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
      .padding(.top)

      Divider()

      // Setup Steps
      VStack(alignment: .leading, spacing: 16) {
        PermissionRow(
          icon: "mic.fill",
          title: "Microphone Access",
          description: "To hear your voice",
          isGranted: microphoneGranted,
          action: requestMicrophone
        )

        PermissionRow(
          icon: "accessibility",
          title: "Accessibility Access",
          description: "To type text into apps",
          isGranted: accessibilityGranted,
          action: requestAccessibility
        )

        PermissionRow(
          icon: "waveform.badge.mic",
          title: "Speech Recognition",
          description: "For on-device transcription",
          isGranted: speechRecognitionGranted,
          action: requestSpeechRecognition
        )

        // API Key Step (optional)
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 12) {
            Image(systemName: "key.fill")
              .font(.title2)
              .foregroundColor(AudioTypeTheme.coral)
              .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 4) {
                Text("Groq API Key")
                  .fontWeight(.medium)
                Text("(optional)")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              Text("Cloud transcription - faster & more accurate")
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            if anyCloudKeyConfigured {
              Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AudioTypeTheme.coral)
            }
          }

          if !anyCloudKeyConfigured {
            HStack {
              SecureField("Paste your API key", text: $apiKeyText)
                .textFieldStyle(.roundedBorder)

              Button("Save") {
                saveApiKey()
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
              .disabled(apiKeyText.isEmpty)
            }
            .padding(.leading, 44)

            HStack(spacing: 12) {
              Button("Get free API key") {
                if let url = URL(string: "https://console.groq.com/keys") {
                  NSWorkspace.shared.open(url)
                }
              }
              .font(.caption)

              Text("or skip to use Apple Speech")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.leading, 44)

            if let error = apiKeySaveError {
              Text(error)
                .foregroundColor(.red)
                .font(.caption)
                .padding(.leading, 44)
            }
          }
        }
        .padding(.vertical, 8)
      }
      .padding(.horizontal)

      Spacer()

      // Engine info badge
      if canContinue {
        let isCloud = GroqEngine.isConfigured || OpenAIEngine.isConfigured
        let engineName =
          GroqEngine.isConfigured
          ? "Groq Whisper"
          : OpenAIEngine.isConfigured ? "OpenAI" : "Apple Speech"
        HStack(spacing: 4) {
          Image(systemName: isCloud ? "cloud.fill" : "cpu")
            .font(.caption)
          Text("Will use \(engineName) for transcription")
            .font(.caption)
        }
        .foregroundColor(.secondary)
      }

      // Continue Button
      Button(action: completeOnboarding) {
        Text(canContinue ? "Get Started" : "Complete Setup Above")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(AudioTypeTheme.coral)
      .controlSize(.large)
      .disabled(!canContinue)
      .padding(.horizontal)
      .padding(.bottom)
    }
    .frame(width: 450, height: 560)
    .onAppear {
      checkPermissions()
    }
    .onReceive(timer) { _ in
      refreshPermissionState()

      // Once every required permission lands, finish onboarding automatically.
      // This avoids the trap where the user grants AX in System Settings,
      // returns to AudioType, but the hotkey listener never starts because
      // they haven't clicked "Get Started" yet.
      if canContinue && !didAutoComplete {
        didAutoComplete = true
        onComplete()
      }
    }
  }

  private func refreshPermissionState() {
    microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    accessibilityGranted = Permissions.checkAccessibility()
    speechRecognitionGranted = Permissions.isSpeechRecognitionAuthorized
    anyCloudKeyConfigured = GroqEngine.isConfigured || OpenAIEngine.isConfigured
  }

  /// The user can proceed once mic + accessibility are granted AND at least one engine is usable.
  private var canContinue: Bool {
    microphoneGranted && accessibilityGranted
      && (anyCloudKeyConfigured || speechRecognitionGranted)
  }

  private func checkPermissions() {
    microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    accessibilityGranted = Permissions.checkAccessibility()
    speechRecognitionGranted = Permissions.isSpeechRecognitionAuthorized
    anyCloudKeyConfigured = GroqEngine.isConfigured || OpenAIEngine.isConfigured
  }

  private func requestMicrophone() {
    Task {
      microphoneGranted = await Permissions.checkMicrophone()
    }
  }

  private func requestAccessibility() {
    Permissions.openAccessibilitySettings()
  }

  private func requestSpeechRecognition() {
    Task {
      speechRecognitionGranted = await Permissions.checkSpeechRecognition()
    }
  }

  private func saveApiKey() {
    apiKeySaveError = nil
    do {
      try GroqEngine.setApiKey(apiKeyText)
      anyCloudKeyConfigured = true
      apiKeyText = ""
    } catch {
      apiKeySaveError = "Failed to save: \(error.localizedDescription)"
    }
  }

  private func completeOnboarding() {
    onComplete()
  }
}

struct PermissionRow: View {
  let icon: String
  let title: String
  let description: String
  let isGranted: Bool
  let action: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundColor(AudioTypeTheme.coral)
        .frame(width: 32)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .fontWeight(.medium)
        Text(description)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      if isGranted {
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(AudioTypeTheme.coral)
      } else {
        Button("Grant") {
          action()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    }
    .padding(.vertical, 8)
  }
}

/// Slim follow-up shown after a re-install/update when the user has already
/// granted Accessibility before, but the new binary's cdhash doesn't match
/// the saved TCC entry so `AXIsProcessTrusted` returns false. Recovering
/// only requires removing + re-adding AudioType in Accessibility settings.
struct ReapproveAccessibilityView: View {
  let onApproved: () -> Void

  // Poll every 2 seconds and dismiss as soon as AX trust comes back.
  let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()
  @State private var didFinish = false

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "lock.shield")
        .font(.system(size: 40))
        .foregroundColor(AudioTypeTheme.coral)

      Text("AudioType needs re-approval")
        .font(.title3)
        .fontWeight(.semibold)

      Text(
        "After updating AudioType, macOS needs you to re-approve "
          + "Accessibility access. In System Settings, remove AudioType from "
          + "the Accessibility list and add it back from /Applications."
      )
      .font(.callout)
      .multilineTextAlignment(.center)
      .foregroundColor(.secondary)
      .padding(.horizontal)
      .fixedSize(horizontal: false, vertical: true)

      Button("Open Accessibility Settings") {
        Permissions.openAccessibilitySettings()
      }
      .buttonStyle(.borderedProminent)
      .tint(AudioTypeTheme.coral)

      Text("This window closes itself when access is restored.")
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .padding(24)
    .frame(width: 420)
    .onReceive(timer) { _ in
      if Permissions.checkAccessibility() && !didFinish {
        didFinish = true
        onApproved()
      }
    }
  }
}
