struct AutomationCoordinator {
    enum Action: Equatable {
        case setStatusMessage(String)
        case restoreAuto
        case startAutoSaveTimer
        case stopAutoSaveTimer
    }

    struct DisplayChangePlan: Equatable {
        let nextFingerprint: String?
        let actions: [Action]
    }

    func planDisplayChange(
        previousFingerprint: String,
        newFingerprint: String,
        permissionGranted: Bool,
        autoRestoreEnabled: Bool
    ) -> DisplayChangePlan? {
        guard newFingerprint != previousFingerprint else { return nil }

        guard permissionGranted else {
            return DisplayChangePlan(
                nextFingerprint: nil,
                actions: [.setStatusMessage("Permission required — open System Settings to grant access")]
            )
        }

        guard autoRestoreEnabled else {
            return DisplayChangePlan(
                nextFingerprint: newFingerprint,
                actions: [.setStatusMessage("Display changed (auto-restore off)")]
            )
        }

        return DisplayChangePlan(
            nextFingerprint: newFingerprint,
            actions: [
                .setStatusMessage("Display changed — restoring..."),
                .restoreAuto,
            ]
        )
    }

    func planResumeAfterPermissionGranted(
        runLaunchActions: Bool,
        autoRestoreOnLaunch: Bool,
        autoSaveOnTimer: Bool
    ) -> [Action] {
        var actions: [Action] = []

        if runLaunchActions, autoRestoreOnLaunch {
            actions.append(.restoreAuto)
        }

        actions.append(autoSaveOnTimer ? .startAutoSaveTimer : .stopAutoSaveTimer)
        return actions
    }

    func planPermissionRecheck(
        wasGranted: Bool,
        isGranted: Bool,
        autoRestoreOnLaunch: Bool,
        autoSaveOnTimer: Bool
    ) -> [Action] {
        guard isGranted else {
            return [
                .setStatusMessage("Permission required — open System Settings to grant access"),
                .stopAutoSaveTimer,
            ]
        }

        var actions = planResumeAfterPermissionGranted(
            runLaunchActions: !wasGranted,
            autoRestoreOnLaunch: autoRestoreOnLaunch,
            autoSaveOnTimer: autoSaveOnTimer
        )

        if wasGranted || !autoRestoreOnLaunch {
            actions.insert(.setStatusMessage("Permission granted"), at: 0)
        }

        return actions
    }
}
