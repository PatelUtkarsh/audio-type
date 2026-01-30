import Foundation
import Carbon
import AppKit
import os.log

class TextInserter {
    private let logger = Logger(subsystem: "com.audiotype", category: "TextInserter")
    
    func insertText(_ text: String) {
        guard !text.isEmpty else { return }
        
        logger.info("Inserting text: \(text.prefix(50))...")
        
        // Use CGEvent to simulate keyboard input
        for char in text {
            insertCharacter(char)
            // Small delay between characters for reliability
            usleep(1000)  // 1ms
        }
        
        logger.info("Text insertion complete")
    }
    
    private func insertCharacter(_ char: Character) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Create key down event
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
            logger.error("Failed to create keyDown event")
            return
        }
        
        // Create key up event
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            logger.error("Failed to create keyUp event")
            return
        }
        
        // Set the unicode string
        var utf16 = Array(String(char).utf16)
        keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        
        // Post events
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
    
    /// Insert text using clipboard (faster for long text, but replaces clipboard)
    func insertTextViaClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        
        // Save current clipboard content
        let pasteboard = NSPasteboard.general
        let oldContent = pasteboard.string(forType: .string)
        
        // Set new content
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Simulate Cmd+V
        simulatePaste()
        
        // Restore old clipboard after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let oldContent = oldContent {
                pasteboard.clearContents()
                pasteboard.setString(oldContent, forType: .string)
            }
        }
    }
    
    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // V key is keycode 9
        let vKeyCode: CGKeyCode = 9
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return
        }
        
        // Add Command modifier
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}
