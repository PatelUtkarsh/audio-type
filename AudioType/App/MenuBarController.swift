import AppKit
import SwiftUI

class MenuBarController: NSObject {
  private weak var statusItem: NSStatusItem?
  private var transcriptionManager: TranscriptionManager
  private var recordingWindow: NSWindow?
  private var hotkeyMenuItems: [NSMenuItem] = []

  init(transcriptionManager: TranscriptionManager) {
    self.transcriptionManager = transcriptionManager
    super.init()

    // Observe state changes
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(stateDidChange),
      name: .transcriptionStateChanged,
      object: nil
    )
  }

  func setupStatusItem(_ statusItem: NSStatusItem) {
    self.statusItem = statusItem

    if let button = statusItem.button {
      button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "AudioType")
      button.image?.isTemplate = true
    }

    let menu = NSMenu()

    let statusMenuItem = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")
    statusMenuItem.tag = 100  // Tag to identify status item
    menu.addItem(statusMenuItem)

    menu.addItem(NSMenuItem.separator())

    // Hotkey submenu
    let hotkeyMenu = NSMenu()
    let hotkeyMenuItem = NSMenuItem(title: "Hotkey", action: nil, keyEquivalent: "")
    hotkeyMenuItem.submenu = hotkeyMenu

    // Add hotkey options
    for trigger in HotKeyTrigger.allCases {
      let item = NSMenuItem(
        title: trigger.displayName,
        action: #selector(changeHotkey(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = trigger
      hotkeyMenu.addItem(item)
      hotkeyMenuItems.append(item)
    }

    DispatchQueue.main.async { [weak self] in
      self?.updateHotkeyMenuCheckmarks()
    }
    menu.addItem(hotkeyMenuItem)

    menu.addItem(NSMenuItem.separator())

    let settingsItem = NSMenuItem(
      title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
    settingsItem.target = self
    menu.addItem(settingsItem)

    menu.addItem(NSMenuItem.separator())

    let quitItem = NSMenuItem(title: "Quit AudioType", action: #selector(quit), keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)

    statusItem.menu = menu
  }

  @MainActor @objc private func changeHotkey(_ sender: NSMenuItem) {
    guard let trigger = sender.representedObject as? HotKeyTrigger else { return }

    // Update the hotkey manager
    transcriptionManager.setHotkey(trigger)

    // Update checkmarks
    updateHotkeyMenuCheckmarks()
  }

  @MainActor private func updateHotkeyMenuCheckmarks() {
    let currentTrigger = transcriptionManager.currentHotkey

    for item in hotkeyMenuItems {
      if let trigger = item.representedObject as? HotKeyTrigger {
        item.state = (trigger == currentTrigger) ? .on : .off
      }
    }
  }

  @objc private func stateDidChange(_ notification: Notification) {
    guard let state = notification.userInfo?["state"] as? TranscriptionState else { return }

    DispatchQueue.main.async {
      self.updateUI(for: state)
    }
  }

  private func updateUI(for state: TranscriptionState) {
    guard let button = statusItem?.button else { return }

    switch state {
    case .idle:
      button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Ready")
      hideRecordingIndicator()
      updateStatusMenuItem("Ready")

    case .recording:
      button.image = NSImage(
        systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
      showRecordingIndicator()
      updateStatusMenuItem("Recording...")

    case .processing:
      button.image = NSImage(
        systemSymbolName: "ellipsis.circle.fill", accessibilityDescription: "Processing")
      updateRecordingIndicator(text: "Processing...")
      updateStatusMenuItem("Processing...")

    case .error(let message):
      button.image = NSImage(
        systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Error")
      hideRecordingIndicator()
      updateStatusMenuItem("Error: \(message)")
    }

    button.image?.isTemplate = true
  }

  private func updateStatusMenuItem(_ text: String) {
    if let menu = statusItem?.menu,
      let item = menu.item(withTag: 100)
    {
      item.title = text
    }
  }

  private func showRecordingIndicator() {
    if recordingWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
      )
      window.level = .floating
      window.backgroundColor = .clear
      window.isOpaque = false
      window.hasShadow = true
      window.contentView = NSHostingView(rootView: RecordingOverlay(text: "Recording..."))

      // Position near mouse cursor
      let mouseLocation = NSEvent.mouseLocation
      window.setFrameOrigin(NSPoint(x: mouseLocation.x - 100, y: mouseLocation.y + 20))

      recordingWindow = window
    }

    recordingWindow?.orderFront(nil)
  }

  private func updateRecordingIndicator(text: String) {
    if let window = recordingWindow {
      window.contentView = NSHostingView(rootView: RecordingOverlay(text: text))
    }
  }

  private func hideRecordingIndicator() {
    recordingWindow?.orderOut(nil)
  }

  @objc private func openSettings() {
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }
}

extension Notification.Name {
  static let transcriptionStateChanged = Notification.Name("transcriptionStateChanged")
}
