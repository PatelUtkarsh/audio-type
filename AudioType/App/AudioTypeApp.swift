import AppKit
import SwiftUI

@main
struct AudioTypeApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    Settings {
      SettingsView()
    }
  }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
  static let onboardingCompletedKey = "onboardingCompleted"

  private var statusItem: NSStatusItem!
  private var menuBarController: MenuBarController!
  private var transcriptionManager: TranscriptionManager!
  private var onboardingWindow: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Hide dock icon
    NSApp.setActivationPolicy(.accessory)

    // Migrate any secrets from legacy file store to Keychain
    KeychainHelper.migrateFromFileStoreIfNeeded()

    // Initialize managers
    transcriptionManager = TranscriptionManager.shared
    menuBarController = MenuBarController(transcriptionManager: transcriptionManager)

    // Set up status bar
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    menuBarController.setupStatusItem(statusItem)

    // Check permissions on launch
    Task {
      await checkPermissions()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    transcriptionManager.cleanup()
  }

  private func checkPermissions() async {
    let micPermission = await Permissions.checkMicrophone()
    let accessibilityPermission = Permissions.checkAccessibility()
    let engineAvailable = EngineResolver.anyEngineAvailable
    let allGood = micPermission && accessibilityPermission && engineAvailable

    if allGood {
      markOnboardingCompleted()
      await transcriptionManager.initialize()
      return
    }

    // If the user already completed onboarding before but accessibility is
    // now failing, it's almost always a cdhash mismatch after a fresh release
    // (TCC.db still says granted, but AXIsProcessTrusted returns false because
    // the saved cdhash no longer matches the ad-hoc-signed binary). Show a
    // narrow re-approval prompt instead of the full first-run onboarding.
    let onboardingDone = UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey)
    if onboardingDone && micPermission && engineAvailable && !accessibilityPermission {
      await MainActor.run {
        showReapprovePrompt()
      }
      return
    }

    await MainActor.run {
      showOnboarding()
    }
  }

  fileprivate func markOnboardingCompleted() {
    UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
  }

  fileprivate func startTranscriptionIfNeeded() {
    Task {
      await self.transcriptionManager.initialize()
    }
  }

  fileprivate func dismissOnboarding() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      self.onboardingWindow?.orderOut(nil)
      self.onboardingWindow = nil
    }
  }

  private func showOnboarding() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 450, height: 480),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.title = "Welcome to AudioType"
    window.center()
    window.isReleasedWhenClosed = false

    // Retain the window
    self.onboardingWindow = window

    window.contentView = NSHostingView(
      rootView: OnboardingView { [weak self] in
        guard let self = self else { return }
        self.markOnboardingCompleted()
        self.dismissOnboarding()
        self.startTranscriptionIfNeeded()
      })
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func showReapprovePrompt() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.title = "AudioType needs re-approval"
    window.center()
    window.isReleasedWhenClosed = false
    self.onboardingWindow = window

    window.contentView = NSHostingView(
      rootView: ReapproveAccessibilityView { [weak self] in
        guard let self = self else { return }
        self.dismissOnboarding()
        self.startTranscriptionIfNeeded()
      })
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
