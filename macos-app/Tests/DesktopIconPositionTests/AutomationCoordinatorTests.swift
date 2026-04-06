@testable import DesktopIconPosition
import Testing

struct AutomationCoordinatorTests {
    private let coordinator = AutomationCoordinator()

    @Test("unchanged fingerprint produces no display-change plan")
    func unchangedFingerprint() {
        let plan = coordinator.planDisplayChange(
            previousFingerprint: "same",
            newFingerprint: "same",
            permissionGranted: true,
            autoRestoreEnabled: true
        )

        #expect(plan == nil)
    }

    @Test("display change with missing permission blocks restore")
    func displayChangeWithoutPermission() {
        let plan = coordinator.planDisplayChange(
            previousFingerprint: "old",
            newFingerprint: "new",
            permissionGranted: false,
            autoRestoreEnabled: true
        )

        #expect(plan == .init(
            nextFingerprint: nil,
            actions: [.setStatusMessage("Permission required — open System Settings to grant access")]
        ))
    }

    @Test("display change with auto-restore disabled updates fingerprint only")
    func displayChangeWithoutAutoRestore() {
        let plan = coordinator.planDisplayChange(
            previousFingerprint: "old",
            newFingerprint: "new",
            permissionGranted: true,
            autoRestoreEnabled: false
        )

        #expect(plan == .init(
            nextFingerprint: "new",
            actions: [.setStatusMessage("Display changed (auto-restore off)")]
        ))
    }

    @Test("display change with auto-restore enabled schedules restore")
    func displayChangeWithAutoRestore() {
        let plan = coordinator.planDisplayChange(
            previousFingerprint: "old",
            newFingerprint: "new",
            permissionGranted: true,
            autoRestoreEnabled: true
        )

        #expect(plan == .init(
            nextFingerprint: "new",
            actions: [
                .setStatusMessage("Display changed — restoring..."),
                .restoreAuto,
            ]
        ))
    }

    @Test("resume after permission can restore and start timer")
    func resumeAfterPermissionGrantedWithRestoreAndTimer() {
        let actions = coordinator.planResumeAfterPermissionGranted(
            runLaunchActions: true,
            autoRestoreOnLaunch: true,
            autoSaveOnTimer: true
        )

        #expect(actions == [.restoreAuto, .startAutoSaveTimer])
    }

    @Test("resume after permission without launch actions only manages timer")
    func resumeAfterPermissionGrantedWithoutLaunchActions() {
        let actions = coordinator.planResumeAfterPermissionGranted(
            runLaunchActions: false,
            autoRestoreOnLaunch: true,
            autoSaveOnTimer: false
        )

        #expect(actions == [.stopAutoSaveTimer])
    }

    @Test("permission denial shows recovery message and stops timer")
    func permissionRecheckDenied() {
        let actions = coordinator.planPermissionRecheck(
            wasGranted: true,
            isGranted: false,
            autoRestoreOnLaunch: true,
            autoSaveOnTimer: true
        )

        #expect(actions == [
            .setStatusMessage("Permission required — open System Settings to grant access"),
            .stopAutoSaveTimer,
        ])
    }

    @Test("permission recovery without launch restore shows granted status")
    func permissionRecheckGrantedWithoutLaunchRestore() {
        let actions = coordinator.planPermissionRecheck(
            wasGranted: false,
            isGranted: true,
            autoRestoreOnLaunch: false,
            autoSaveOnTimer: true
        )

        #expect(actions == [
            .setStatusMessage("Permission granted"),
            .startAutoSaveTimer,
        ])
    }

    @Test("permission recovery with launch restore suppresses granted status")
    func permissionRecheckGrantedWithLaunchRestore() {
        let actions = coordinator.planPermissionRecheck(
            wasGranted: false,
            isGranted: true,
            autoRestoreOnLaunch: true,
            autoSaveOnTimer: false
        )

        #expect(actions == [
            .restoreAuto,
            .stopAutoSaveTimer,
        ])
    }
}
