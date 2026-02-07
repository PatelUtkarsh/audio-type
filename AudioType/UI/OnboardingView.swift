import AVFoundation
import SwiftUI

struct OnboardingView: View {
  @State private var microphoneGranted = false
  @State private var accessibilityGranted = false
  @State private var apiKeyConfigured = GroqEngine.isConfigured
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
          .foregroundColor(.accentColor)

        Text("Welcome to AudioType")
          .font(.title)
          .fontWeight(.semibold)

        Text("Voice-to-text, powered by Groq")
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

        // API Key Step
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 12) {
            Image(systemName: "key.fill")
              .font(.title2)
              .foregroundColor(.accentColor)
              .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
              Text("Groq API Key")
                .fontWeight(.medium)
              Text("Free cloud transcription")
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            if apiKeyConfigured {
              Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            }
          }

          if !apiKeyConfigured {
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

            Button("Get free API key") {
              if let url = URL(string: "https://console.groq.com/keys") {
                NSWorkspace.shared.open(url)
              }
            }
            .font(.caption)
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

      // Continue Button
      Button(action: completeOnboarding) {
        Text(canContinue ? "Get Started" : "Complete Setup Above")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(!canContinue)
      .padding(.horizontal)
      .padding(.bottom)
    }
    .frame(width: 450, height: 480)
    .onAppear {
      checkPermissions()
    }
    .onReceive(timer) { _ in
      // Continuously check permissions
      microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
      accessibilityGranted = Permissions.checkAccessibility()
      apiKeyConfigured = GroqEngine.isConfigured

      // Auto-complete when all three are ready
      if canContinue && !hasAutoCompleted {
        hasAutoCompleted = true
        onComplete()
      }
    }
  }

  private var canContinue: Bool {
    microphoneGranted && accessibilityGranted && apiKeyConfigured
  }

  private func checkPermissions() {
    microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    accessibilityGranted = Permissions.checkAccessibility()
    apiKeyConfigured = GroqEngine.isConfigured
  }

  private func requestMicrophone() {
    Task {
      microphoneGranted = await Permissions.checkMicrophone()
    }
  }

  private func requestAccessibility() {
    Permissions.openAccessibilitySettings()
  }

  private func saveApiKey() {
    apiKeySaveError = nil
    do {
      try GroqEngine.setApiKey(apiKeyText)
      apiKeyConfigured = true
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
        .foregroundColor(.accentColor)
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
          .foregroundColor(.green)
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
