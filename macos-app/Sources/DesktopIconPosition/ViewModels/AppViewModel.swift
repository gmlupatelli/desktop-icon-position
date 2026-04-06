import AppKit
import SwiftUI
import Observation
import Foundation
import ServiceManagement

/// Central state and logic for the menu bar app.
/// Orchestrates save, restore, and display-change monitoring.
@MainActor
@Observable
final class AppViewModel {

    // MARK: - Published State

    var profiles: [ProfileManager.ProfileSummary] = []
    var statusMessage: String = "Ready"
    var permissionGranted: Bool = true

    /// Task handle for the adaptive verify chain, so a new restore can cancel it.
    private var verifyTask: Task<Void, Never>?

    /// True while a restore (including its verify chain) is in progress.
    private var isRestoring = false

    /// Task handle for the pending display-change handler, for debounce/cancellation.
    private var displayChangeTask: Task<Void, Never>?

    private var isUpdatingLaunchAtLogin = false
    var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            guard !isUpdatingLaunchAtLogin else { return }
            isUpdatingLaunchAtLogin = true
            defer { isUpdatingLaunchAtLogin = false }
            if launchAtLogin && !isStableLocation {
                statusMessage = "Move app to /Applications for reliable Launch at Login"
                launchAtLogin = false
                return
            }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                statusMessage = "Launch at Login failed: \(error.localizedDescription)"
                // Revert to actual state on failure
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }
    var autoRestoreEnabled: Bool = UserDefaults.standard.bool(forKey: "autoRestoreEnabled") {
        didSet { UserDefaults.standard.set(autoRestoreEnabled, forKey: "autoRestoreEnabled") }
    }
    var autoRestoreOnLaunch: Bool = UserDefaults.standard.bool(forKey: "autoRestoreOnLaunch") {
        didSet { UserDefaults.standard.set(autoRestoreOnLaunch, forKey: "autoRestoreOnLaunch") }
    }
    var showAutoProfiles: Bool = UserDefaults.standard.bool(forKey: "showAutoProfiles") {
        didSet { UserDefaults.standard.set(showAutoProfiles, forKey: "showAutoProfiles") }
    }

    var autoSaveOnQuit: Bool = UserDefaults.standard.bool(forKey: "autoSaveOnQuit") {
        didSet { UserDefaults.standard.set(autoSaveOnQuit, forKey: "autoSaveOnQuit") }
    }
    var autoSaveOnTimer: Bool = UserDefaults.standard.bool(forKey: "autoSaveOnTimer") {
        didSet {
            UserDefaults.standard.set(autoSaveOnTimer, forKey: "autoSaveOnTimer")
            if autoSaveOnTimer { startAutoSaveTimer() } else { stopAutoSaveTimer() }
        }
    }
    /// Auto-save interval in minutes. Options: 5, 10, 15, 30, 60.
    var autoSaveIntervalMinutes: Int = {
        let stored = UserDefaults.standard.integer(forKey: "autoSaveIntervalMinutes")
        return stored > 0 ? stored : 15
    }() {
        didSet {
            UserDefaults.standard.set(autoSaveIntervalMinutes, forKey: "autoSaveIntervalMinutes")
            if autoSaveOnTimer { startAutoSaveTimer() }
        }
    }

    var visibleProfiles: [ProfileManager.ProfileSummary] {
        if showAutoProfiles { return profiles }
        return profiles.filter { !$0.name.hasPrefix("Auto-") }
    }

    /// Whether the app is running from a stable location suitable for Launch at Login.
    var isStableLocation: Bool {
        let path = Bundle.main.bundlePath
        // Stable: /Applications or ~/Applications
        if path.hasPrefix("/Applications/") { return true }
        if path.hasPrefix(NSHomeDirectory() + "/Applications/") { return true }
        return false
    }

    // MARK: - Private State

    private var displayObserver: NSObjectProtocol?
    private var lastFingerprint: String = ""
    private var autoSaveTimer: Timer?
    private let automationCoordinator = AutomationCoordinator()
    private var settingsWindow: NSWindow?

    // MARK: - Lifecycle

    func start() {
        if launchAtLogin && !isStableLocation {
            statusMessage = "Launch at Login disabled — move app to /Applications for reliable startup"
            launchAtLogin = false
        }

        // Enable launch at login by default on first run (only from a stable location)
        if !UserDefaults.standard.bool(forKey: "hasSetupLaunchAtLogin") {
            UserDefaults.standard.set(true, forKey: "hasSetupLaunchAtLogin")
            if isStableLocation {
                launchAtLogin = true
            }
        }

        refreshProfiles()
        lastFingerprint = DisplayService.fingerprint()
        startDisplayObserver()

        // Check Automation permission before any Finder operations
        permissionGranted = FinderService.checkPermission()
        guard permissionGranted else {
            statusMessage = "Permission required \u{2014} open System Settings to grant access"
            stopAutoSaveTimer()
            return
        }

        resumeAfterPermissionGranted(runLaunchActions: true)
    }

    func stop() {
        stopAutoSaveTimer()
        if let observer = displayObserver {
            NotificationCenter.default.removeObserver(observer)
            displayObserver = nil
        }
    }

    func quit() {
        if autoSaveOnQuit {
            saveAutoIfIconsExist()
        }
        stop()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Save

    /// Save current icon positions with a given profile name.
    func save(name: String) {
        save(name: name, allowReservedAutoName: false)
    }

    private func save(name: String, allowReservedAutoName: Bool) {
        let saveStart = CFAbsoluteTimeGetCurrent()
        do {
            statusMessage = "Saving..."
            let frames = TimingLog.measure("save: currentFrames") { DisplayService.currentFrames() }
            let fingerprint = TimingLog.measure("save: fingerprint") { DisplayService.fingerprint() }
            let settings = try TimingLog.measure("save: readSettings") { try FinderService.readSettings() }
            let icons = try TimingLog.measure("save: readIconPositions") { try FinderService.readIconPositions() }

            let profile = Profile(
                fingerprint: fingerprint,
                displays: frames,
                settings: settings,
                icons: icons
            )
            try TimingLog.measure("save: writeProfile") { try ProfileManager.saveProfile(profile, name: name, allowReservedAutoName: allowReservedAutoName) }
            refreshProfiles()
            TimingLog.summary("SAVE TOTAL", startTime: saveStart)
            statusMessage = "Saved \(icons.count) icons to \"\(name)\""
        } catch {
            handleFinderError(error, action: "Save")
        }
    }

    /// Save with auto-fingerprint name.
    func saveAuto() {
        let fp = DisplayService.fingerprint()
        let names = DisplayService.displayNames()
        let name = ProfileManager.autoProfileName(fingerprint: fp, displayNames: names)
        save(name: name, allowReservedAutoName: true)
    }

    /// Update an existing profile with current icon positions.
    func updateProfile(name: String) {
        do {
            statusMessage = "Updating..."
            let frames = DisplayService.currentFrames()
            let fingerprint = DisplayService.fingerprint()
            let settings = try FinderService.readSettings()
            let icons = try FinderService.readIconPositions()

            let profile = Profile(
                fingerprint: fingerprint,
                displays: frames,
                settings: settings,
                icons: icons
            )
            try ProfileManager.saveProfile(
                profile,
                name: name,
                allowReservedAutoName: name.hasPrefix("Auto-")
            )
            refreshProfiles()
            statusMessage = "Updated \(icons.count) icons in \"\(name)\""
        } catch {
            handleFinderError(error, action: "Update")
        }
    }

    /// Save auto profile only if Finder returns at least 1 icon.
    /// Reads icons once and builds the profile directly, avoiding the double-read
    /// that would happen if we called saveAuto() → save() → readIconPositions() again.
    private func saveAutoIfIconsExist() {
        do {
            let icons = try FinderService.readIconPositions()
            guard !icons.isEmpty else { return }
            let settings = try FinderService.readSettings()
            let frames = DisplayService.currentFrames()
            let fingerprint = DisplayService.fingerprint()
            let names = DisplayService.displayNames()
            let name = ProfileManager.autoProfileName(fingerprint: fingerprint, displayNames: names)
            let profile = Profile(
                fingerprint: fingerprint,
                displays: frames,
                settings: settings,
                icons: icons
            )
            try ProfileManager.saveProfile(profile, name: name, allowReservedAutoName: true)
            refreshProfiles()
        } catch {
            if FinderService.isPermissionError(error) {
                handleFinderError(error, action: "Auto-save")
            }
            // Finder may not be ready — skip silently
        }
    }

    // MARK: - Restore

    /// Restore a profile by name. Auto-converts coordinates if display setup changed.
    func restore(name: String) {
        do {
            let profile = try ProfileManager.loadProfile(name: name)
            restore(name: name, profile: profile)
        } catch {
            handleFinderError(error, action: "Restore")
        }
    }

    /// Core restore logic. Accepts a pre-loaded profile to avoid redundant disk reads
    /// (e.g. when restoreAuto already loaded the profile via findAutoProfile).
    private func restore(name: String, profile: Profile) {
        isRestoring = true
        let restoreStart = CFAbsoluteTimeGetCurrent()
        do {
            statusMessage = "Restoring..."
            let currentDisplays = TimingLog.measure("restore: currentFrames") { DisplayService.currentFrames() }

            // Determine if coordinate conversion is needed
            var icons = profile.icons
            if profile.displays != currentDisplays.map({ $0 }) && !profile.displays.isEmpty {
                icons = TimingLog.measure("restore: remap") {
                    CoordinateConverter.remap(
                        icons: icons,
                        from: profile.displays,
                        to: currentDisplays
                    )
                }
            }

            // 1. Restore settings + disable auto-arrange in one call
            try TimingLog.measure("restore: prepareForRestore") { try FinderService.prepareForRestore(profile.settings) }

            // 3. Batch set all positions
            try TimingLog.measure("restore: batchSetPositions") { try FinderService.batchSetPositions(icons) }

            TimingLog.summary("RESTORE (before verify)", startTime: restoreStart)

            // 2. Adaptive verify: check at 0.5s, 1.5s, 3.0s — stop early if no drift
            let expected = icons
            verifyTask?.cancel()
            verifyTask = Task { @MainActor [weak self] in
                defer { self?.isRestoring = false }
                let verifyDelays: [Double] = [0.5, 1.0, 1.5]  // cumulative: 0.5s, 1.5s, 3.0s
                var totalCorrected = 0
                for (attempt, delay) in verifyDelays.enumerated() {
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    do {
                        let corrected = try TimingLog.measure("restore: verify pass \(attempt + 1)") {
                            try FinderService.verifyAndReapply(expected: expected)
                        }
                        totalCorrected += corrected
                        if corrected == 0 {
                            TimingLog.summary("RESTORE TOTAL (verify pass \(attempt + 1), no drift)", startTime: restoreStart)
                            self?.statusMessage = totalCorrected > 0
                                ? "Restored \(expected.count) icons, corrected \(totalCorrected)"
                                : "Restored \(expected.count) icons"
                            return
                        }
                    } catch {
                        self?.handleFinderError(error, action: "Restore")
                        return
                    }
                }
                // All passes completed with some corrections
                TimingLog.summary("RESTORE TOTAL (all verify passes)", startTime: restoreStart)
                self?.statusMessage = "Restored \(expected.count) icons, corrected \(totalCorrected)"
            }
        } catch {
            isRestoring = false
            handleFinderError(error, action: "Restore")
        }
    }

    /// Restore the auto-profile matching the current display fingerprint.
    /// Skips if a restore is already in progress to prevent overlapping restores.
    func restoreAuto() {
        guard !isRestoring else { return }
        do {
            let fp = DisplayService.fingerprint()
            guard let (name, profile) = try ProfileManager.findAutoProfile(forFingerprint: fp) else {
                statusMessage = "No profile for current display config"
                return
            }
            restore(name: name, profile: profile)
        } catch {
            handleFinderError(error, action: "Auto-restore")
        }
    }

    // MARK: - Profile Management

    func refreshProfiles() {
        profiles = (try? ProfileManager.listProfiles()) ?? []
    }

    func deleteProfile(name: String) {
        do {
            try ProfileManager.deleteProfile(name: name)
            refreshProfiles()
            statusMessage = "Deleted \"\(name)\""
        } catch {
            statusMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    func renameProfile(from oldName: String, to newName: String) {
        do {
            try ProfileManager.renameProfile(from: oldName, to: newName)
            refreshProfiles()
            statusMessage = "Renamed \"\(oldName)\" → \"\(newName)\""
        } catch {
            statusMessage = "Rename failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Display Change Observer

    private func startDisplayObserver() {
        displayObserver = DisplayService.observeDisplayChanges(delay: 0) { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleDisplayChange()
            }
        }
    }

    /// Debounce display-change handling: cancel any pending task, then wait 5s.
    /// This collapses rapid-fire notifications (common during dock/undock) into one.
    private func scheduleDisplayChange() {
        displayChangeTask?.cancel()
        displayChangeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.handleDisplayChange()
        }
    }

    private func handleDisplayChange() {
        let newFingerprint = DisplayService.fingerprint()
        guard let plan = automationCoordinator.planDisplayChange(
            previousFingerprint: lastFingerprint,
            newFingerprint: newFingerprint,
            permissionGranted: permissionGranted,
            autoRestoreEnabled: autoRestoreEnabled
        ) else {
            return
        }

        if let nextFingerprint = plan.nextFingerprint {
            lastFingerprint = nextFingerprint
        }

        applyAutomationActions(plan.actions)
    }

    // MARK: - Auto-Save Timer

    private func startAutoSaveTimer() {
        stopAutoSaveTimer()
        let interval = TimeInterval(autoSaveIntervalMinutes * 60)
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.saveAutoIfIconsExist()
            }
        }
    }

    private func stopAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }

    /// Reveal the app in Finder so the user can drag it to /Applications.
    func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Bundle.main.bundlePath)])
    }

    /// Open the bundled license text for the installed app.
    func openBundledLicense() {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("LICENSE.txt"),
              FileManager.default.fileExists(atPath: url.path) else {
            statusMessage = "Bundled license not found"
            return
        }

        if !NSWorkspace.shared.open(url) {
            statusMessage = "Unable to open bundled license"
        }
    }

    /// Start an email draft for commercial licensing inquiries.
    func requestCommercialLicense() {
        guard let url = URL(
            string: "mailto:gmlupatelli@gmail.com?subject=Desktop%20Icon%20Position%20Commercial%20License"
        ) else {
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
        let settingsWindowSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: settingsWindowSize)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Desktop Icon Position Settings"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.setContentSize(settingsWindowSize)
        window.contentMinSize = settingsWindowSize
        window.tabbingMode = .disallowed

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Permission Helpers

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
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    private func handleFinderError(_ error: Error, action: String) {
        if FinderService.isPermissionError(error) {
            permissionGranted = false
            statusMessage = "Permission required \u{2014} open System Settings to grant access"
            stopAutoSaveTimer()
        } else {
            statusMessage = "\(action) failed: \(error.localizedDescription)"
        }
    }

    private func resumeAfterPermissionGranted(runLaunchActions: Bool) {
        let actions = automationCoordinator.planResumeAfterPermissionGranted(
            runLaunchActions: runLaunchActions,
            autoRestoreOnLaunch: autoRestoreOnLaunch,
            autoSaveOnTimer: autoSaveOnTimer
        )
        applyAutomationActions(actions)
    }

    private func applyAutomationActions(_ actions: [AutomationCoordinator.Action]) {
        for action in actions {
            switch action {
            case .setStatusMessage(let message):
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
