import SwiftUI
import AppKit

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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        
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
        
        if !micPermission || !accessibilityPermission {
            // Show onboarding window
            DispatchQueue.main.async {
                self.showOnboarding()
            }
        } else {
            // Load model and start listening for hotkey
            await transcriptionManager.initialize()
        }
    }
    
    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 350),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to AudioType"
        window.center()
        window.contentView = NSHostingView(rootView: OnboardingView {
            window.close()
            Task {
                await self.transcriptionManager.initialize()
            }
        })
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
