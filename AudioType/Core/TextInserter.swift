import AppKit
import Carbon
import Foundation
import os.log

/// Marks the key events that AudioType posts, so its own hotkey listener can
/// tell them from the user's typing.
enum SyntheticKeyEvent {
  private static let userData: Int64 = 0x4155_4449_4F54  // "AUDIOT"

  static func mark(_ event: CGEvent) {
    event.setIntegerValueField(.eventSourceUserData, value: userData)
  }

  static func isMarked(_ event: CGEvent) -> Bool {
    event.getIntegerValueField(.eventSourceUserData) == userData
  }
}

@MainActor
final class TextInserter {
  private let logger = Logger(subsystem: "com.audiotype", category: "TextInserter")

  /// Above this length we paste via clipboard instead of synthesising one
  /// keystroke per character. Per-char synthesis costs ~1 ms each plus a
  /// fresh CGEventSource per char — for long dictations that's the dominant
  /// post-recording latency the user feels.
  private static let clipboardPasteThreshold = 30

  private let pasteboard: NSPasteboard

  /// Time the target app gets to read the pasteboard after Cmd+V. The
  /// pasteboard does not change again before this. The user's clipboard
  /// comes back twice this long after the last paste, so a chunk that
  /// follows at once joins the burst instead of racing the restore.
  private let pasteSettleDelay: Duration

  /// Marks the pasted text as temporary, so clipboard managers do not
  /// record each dictated chunk (nspasteboard.org convention).
  private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

  private let postPaste: () -> Void

  /// The user's clipboard, saved at the first paste of a burst of pastes
  /// and restored once after the last one.
  private var savedClipboard: [NSPasteboardItem] = []
  private var restoreTask: Task<Void, Never>?
  private var lastPasteTime: ContinuousClock.Instant?
  private var pastedChangeCount = 0

  /// - Parameter postPaste: Sends Cmd+V. Tests replace it so no key events
  ///   are posted.
  init(
    pasteboard: NSPasteboard = .general,
    pasteSettleDelay: Duration = .milliseconds(250),
    postPaste: (() -> Void)? = nil
  ) {
    self.pasteboard = pasteboard
    self.pasteSettleDelay = pasteSettleDelay
    self.postPaste = postPaste ?? { TextInserter.simulatePaste() }
  }

  func insertText(_ text: String) async {
    guard !text.isEmpty else { return }

    logger.info("Inserting text: \(text.prefix(50))...")

    if text.count > Self.clipboardPasteThreshold {
      await insertTextViaClipboard(text)
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

    // Clear modifier flags: with live typing the user is still physically
    // holding the hotkey (fn or a modifier), and synthetic events sourced
    // from hidSystemState would otherwise inherit it, turning plain
    // characters into modified keystrokes in some apps.
    keyDown.flags = []
    keyUp.flags = []
    SyntheticKeyEvent.mark(keyDown)
    SyntheticKeyEvent.mark(keyUp)

    // Post events
    keyDown.post(tap: .cgSessionEventTap)
    keyUp.post(tap: .cgSessionEventTap)
  }

  /// Insert text using clipboard (faster for long text, but replaces
  /// clipboard). Live Typing can paste two chunks back to back: the second
  /// paste waits until the target app had time to read the first, and the
  /// user's clipboard comes back once, after the last paste. Before, the
  /// second chunk replaced the pasteboard before the app read the first
  /// one, so it could paste twice while the first was lost.
  private func insertTextViaClipboard(_ text: String) async {
    if let lastPasteTime = lastPasteTime {
      let wait = pasteSettleDelay - (ContinuousClock.now - lastPasteTime)
      if wait > .zero {
        try? await Task.sleep(for: wait)
      }
    }
    // A cancelled session must not paste stale text.
    guard !Task.isCancelled else { return }

    // Part of a burst while the pasteboard still holds our last paste: the
    // clipboard saved at the first paste stays. If anything was copied
    // since, that is the clipboard to keep.
    let burstContinues = restoreTask != nil && pasteboard.changeCount == pastedChangeCount
    restoreTask?.cancel()
    if !burstContinues {
      savedClipboard = Self.snapshot(of: pasteboard)
    }

    let item = NSPasteboardItem()
    item.setString(text, forType: .string)
    item.setData(Data(), forType: Self.transientType)
    pasteboard.clearContents()
    pasteboard.writeObjects([item])
    pastedChangeCount = pasteboard.changeCount
    postPaste()
    lastPasteTime = .now

    restoreTask = Task { [weak self, restoreDelay = pasteSettleDelay * 2] in
      try? await Task.sleep(for: restoreDelay)
      guard !Task.isCancelled else { return }
      self?.restoreClipboard()
    }
  }

  private func restoreClipboard() {
    defer {
      savedClipboard = []
      restoreTask = nil
    }
    // The user copied something new after our paste: keep it.
    guard pasteboard.changeCount == pastedChangeCount else { return }
    pasteboard.clearContents()
    if !savedClipboard.isEmpty {
      pasteboard.writeObjects(savedClipboard)
    }
  }

  /// Copies every item with every type, not only plain text, so images,
  /// files and rich text survive the paste.
  private static func snapshot(of pasteboard: NSPasteboard) -> [NSPasteboardItem] {
    (pasteboard.pasteboardItems ?? []).map { item in
      let copy = NSPasteboardItem()
      for type in item.types {
        if let data = item.data(forType: type) {
          copy.setData(data, forType: type)
        }
      }
      return copy
    }
  }

  private static func simulatePaste() {
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
    SyntheticKeyEvent.mark(keyDown)
    SyntheticKeyEvent.mark(keyUp)

    keyDown.post(tap: .cgSessionEventTap)
    keyUp.post(tap: .cgSessionEventTap)
  }
}
