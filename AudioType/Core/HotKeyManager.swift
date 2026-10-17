import AppKit
import Carbon
import Foundation
import os.log

enum HotKeyEvent: Equatable {
  case keyDown
  /// The hotkey was released. `otherKeyPressed` is true when another key
  /// went down soon after the press: a shortcut such as fn+Delete or
  /// fn+arrow, not a dictation.
  case keyUp(otherKeyPressed: Bool)
  /// The hold ended without a normal release (the binding changed).
  /// Discard the recording.
  case cancel
}

/// Hold-to-record state for the hotkey, kept apart from the event tap so it
/// is unit-testable. One flag for "held" (two flags could drift apart and
/// leave a recording that no release could stop).
struct HotKeyHoldState {
  /// Another key pressed this soon after the hotkey went down marks the
  /// hold as a shortcut. Keys pressed later in a long hold do not count.
  static let shortcutWindow: TimeInterval = 1.0

  private(set) var isHeld = false
  private var pressTime: TimeInterval = 0
  private var otherKeyPressed = false

  /// The bound key's flag changed. Returns the event to send, if any.
  mutating func bindingFlagChanged(isDown: Bool, at time: TimeInterval) -> HotKeyEvent? {
    if isDown && !isHeld {
      isHeld = true
      pressTime = time
      otherKeyPressed = false
      return .keyDown
    }
    if !isDown && isHeld {
      isHeld = false
      return .keyUp(otherKeyPressed: otherKeyPressed)
    }
    return nil
  }

  /// A key other than the hotkey went down (not one AudioType typed).
  mutating func otherKeyDown(at time: TimeInterval) {
    if isHeld && time - pressTime < Self.shortcutWindow {
      otherKeyPressed = true
    }
  }

  /// The binding changed or the listener stopped. A hold in progress can no
  /// longer end with a release of the watched key, so it is cancelled.
  mutating func reset() -> HotKeyEvent? {
    defer { isHeld = false }
    return isHeld ? .cancel : nil
  }
}

extension Notification.Name {
  /// Posted when `CGEvent.tapCreate` fails, almost always because Accessibility
  /// permission isn't actually trusted for the running binary.
  static let hotKeyTapCreationFailed = Notification.Name("hotKeyTapCreationFailed")
}

class HotKeyManager {
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private let callback: (HotKeyEvent) -> Void

  // Retained pointer to self that the event-tap callback uses as refcon.
  // Holding self retained for the lifetime of the tap means the tap
  // callback is always safe to call back into self, even if the owner
  // releases its reference. We balance the retain in stopListening.
  private var refconRetained: Unmanaged<HotKeyManager>?

  // Whether the bound key is held, and whether another key joined it.
  private var hold = HotKeyHoldState()

  // The active hotkey binding, refreshed from HotKeyBindingStore on start
  // and whenever the user changes it via Settings.
  private var activeBinding: HotKeyBinding = HotKeyBindingStore.current
  private var bindingChangeObserver: NSObjectProtocol?

  private let logger = Logger(subsystem: "com.audiotype", category: "HotKeyManager")

  init(callback: @escaping (HotKeyEvent) -> Void) {
    self.callback = callback
  }

  func startListening() {
    stopListening()

    activeBinding = HotKeyBindingStore.current

    // Observe binding changes so the user can rebind without restarting the app.
    bindingChangeObserver = NotificationCenter.default.addObserver(
      forName: HotKeyBindingStore.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self = self else { return }
      let newBinding = HotKeyBindingStore.current
      self.logger.info("Hotkey binding changed to \(newBinding.displayName, privacy: .public)")
      self.activeBinding = newBinding
      // A hold of the old binding can no longer end with a release (its
      // key is not watched any more), so cancel it. Before, the recording
      // then ran on with no way to stop it.
      if let event = self.hold.reset() {
        self.callback(event)
      }
    }

    // Prefer a listen-only (passive) tap: we never modify or consume events,
    // and an active tap forces every flagsChanged event system-wide through
    // this process synchronously before delivery. Listen-only taps need the
    // ListenEvent (Input Monitoring) grant, which Accessibility trust - the
    // permission this app already requires for CGEventPost - is a superset
    // of. Preflight anyway: a listen-only tap created without the grant can
    // come back non-nil yet silently deliver no events, whereas .defaultTap
    // returns nil without Accessibility, which drives our failure UX below.
    let options: CGEventTapOptions = CGPreflightListenEventAccess() ? .listenOnly : .defaultTap

    // flagsChanged drives the hold. keyDown only tells a shortcut
    // (fn+Delete, fn+arrow) from a dictation; nothing about the key is kept.
    // The active fallback tap skips keyDown: every keystroke would then wait
    // for this process.
    var eventMask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
    if options == .listenOnly {
      eventMask |= 1 << CGEventType.keyDown.rawValue
    }

    // Retain self for the duration of the tap. Released in stopListening.
    let retained = Unmanaged.passRetained(self)
    refconRetained = retained

    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: options,
        eventsOfInterest: eventMask,
        callback: { proxy, type, event, refcon in
          // The event is owned by the system; pass it back unretained.
          guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
          let manager = Unmanaged<HotKeyManager>.fromOpaque(refcon).takeUnretainedValue()
          return manager.handleEvent(proxy: proxy, type: type, event: event)
        },
        userInfo: retained.toOpaque()
      )
    else {
      // Tap creation failed — release the retain we just took.
      retained.release()
      refconRetained = nil
      logger.error("Failed to create event tap. Accessibility permission may be required.")
      // Surface the failure so the menu bar can show an error state and the
      // user understands the hotkey isn't going to work.
      NotificationCenter.default.post(name: .hotKeyTapCreationFailed, object: nil)
      return
    }

    eventTap = tap
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

    if let source = runLoopSource {
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
      CGEvent.tapEnable(tap: tap, enable: true)
    }

    logger.info(
      "Hotkey listener started (Hold \(self.activeBinding.displayName, privacy: .public), \(options == .listenOnly ? "listen-only" : "active", privacy: .public) tap)"
    )
  }

  func stopListening() {
    if let tap = eventTap {
      CGEvent.tapEnable(tap: tap, enable: false)
      // Invalidating the mach port stops further callbacks before we drop
      // the run loop source.
      CFMachPortInvalidate(tap)
    }

    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    }

    eventTap = nil
    runLoopSource = nil
    _ = hold.reset()

    if let observer = bindingChangeObserver {
      NotificationCenter.default.removeObserver(observer)
      bindingChangeObserver = nil
    }

    // Balance the retain taken in startListening. Done last so any
    // callback already in-flight against the now-disabled tap still sees
    // a live self via its own takeUnretainedValue.
    refconRetained?.release()
    refconRetained = nil

    logger.info("Hotkey listener stopped")
  }

  private func handleEvent(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent
  ) -> Unmanaged<CGEvent>? {
    // Handle tap disabled event. Timeout disabling only happens to active
    // taps (the .defaultTap fallback path); passive taps never block event
    // delivery so the watchdog has nothing to fire on. Kept for the fallback.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap = eventTap {
        CGEvent.tapEnable(tap: tap, enable: true)
      }
      return Unmanaged.passUnretained(event)
    }

    let now = ProcessInfo.processInfo.systemUptime

    if type == .keyDown {
      // Keys that AudioType itself types (Live Typing) are not the user's.
      if !SyntheticKeyEvent.isMarked(event) {
        hold.otherKeyDown(at: now)
      }
      return Unmanaged.passUnretained(event)
    }

    guard type == .flagsChanged else {
      return Unmanaged.passUnretained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let binding = activeBinding

    // Only react to flag changes on the bound key. Other modifiers being held
    // (e.g. Left Shift while the user presses Right Cmd as the binding) are
    // ignored intentionally.
    guard keyCode == binding.keyCode else {
      return Unmanaged.passUnretained(event)
    }

    let bindingBitSet = (event.flags.rawValue & binding.flagMask) != 0

    if let hotKeyEvent = hold.bindingFlagChanged(isDown: bindingBitSet, at: now) {
      let action = hotKeyEvent == .keyDown ? "pressed - starting recording" : "released - stopping recording"
      logger.info("\(binding.displayName, privacy: .public) \(action, privacy: .public)")
      DispatchQueue.main.async {
        self.callback(hotKeyEvent)
      }
    }

    return Unmanaged.passUnretained(event)
  }

  deinit {
    stopListening()
  }
}
