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

class AppDelegate: NSObject, NSApplicationDelegate {
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

    // Show onboarding if permissions are missing or no engine is usable
    if !micPermission || !accessibilityPermission || !EngineResolver.anyEngineAvailable {
      DispatchQueue.main.async {
        self.showOnboarding()
      }
    } else {
      // All set — start listening for hotkey
      await transcriptionManager.initialize()
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
        // Delay to let animations complete before releasing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          self?.onboardingWindow?.orderOut(nil)
          self?.onboardingWindow = nil
        }
        Task {
          await self?.transcriptionManager.initialize()
        }
      })
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
