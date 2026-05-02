import AppKit
import Carbon
import Foundation
import os.log

class TextInserter {
  private let logger = Logger(subsystem: "com.audiotype", category: "TextInserter")

  /// Above this length we paste via clipboard instead of synthesising one
  /// keystroke per character. Per-char synthesis costs ~1 ms each plus a
  /// fresh CGEventSource per char — for long dictations that's the dominant
  /// post-recording latency the user feels.
  private static let clipboardPasteThreshold = 30

  func insertText(_ text: String) {
    guard !text.isEmpty else { return }

    logger.info("Inserting text: \(text.prefix(50))...")

    if text.count > Self.clipboardPasteThreshold {
      insertTextViaClipboard(text)
    } else {
      insertTextViaKeystrokes(text)
    }

    logger.info("Text insertion complete")
  }

  /// Per-character keystroke synthesis. Used for short strings where
  /// clipboard paste's clipboard-restore quirks aren't worth it.
  private func insertTextViaKeystrokes(_ text: String) {
    // Cache the event source once for the whole insertion — creating one
    // per character was a measurable hot path.
    let source = CGEventSource(stateID: .hidSystemState)

    for char in text {
      insertCharacter(char, source: source)
      // Tiny delay so target apps don't drop events under load.
      usleep(1000)  // 1ms
    }
  }

  private func insertCharacter(_ char: Character, source: CGEventSource?) {
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
      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
    else {
      return
    }

    // Add Command modifier
    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand

    keyDown.post(tap: .cgSessionEventTap)
    keyUp.post(tap: .cgSessionEventTap)
  }
}
