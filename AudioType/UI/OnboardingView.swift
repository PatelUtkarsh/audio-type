import AVFoundation
import SwiftUI

struct OnboardingView: View {
  @State private var step = 0
  @State private var microphoneGranted = false
  @State private var accessibilityGranted = false
  @State private var isDownloadingModel = false
  @State private var downloadProgress: Double = 0

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

        Text("Voice-to-text, instantly")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
      .padding(.top)

      Divider()

      // Permission Steps
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
      }
      .padding(.horizontal)

      Spacer()

      // Continue Button
      Button(action: completeOnboarding) {
        if isDownloadingModel {
          HStack {
            ProgressView()
              .scaleEffect(0.8)
            Text("Downloading model...")
          }
          .frame(maxWidth: .infinity)
        } else {
          Text(canContinue ? "Get Started" : "Grant Permissions")
            .frame(maxWidth: .infinity)
        }
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(!canContinue || isDownloadingModel)
      .padding(.horizontal)
      .padding(.bottom)
    }
    .frame(width: 400, height: 380)
    .onAppear {
      checkPermissions()
    }
  }

  private var canContinue: Bool {
    microphoneGranted && accessibilityGranted
  }

  private func checkPermissions() {
    microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    accessibilityGranted = Permissions.checkAccessibility()
  }

  private func requestMicrophone() {
    Task {
      microphoneGranted = await Permissions.checkMicrophone()
    }
  }

  private func requestAccessibility() {
    Permissions.openAccessibilitySettings()

    // Poll for accessibility permission
    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
      if Permissions.checkAccessibility() {
        accessibilityGranted = true
        timer.invalidate()
      }
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
