import SwiftUI

/// Settings window content for Desktop Icon Position.
struct SettingsView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        Form {
            // MARK: - Launch at Login
            Section {
                if viewModel.isStableLocation {
                    Toggle("Launch at Login", isOn: $viewModel.launchAtLogin)
                } else {
                    HStack {
                        Text("Launch at Login")
                        Spacer()
                        Text("Unavailable")
                            .foregroundStyle(.secondary)
                    }
                    Text("Move app to /Applications for reliable startup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Reveal in Finder") {
                        viewModel.revealAppInFinder()
                    }
                    .controlSize(.small)
                }
            }

            // MARK: - Auto-Save
            Section("Auto-Save") {
                Toggle("Save on Quit", isOn: $viewModel.autoSaveOnQuit)
                Toggle("Save Periodically", isOn: $viewModel.autoSaveOnTimer)

                if viewModel.autoSaveOnTimer {
                    Picker("Interval", selection: $viewModel.autoSaveIntervalMinutes) {
                        ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                }
            }

            // MARK: - Auto-Restore
            Section("Auto-Restore") {
                Toggle("Restore on Display Change", isOn: $viewModel.autoRestoreEnabled)
                Toggle("Restore on Launch", isOn: $viewModel.autoRestoreOnLaunch)
            }

            // MARK: - Display
            Section("Display") {
                Toggle("Show Auto Profiles", isOn: $viewModel.showAutoProfiles)
            }
        }
        .formStyle(.grouped)
        .frame(width: 320, height: 360)
    }
}
