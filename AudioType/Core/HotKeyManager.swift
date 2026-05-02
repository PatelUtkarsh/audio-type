import AppKit
import Carbon
import Foundation
import os.log

enum HotKeyEvent {
  case keyDown
  case keyUp
}

class HotKeyManager {
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private let callback: (HotKeyEvent) -> Void
  private var isRecording = false

  // Retained pointer to self that the event-tap callback uses as refcon.
  // Holding self retained for the lifetime of the tap means the tap
  // callback is always safe to call back into self, even if the owner
  // releases its reference. We balance the retain in stopListening.
  private var refconRetained: Unmanaged<HotKeyManager>?

  // Track fn key state
  private var fnKeyWasPressed = false

  private let logger = Logger(subsystem: "com.audiotype", category: "HotKeyManager")

  init(callback: @escaping (HotKeyEvent) -> Void) {
    self.callback = callback
  }

  func startListening() {
    stopListening()

    // Use CGEventTap for fn key detection
    let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

    // Retain self for the duration of the tap. Released in stopListening.
    let retained = Unmanaged.passRetained(self)
    refconRetained = retained

    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
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
      return
    }

    eventTap = tap
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

    if let source = runLoopSource {
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
      CGEvent.tapEnable(tap: tap, enable: true)
    }

    logger.info("Hotkey listener started (Hold fn)")
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
    isRecording = false
    fnKeyWasPressed = false

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
    // Handle tap disabled event
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap = eventTap {
        CGEvent.tapEnable(tap: tap, enable: true)
      }
      return Unmanaged.passUnretained(event)
    }

    let flags = event.flags

    // Check for fn key via the secondary fn flag
    let fnPressed = flags.contains(.maskSecondaryFn)
    let hasCommand = flags.contains(.maskCommand)
    let hasShift = flags.contains(.maskShift)
    let hasOption = flags.contains(.maskAlternate)
    let hasControl = flags.contains(.maskControl)

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

    return Unmanaged.passUnretained(event)
  }

  deinit {
    stopListening()
  }
}
