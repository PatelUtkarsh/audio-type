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

  // For double-tap detection
  private var lastFnPressTime: Date?
  private let doubleTapThreshold: TimeInterval = 0.3

  // Track fn key state
  private var fnKeyWasPressed = false

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

    // Use CGEventTap for all triggers - it's more reliable
    let eventMask: CGEventMask =
      (1 << CGEventType.keyDown.rawValue)
      | (1 << CGEventType.keyUp.rawValue)
      | (1 << CGEventType.flagsChanged.rawValue)

    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
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

    logger.info("Hotkey listener started (\(self.currentTrigger.displayName))")
  }

  func stopListening() {
    if let tap = eventTap {
      CGEvent.tapEnable(tap: tap, enable: false)
    }

    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    }

    eventTap = nil
    runLoopSource = nil
    isRecording = false
    fnKeyWasPressed = false

    logger.info("Hotkey listener stopped")
  }

  private func restartListening() {
    stopListening()
    startListening()
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

    // Check for fn key via the secondary fn flag
    // On Mac, fn key sets a special flag
    let fnPressed = flags.contains(.maskSecondaryFn)
    let hasCommand = flags.contains(.maskCommand)
    let hasShift = flags.contains(.maskShift)
    let hasOption = flags.contains(.maskAlternate)
    let hasControl = flags.contains(.maskControl)

    // Debug: print all flag changes
    if type == .flagsChanged {
      print("DEBUG flagsChanged: fn=\(fnPressed) cmd=\(hasCommand) shift=\(hasShift) opt=\(hasOption) ctrl=\(hasControl) rawFlags=\(flags.rawValue)")
    }

    switch currentTrigger {
    case .fnKey:
      // Hold fn mode - detect via flagsChanged
      if type == .flagsChanged {
        let onlyFn = fnPressed && !hasCommand && !hasShift && !hasOption && !hasControl

        if onlyFn && !fnKeyWasPressed && !isRecording {
          fnKeyWasPressed = true
          isRecording = true
          logger.info("fn key pressed - starting recording")
          DispatchQueue.main.async {
            self.callback(.keyDown)
          }
        } else if !fnPressed && fnKeyWasPressed && isRecording {
          fnKeyWasPressed = false
          isRecording = false
          logger.info("fn key released - stopping recording")
          DispatchQueue.main.async {
            self.callback(.keyUp)
          }
        } else if !fnPressed {
          fnKeyWasPressed = false
        }
      }

    case .doubleFn:
      // Double-tap fn mode
      if type == .flagsChanged && fnPressed && !hasCommand && !hasShift && !hasOption && !hasControl
      {
        if !fnKeyWasPressed {
          fnKeyWasPressed = true
          let now = Date()
          if let lastPress = lastFnPressTime,
            now.timeIntervalSince(lastPress) < doubleTapThreshold
          {
            // Double tap detected
            if !isRecording {
              isRecording = true
              logger.info("Double fn tap - starting recording")
              DispatchQueue.main.async {
                self.callback(.keyDown)
              }
            } else {
              isRecording = false
              logger.info("Double fn tap - stopping recording")
              DispatchQueue.main.async {
                self.callback(.keyUp)
              }
            }
            lastFnPressTime = nil
          } else {
            lastFnPressTime = now
          }
        }
      } else if type == .flagsChanged && !fnPressed {
        fnKeyWasPressed = false
      }

    case .cmdShiftSpace:
      let hasModifiers = hasCommand && hasShift
      let isSpaceKey = keyCode == spaceKeyCode

      if type == .keyDown && hasModifiers && isSpaceKey && !isRecording {
        isRecording = true
        DispatchQueue.main.async {
          self.callback(.keyDown)
        }
        return nil  // Consume event
      }

      if type == .keyUp && isSpaceKey && isRecording {
        isRecording = false
        DispatchQueue.main.async {
          self.callback(.keyUp)
        }
        return nil  // Consume event
      }

      if type == .flagsChanged && isRecording && !hasModifiers {
        isRecording = false
        DispatchQueue.main.async {
          self.callback(.keyUp)
        }
      }

    case .optionSpace:
      let onlyOption = hasOption && !hasCommand && !hasControl && !hasShift
      let isSpaceKey = keyCode == spaceKeyCode

      if type == .keyDown && onlyOption && isSpaceKey && !isRecording {
        isRecording = true
        DispatchQueue.main.async {
          self.callback(.keyDown)
        }
        return nil  // Consume event
      }

      if type == .keyUp && isSpaceKey && isRecording {
        isRecording = false
        DispatchQueue.main.async {
          self.callback(.keyUp)
        }
        return nil  // Consume event
      }

      if type == .flagsChanged && isRecording && !hasOption {
        isRecording = false
        DispatchQueue.main.async {
          self.callback(.keyUp)
        }
      }
    }

    return Unmanaged.passRetained(event)
  }

  deinit {
    stopListening()
  }
}
