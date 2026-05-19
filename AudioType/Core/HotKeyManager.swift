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

  // Track whether the bound key is currently held.
  private var bindingKeyWasPressed = false

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
      // If we were tracking a press on the old binding, drop it.
      self.bindingKeyWasPressed = false
    }

    // Use CGEventTap for modifier-key detection
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

    logger.info("Hotkey listener started (Hold \(self.activeBinding.displayName, privacy: .public))")
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
    bindingKeyWasPressed = false

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
    // Handle tap disabled event
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap = eventTap {
        CGEvent.tapEnable(tap: tap, enable: true)
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

    if bindingBitSet && !bindingKeyWasPressed && !isRecording {
      bindingKeyWasPressed = true
      isRecording = true
      logger.info("\(binding.displayName, privacy: .public) pressed - starting recording")
      DispatchQueue.main.async {
        self.callback(.keyDown)
      }
    } else if !bindingBitSet && bindingKeyWasPressed && isRecording {
      bindingKeyWasPressed = false
      isRecording = false
      logger.info("\(binding.displayName, privacy: .public) released - stopping recording")
      DispatchQueue.main.async {
        self.callback(.keyUp)
      }
    } else if !bindingBitSet {
      bindingKeyWasPressed = false
    }

    return Unmanaged.passUnretained(event)
  }

  deinit {
    stopListening()
  }
}
