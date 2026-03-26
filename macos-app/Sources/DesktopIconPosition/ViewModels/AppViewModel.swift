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

    var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
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
    var showAutoProfiles: Bool = UserDefaults.standard.bool(forKey: "showAutoProfiles") {
        didSet { UserDefaults.standard.set(showAutoProfiles, forKey: "showAutoProfiles") }
    }
    var autoSaveOnLaunch: Bool = UserDefaults.standard.bool(forKey: "autoSaveOnLaunch") {
        didSet { UserDefaults.standard.set(autoSaveOnLaunch, forKey: "autoSaveOnLaunch") }
    }
    var autoSaveOnDisplayChange: Bool = UserDefaults.standard.bool(forKey: "autoSaveOnDisplayChange") {
        didSet { UserDefaults.standard.set(autoSaveOnDisplayChange, forKey: "autoSaveOnDisplayChange") }
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
        return profiles.filter { !$0.name.hasPrefix("auto_") }
    }

    // MARK: - Private State

    private var displayObserver: NSObjectProtocol?
    private var lastFingerprint: String = ""
    private var autoSaveTimer: Timer?

    // MARK: - Lifecycle

    func start() {
        // Enable launch at login by default on first run
        if !UserDefaults.standard.bool(forKey: "hasSetupLaunchAtLogin") {
            UserDefaults.standard.set(true, forKey: "hasSetupLaunchAtLogin")
            launchAtLogin = true
        }

        refreshProfiles()
        lastFingerprint = DisplayService.fingerprint()
        startDisplayObserver()

        if autoSaveOnLaunch {
            saveAutoIfIconsExist()
        }
        if autoSaveOnTimer {
            startAutoSaveTimer()
        }
    }

    func stop() {
        stopAutoSaveTimer()
        if let observer = displayObserver {
            NotificationCenter.default.removeObserver(observer)
            displayObserver = nil
        }
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
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    /// Save with auto-fingerprint name.
    func saveAuto() {
        let fp = DisplayService.fingerprint()
        let name = ProfileManager.autoProfileName(fingerprint: fp)
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
            statusMessage = "Update failed: \(error.localizedDescription)"
        }
    }

    /// Save auto profile only if Finder returns at least 1 icon.
    private func saveAutoIfIconsExist() {
        do {
            let icons = try FinderService.readIconPositions()
            guard !icons.isEmpty else { return }
            saveAuto()
        } catch {
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
                let corrected = try? FinderService.verifyAndReapply(expected: expected)
                if let corrected, corrected > 0 {
                    statusMessage = "Restored \(expected.count) icons, corrected \(corrected)"
                } else {
                    statusMessage = "Restored \(expected.count) icons"
                }
            }
        } catch {
            statusMessage = "Restore failed: \(error.localizedDescription)"
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
            statusMessage = "Auto-restore failed: \(error.localizedDescription)"
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
        guard newFingerprint != lastFingerprint else { return }

        // Save outgoing display config before switching
        if autoSaveOnDisplayChange {
            saveAutoIfIconsExist()
        }

        lastFingerprint = newFingerprint

        guard autoRestoreEnabled else {
            statusMessage = "Display changed (auto-restore off)"
            return
        }

        statusMessage = "Display changed — restoring..."
        restoreAuto()
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
}
