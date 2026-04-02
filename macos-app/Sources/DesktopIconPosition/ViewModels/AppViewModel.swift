import AppKit
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
    /// Auto-save interval in minutes. Options: 5, 10, 15, 30.
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
        do {
            statusMessage = "Saving..."
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
            try ProfileManager.saveProfile(profile, name: name)
            refreshProfiles()
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
        save(name: name)
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
            try ProfileManager.saveProfile(profile, name: name)
            refreshProfiles()
            statusMessage = "Updated \(icons.count) icons in \"\(name)\""
        } catch {
            handleFinderError(error, action: "Update")
        }
    }

    /// Save auto profile only if Finder returns at least 1 icon.
    private func saveAutoIfIconsExist() {
        do {
            let icons = try FinderService.readIconPositions()
            guard !icons.isEmpty else { return }
            saveAuto()
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
            statusMessage = "Restoring..."
            let profile = try ProfileManager.loadProfile(name: name)
            let currentDisplays = DisplayService.currentFrames()

            // Determine if coordinate conversion is needed
            var icons = profile.icons
            if profile.displays != currentDisplays.map({ $0 }) && !profile.displays.isEmpty {
                icons = CoordinateConverter.remap(
                    icons: icons,
                    from: profile.displays,
                    to: currentDisplays
                )
            }

            // 1. Restore settings first (prevents Finder layout recalculation)
            try FinderService.restoreSettings(profile.settings)

            // 2. Disable auto-arrange (prevents Snap to Grid drift)
            try FinderService.disableArrangement()

            // 3. Batch set all positions
            try FinderService.batchSetPositions(icons)

            // 4. Verify after delay and re-apply drifted icons
            let expected = icons
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                do {
                    let corrected = try FinderService.verifyAndReapply(expected: expected)
                    if corrected > 0 {
                        statusMessage = "Restored \(expected.count) icons, corrected \(corrected)"
                    } else {
                        statusMessage = "Restored \(expected.count) icons"
                    }
                } catch {
                    handleFinderError(error, action: "Restore")
                }
            }
        } catch {
            handleFinderError(error, action: "Restore")
        }
    }

    /// Restore the auto-profile matching the current display fingerprint.
    func restoreAuto() {
        do {
            let fp = DisplayService.fingerprint()
            guard let (name, _) = try ProfileManager.findProfile(forFingerprint: fp) else {
                statusMessage = "No profile for current display config"
                return
            }
            restore(name: name)
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
        displayObserver = DisplayService.observeDisplayChanges(delay: 5.0) { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleDisplayChange()
            }
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
