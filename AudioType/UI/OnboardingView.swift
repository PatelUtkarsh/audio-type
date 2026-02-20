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
  @State private var hasAutoCompleted = false

  let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

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
              Text("Cloud transcription — faster & more accurate")
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
      // Continuously check permissions
      microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
      accessibilityGranted = Permissions.checkAccessibility()
      speechRecognitionGranted = Permissions.isSpeechRecognitionAuthorized
      anyCloudKeyConfigured = GroqEngine.isConfigured || OpenAIEngine.isConfigured

      // Auto-complete when all required permissions are ready and at least one engine works
      if canContinue && !hasAutoCompleted {
        hasAutoCompleted = true
        onComplete()
      }
    }
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
