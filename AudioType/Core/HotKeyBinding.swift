import AppKit
import Foundation

/// A user-configurable hold-to-record hotkey binding.
///
/// Only modifier-style keys are supported (fn, Shift, Cmd, Option, Control, Caps Lock).
/// Left and right variants of Shift/Cmd/Option/Control are distinct so the user can
/// dedicate one side to AudioType without breaking normal shortcuts on the other.
struct HotKeyBinding: Codable, Equatable {
  let keyCode: Int64
  let flagMask: UInt64
  let displayName: String

  // MARK: - Known bindings

  static let fn = HotKeyBinding(
    keyCode: 63,
    flagMask: CGEventFlags.maskSecondaryFn.rawValue,
    displayName: "fn"
  )
  static let leftShift = HotKeyBinding(
    keyCode: 56,
    flagMask: CGEventFlags.maskShift.rawValue,
    displayName: "Left Shift"
  )
  static let rightShift = HotKeyBinding(
    keyCode: 60,
    flagMask: CGEventFlags.maskShift.rawValue,
    displayName: "Right Shift"
  )
  static let leftCommand = HotKeyBinding(
    keyCode: 55,
    flagMask: CGEventFlags.maskCommand.rawValue,
    displayName: "Left Cmd"
  )
  static let rightCommand = HotKeyBinding(
    keyCode: 54,
    flagMask: CGEventFlags.maskCommand.rawValue,
    displayName: "Right Cmd"
  )
  static let leftOption = HotKeyBinding(
    keyCode: 58,
    flagMask: CGEventFlags.maskAlternate.rawValue,
    displayName: "Left Option"
  )
  static let rightOption = HotKeyBinding(
    keyCode: 61,
    flagMask: CGEventFlags.maskAlternate.rawValue,
    displayName: "Right Option"
  )
  static let leftControl = HotKeyBinding(
    keyCode: 59,
    flagMask: CGEventFlags.maskControl.rawValue,
    displayName: "Left Control"
  )
  static let rightControl = HotKeyBinding(
    keyCode: 62,
    flagMask: CGEventFlags.maskControl.rawValue,
    displayName: "Right Control"
  )
  static let capsLock = HotKeyBinding(
    keyCode: 57,
    flagMask: CGEventFlags.maskAlphaShift.rawValue,
    displayName: "Caps Lock"
  )

  static let allKnown: [HotKeyBinding] = [
    .fn,
    .leftShift, .rightShift,
    .leftCommand, .rightCommand,
    .leftOption, .rightOption,
    .leftControl, .rightControl,
    .capsLock
  ]

  static let defaultBinding: HotKeyBinding = .fn

  // MARK: - Lookup

  /// Look up a known binding by keyCode. Returns nil if the key is not a recognized modifier.
  static func recognize(keyCode: Int64) -> HotKeyBinding? {
    allKnown.first { $0.keyCode == keyCode }
  }
}

/// Persistence + change-notification for the active hotkey binding.
enum HotKeyBindingStore {
  private static let userDefaultsKey = "hotKeyBinding"
  static let didChangeNotification = Notification.Name("hotKeyBindingChanged")

  static var current: HotKeyBinding {
    get {
      guard
        let data = UserDefaults.standard.data(forKey: userDefaultsKey),
        let decoded = try? JSONDecoder().decode(HotKeyBinding.self, from: data)
      else {
        return .defaultBinding
      }
      // If the stored binding refers to an unknown keyCode (downgrade / removed binding),
      // fall back to the default.
      if HotKeyBinding.recognize(keyCode: decoded.keyCode) == nil {
        return .defaultBinding
      }
      return decoded
    }
    set {
      if let data = try? JSONEncoder().encode(newValue) {
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
      }
      NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
  }
}
