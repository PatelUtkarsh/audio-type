import AppKit
import SwiftUI

class MenuBarController: NSObject, NSWindowDelegate {
  private weak var statusItem: NSStatusItem?
  private var transcriptionManager: TranscriptionManager
  private var recordingWindow: NSWindow?
  private var settingsWindow: NSWindow?

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
      button.image = NSImage(
        systemSymbolName: "waveform.circle.fill", accessibilityDescription: "AudioType")
      button.image?.isTemplate = true
    }

    let menu = NSMenu()

    let statusMenuItem = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")
    statusMenuItem.tag = 100  // Tag to identify status item
    menu.addItem(statusMenuItem)

    // Hotkey info
    let hotkeyItem = NSMenuItem(title: "Hotkey: Hold fn", action: nil, keyEquivalent: "")
    hotkeyItem.isEnabled = false
    menu.addItem(hotkeyItem)

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
      button.image = NSImage(
        systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Ready")
      hideRecordingIndicator()
      updateStatusMenuItem("Ready")

    case .recording:
      button.image = NSImage(
        systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Recording")
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
      let item = menu.item(withTag: 100) {
      item.title = text
    }
  }

  private func showRecordingIndicator() {
    if recordingWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 180, height: 50),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
      )
      window.level = .floating
      window.backgroundColor = .clear
      window.isOpaque = false
      window.hasShadow = true

      // Position at bottom center of screen
      if let screen = NSScreen.main {
        let screenFrame = screen.visibleFrame
        let windowWidth: CGFloat = 180
        let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
        let y = screenFrame.origin.y + 100  // 100px from bottom
        window.setFrameOrigin(NSPoint(x: x, y: y))
      }

      recordingWindow = window
    }

    // Always update content to "Recording..." when showing
    let hostingView = NSHostingView(rootView: RecordingOverlay(text: "Recording..."))
    hostingView.frame = NSRect(x: 0, y: 0, width: 180, height: 50)
    recordingWindow?.contentView = hostingView
    recordingWindow?.orderFront(nil)
  }

  private func updateRecordingIndicator(text: String) {
    if let window = recordingWindow {
      let hostingView = NSHostingView(rootView: RecordingOverlay(text: text))
      hostingView.frame = NSRect(x: 0, y: 0, width: 180, height: 50)
      window.contentView = hostingView
    }
  }

  private func hideRecordingIndicator() {
    recordingWindow?.orderOut(nil)
  }

  @objc private func openSettings() {
    if settingsWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
        styleMask: [.titled, .closable, .miniaturizable],
        backing: .buffered,
        defer: false
      )
      window.title = "AudioType Settings"
      window.center()
      window.isReleasedWhenClosed = false
      window.delegate = self
      window.contentView = NSHostingView(rootView: SettingsView())
      settingsWindow = window
    }

    // For LSUIElement apps, we need to temporarily become a regular app to show windows
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.makeKeyAndOrderFront(nil)
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  // MARK: - NSWindowDelegate

  func windowWillClose(_ notification: Notification) {
    // Return to accessory mode when settings window closes (hide from dock)
    if (notification.object as? NSWindow) == settingsWindow {
      NSApp.setActivationPolicy(.accessory)
    }
  }
}

extension Notification.Name {
  static let transcriptionStateChanged = Notification.Name("transcriptionStateChanged")
}
