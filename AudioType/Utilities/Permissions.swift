import AVFoundation
import AppKit
import Foundation

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

  /// Open System Settings to Accessibility pane
  static func openAccessibilitySettings() {
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    {
      NSWorkspace.shared.open(url)
    }
  }

  /// Open System Settings to Microphone pane
  static func openMicrophoneSettings() {
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    {
      NSWorkspace.shared.open(url)
    }
  }
}
