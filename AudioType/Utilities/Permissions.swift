import AVFoundation
import AppKit
import Foundation
import Speech

class Permissions {
  /// Check and request microphone permission
  static func checkMicrophone() async -> Bool {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)

    switch status {
    case .authorized:
      return true
    case .notDetermined:
      return await AVCaptureDevice.requestAccess(for: .audio)
    case .denied, .restricted:
      return false
    @unknown default:
      return false
    }
  }

  /// Check accessibility permission (required for keyboard simulation)
  static func checkAccessibility() -> Bool {
    // This will prompt the user if not already determined
    let options =
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  /// Prompt for accessibility permission
  static func promptAccessibility() -> Bool {
    let options =
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  // MARK: - Speech Recognition

  /// Check and request speech recognition permission.
  static func checkSpeechRecognition() async -> Bool {
    let status = SFSpeechRecognizer.authorizationStatus()
    switch status {
    case .authorized:
      return true
    case .notDetermined:
      return await AppleSpeechEngine.requestAuthorization()
    case .denied, .restricted:
      return false
    @unknown default:
      return false
    }
  }

  /// Whether speech recognition has already been authorized.
  static var isSpeechRecognitionAuthorized: Bool {
    SFSpeechRecognizer.authorizationStatus() == .authorized
  }

  // MARK: - System Settings

  /// Open System Settings to Accessibility pane
  static func openAccessibilitySettings() {
    let urlString =
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    if let url = URL(string: urlString) {
      NSWorkspace.shared.open(url)
    }
  }

  /// Open System Settings to Microphone pane
  static func openMicrophoneSettings() {
    let urlString =
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    if let url = URL(string: urlString) {
      NSWorkspace.shared.open(url)
    }
  }

  /// Open System Settings to Speech Recognition pane
  static func openSpeechRecognitionSettings() {
    let urlString =
      "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
    if let url = URL(string: urlString) {
      NSWorkspace.shared.open(url)
    }
  }
}
