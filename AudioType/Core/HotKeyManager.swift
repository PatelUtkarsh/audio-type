import Foundation
import Carbon
import AppKit
import os.log

enum HotKeyEvent {
    case keyDown
    case keyUp
}

class HotKeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let callback: (HotKeyEvent) -> Void
    private var isKeyDown = false
    
    private let logger = Logger(subsystem: "com.audiotype", category: "HotKeyManager")
    
    // Default hotkey: Cmd + Shift + Space
    private let modifierFlags: CGEventFlags = [.maskCommand, .maskShift]
    private let keyCode: CGKeyCode = 49  // Space key
    
    init(callback: @escaping (HotKeyEvent) -> Void) {
        self.callback = callback
    }
    
    func startListening() {
        guard eventTap == nil else {
            logger.warning("Already listening for hotkeys")
            return
        }
        
        // Create event tap
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        guard let tap = CGEvent.tapCreate(
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
        ) else {
            logger.error("Failed to create event tap. Accessibility permission may be required.")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            logger.info("Hotkey listener started (Cmd+Shift+Space)")
        }
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
        isKeyDown = false
        
        logger.info("Hotkey listener stopped")
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle tap disabled event (can happen if system disables it)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }
        
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        // Check if our modifier keys are pressed (Cmd + Shift)
        let hasModifiers = flags.contains(.maskCommand) && flags.contains(.maskShift)
        
        // Check if Space key is pressed
        let isSpaceKey = keyCode == self.keyCode
        
        if type == .keyDown && hasModifiers && isSpaceKey && !isKeyDown {
            isKeyDown = true
            callback(.keyDown)
            // Consume the event so it doesn't propagate
            return nil
        }
        
        if type == .keyUp && isSpaceKey && isKeyDown {
            isKeyDown = false
            callback(.keyUp)
            // Consume the event
            return nil
        }
        
        // If modifiers are released while key is down, treat as key up
        if type == .flagsChanged && isKeyDown && !hasModifiers {
            isKeyDown = false
            callback(.keyUp)
        }
        
        return Unmanaged.passRetained(event)
    }
    
    deinit {
        stopListening()
    }
}
