import AppKit
import SwiftUI

// MARK: - Utility Actions

extension AppViewModel {
    /// Reveal the app in Finder so the user can drag it to /Applications.
    func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting(
            [URL(fileURLWithPath: Bundle.main.bundlePath)]
        )
    }

    /// Open the bundled license text for the installed app.
    func openBundledLicense() {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("LICENSE.txt"),
              FileManager.default.fileExists(atPath: url.path)
        else {
            statusMessage = "Bundled license not found"
            return
        }

        if !NSWorkspace.shared.open(url) {
            statusMessage = "Unable to open bundled license"
        }
    }

    /// Start an email draft for commercial licensing inquiries.
    func requestCommercialLicense() {
        let mailto = "mailto:gmlupatelli@gmail.com"
            + "?subject=Desktop%20Icon%20Position%20Commercial%20License"
        guard let url = URL(string: mailto) else {
            statusMessage = "Commercial licensing contact unavailable"
            return
        }

        if !NSWorkspace.shared.open(url) {
            statusMessage = "Unable to open mail client"
        }
    }

    /// Open (or bring to front) the Settings window.
    func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: SettingsView(viewModel: self))
        let windowSize = NSSize(width: 480, height: 460)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Desktop Icon Position"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Permission Helpers

extension AppViewModel {
    /// Re-check Automation permission (e.g. after user grants access in System Settings).
    func recheckPermission() {
        let wasGranted = permissionGranted
        permissionGranted = FinderService.checkPermission()
        let actions = automationCoordinator.planPermissionRecheck(
            wasGranted: wasGranted,
            isGranted: permissionGranted,
            autoRestoreOnLaunch: autoRestoreOnLaunch,
            autoSaveOnTimer: autoSaveOnTimer
        )
        applyAutomationActions(actions)
    }

    /// Open System Settings to the Automation privacy pane.
    func openAutomationSettings() {
        let prefURL = "x-apple.systempreferences:"
            + "com.apple.preference.security?Privacy_Automation"
        if let url = URL(string: prefURL) {
            NSWorkspace.shared.open(url)
        }
    }

    func handleFinderError(_ error: Error, action: String) {
        if FinderService.isPermissionError(error) {
            permissionGranted = false
            statusMessage = "Permission required \u{2014} open System Settings to grant access"
            stopAutoSaveTimer()
        } else {
            statusMessage = "\(action) failed: \(error.localizedDescription)"
        }
    }

    func resumeAfterPermissionGranted(runLaunchActions: Bool) {
        let actions = automationCoordinator.planResumeAfterPermissionGranted(
            runLaunchActions: runLaunchActions,
            autoRestoreOnLaunch: autoRestoreOnLaunch,
            autoSaveOnTimer: autoSaveOnTimer
        )
        applyAutomationActions(actions)
    }

    func applyAutomationActions(_ actions: [AutomationCoordinator.Action]) {
        for action in actions {
            switch action {
            case let .setStatusMessage(message):
                statusMessage = message
            case .restoreAuto:
                restoreAuto()
            case .startAutoSaveTimer:
                startAutoSaveTimer()
            case .stopAutoSaveTimer:
                stopAutoSaveTimer()
            }
        }
    }
}
