import AppKit
import SwiftUI

/// Mira Sato's color system for AudioType.
/// Warm, voice-centric palette — coral for brand, amber for processing, system red for errors.
enum AudioTypeTheme {

  // MARK: – Brand

  /// Primary brand color — Soft Coral.  Warm, human, "I'm listening."
  static let coral = Color(red: 1.0, green: 107.0 / 255.0, blue: 107.0 / 255.0)

  /// Lighter coral for dark-mode waveform bars & hover states.
  static let coralLight = Color(red: 1.0, green: 142.0 / 255.0, blue: 142.0 / 255.0)

  /// Deeper coral for icon gradient bottom-right.
  static let coralDeep = Color(red: 232.0 / 255.0, green: 93.0 / 255.0, blue: 93.0 / 255.0)

  // MARK: – State: Processing

  /// Amber — "Your voice was heard, now I'm working."
  static let amber = Color(red: 1.0, green: 184.0 / 255.0, blue: 77.0 / 255.0)

  /// Lighter amber for dark-mode thinking dots.
  static let amberLight = Color(red: 1.0, green: 204.0 / 255.0, blue: 128.0 / 255.0)

  // MARK: – State: Recording (menu bar tint)

  /// Warm red for the menu-bar icon while recording.
  static let recordingRed = Color(red: 1.0, green: 77.0 / 255.0, blue: 77.0 / 255.0)

  // MARK: – NSColor equivalents (needed for NSImage tinting)

  static let nsRecordingRed = NSColor(red: 1.0, green: 77.0 / 255.0, blue: 77.0 / 255.0, alpha: 1.0)
  static let nsAmber = NSColor(red: 1.0, green: 184.0 / 255.0, blue: 77.0 / 255.0, alpha: 1.0)
  static let nsCoral = NSColor(red: 1.0, green: 107.0 / 255.0, blue: 107.0 / 255.0, alpha: 1.0)

  // MARK: – Adaptive helpers

  /// Waveform bar color — coral in light mode, lighter coral in dark mode.
  static var waveformColor: Color {
    let ns = NSColor(name: nil) { appearance in
      if appearance.bestMatch(from: [.darkAqua]) == .darkAqua {
        return NSColor(red: 1.0, green: 142.0 / 255.0, blue: 142.0 / 255.0, alpha: 1.0)
      }
      return NSColor(red: 1.0, green: 107.0 / 255.0, blue: 107.0 / 255.0, alpha: 1.0)
    }
    return Color(nsColor: ns)
  }

  /// Thinking-dot color — amber in light mode, lighter amber in dark mode.
  static var thinkingColor: Color {
    let ns = NSColor(name: nil) { appearance in
      if appearance.bestMatch(from: [.darkAqua]) == .darkAqua {
        return NSColor(red: 1.0, green: 204.0 / 255.0, blue: 128.0 / 255.0, alpha: 1.0)
      }
      return NSColor(red: 1.0, green: 184.0 / 255.0, blue: 77.0 / 255.0, alpha: 1.0)
    }
    return Color(nsColor: ns)
  }
}
