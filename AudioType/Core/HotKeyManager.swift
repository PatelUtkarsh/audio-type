import AppKit
import Carbon
import Foundation
import os.log

enum HotKeyEvent {
  case keyDown
  case keyUp
}

enum HotKeyTrigger: String, CaseIterable {
  case fnKey = "fn"
  case doubleFn = "double-fn"
  case cmdShiftSpace = "cmd-shift-space"
  case optionSpace = "option-space"

  var displayName: String {
    switch self {
    case .fnKey: return "Hold fn"
    case .doubleFn: return "Double-tap fn"
    case .cmdShiftSpace: return "Cmd + Shift + Space"
    case .optionSpace: return "Option + Space"
    }
  }
}

class HotKeyManager {
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private let callback: (HotKeyEvent) -> Void
  private var isRecording = false
  private var fnKeyMonitor: Any?
  private var localMonitor: Any?

  // For double-tap detection
  private var lastFnPressTime: Date?
  private let doubleTapThreshold: TimeInterval = 0.3

  private let logger = Logger(subsystem: "com.audiotype", category: "HotKeyManager")

  var currentTrigger: HotKeyTrigger {
    didSet {
      UserDefaults.standard.set(currentTrigger.rawValue, forKey: "hotkeyTrigger")
      restartListening()
    }
  }

  init(callback: @escaping (HotKeyEvent) -> Void) {
    self.callback = callback
    // Load saved trigger or default to fn key
    if let saved = UserDefaults.standard.string(forKey: "hotkeyTrigger"),
      let trigger = HotKeyTrigger(rawValue: saved)
    {
      self.currentTrigger = trigger
    } else {
      self.currentTrigger = .fnKey
    }
  }

  func startListening() {
    stopListening()

    switch currentTrigger {
    case .fnKey, .doubleFn:
      startFnKeyMonitoring()
    case .cmdShiftSpace, .optionSpace:
      startEventTapMonitoring()
    }

    logger.info("Hotkey listener started (\(self.currentTrigger.displayName))")
  }

  private func startFnKeyMonitoring() {
    // Use NSEvent global monitor for fn key (flagsChanged events)
    fnKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      self?.handleFlagsChanged(event)
    }

    // Also monitor local events (when app is focused)
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      self?.handleFlagsChanged(event)
      return event
    }
  }

  private func startEventTapMonitoring() {
    let eventMask =
      (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
      | (1 << CGEventType.flagsChanged.rawValue)

    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(eventMask),
        callback: { proxy, type, event, refcon in
          guard let refcon = refcon else { return Unmanaged.passRetained(event) }
          let manager = Unmanaged<HotKeyManager>.fromOpaque(refcon).takeUnretainedValue()
          return manager.handleEvent(proxy: proxy, type: type, event: event)
        },
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      logger.error("Failed to create event tap. Accessibility permission may be required.")
      return
    }

    eventTap = tap
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

    if let source = runLoopSource {
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
      CGEvent.tapEnable(tap: tap, enable: true)
    }
  }

  func stopListening() {
    if let monitor = fnKeyMonitor {
      NSEvent.removeMonitor(monitor)
      fnKeyMonitor = nil
    }

    if let monitor = localMonitor {
      NSEvent.removeMonitor(monitor)
      localMonitor = nil
    }

    if let tap = eventTap {
      CGEvent.tapEnable(tap: tap, enable: false)
    }

    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    }

    eventTap = nil
    runLoopSource = nil
    isRecording = false

    logger.info("Hotkey listener stopped")
  }

  private func restartListening() {
    stopListening()
    startListening()
  }

  private func handleFlagsChanged(_ event: NSEvent) {
    let fnPressed = event.modifierFlags.contains(.function)

    // Ignore if other modifier keys are also pressed (avoid conflicts)
    let otherModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    let hasOtherModifiers = !event.modifierFlags.intersection(otherModifiers).isEmpty

    if currentTrigger == .fnKey {
      // Hold fn mode
      if fnPressed && !hasOtherModifiers && !isRecording {
        isRecording = true
        logger.info("fn key pressed - starting recording")
        callback(.keyDown)
      } else if !fnPressed && isRecording {
        isRecording = false
        logger.info("fn key released - stopping recording")
        callback(.keyUp)
      }
    } else if currentTrigger == .doubleFn {
      // Double-tap fn mode
      if fnPressed && !hasOtherModifiers {
        let now = Date()
        if let lastPress = lastFnPressTime,
          now.timeIntervalSince(lastPress) < doubleTapThreshold
        {
          // Double tap detected
          if !isRecording {
            isRecording = true
            logger.info("Double fn tap - starting recording")
            callback(.keyDown)
          } else {
            isRecording = false
            logger.info("Double fn tap - stopping recording")
            callback(.keyUp)
          }
          lastFnPressTime = nil
        } else {
          lastFnPressTime = now
        }
      }
    }
  }

  private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<
    CGEvent
  >? {
    // Handle tap disabled event
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap = eventTap {
        CGEvent.tapEnable(tap: tap, enable: true)
      }
      return Unmanaged.passRetained(event)
    }

    let flags = event.flags
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    let spaceKeyCode: Int64 = 49

    switch currentTrigger {
    case .cmdShiftSpace:
      let hasModifiers = flags.contains(.maskCommand) && flags.contains(.maskShift)
      let isSpaceKey = keyCode == spaceKeyCode

      if type == .keyDown && hasModifiers && isSpaceKey && !isRecording {
        isRecording = true
        callback(.keyDown)
        return nil
      }

      if type == .keyUp && isSpaceKey && isRecording {
        isRecording = false
        callback(.keyUp)
        return nil
      }

      if type == .flagsChanged && isRecording && !hasModifiers {
        isRecording = false
        callback(.keyUp)
      }

    case .optionSpace:
      let hasOption = flags.contains(.maskAlternate)
      let noOtherModifiers =
        !flags.contains(.maskCommand) && !flags.contains(.maskControl)
        && !flags.contains(.maskShift)
      let isSpaceKey = keyCode == spaceKeyCode

      if type == .keyDown && hasOption && noOtherModifiers && isSpaceKey && !isRecording {
        isRecording = true
        callback(.keyDown)
        return nil
      }

      if type == .keyUp && isSpaceKey && isRecording {
        isRecording = false
        callback(.keyUp)
        return nil
      }

      if type == .flagsChanged && isRecording && !hasOption {
        isRecording = false
        callback(.keyUp)
      }

    default:
      break
    }

    return Unmanaged.passRetained(event)
  }

  deinit {
    stopListening()
  }
}
