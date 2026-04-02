import SwiftUI

/// Settings window content for Desktop Icon Position.
struct SettingsView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection(
                title: "Startup",
                footer: viewModel.isStableLocation
                    ? "Open Desktop Icon Position automatically when you sign in."
                    : "Move the app to /Applications to enable Launch at Login."
            ) {
                if viewModel.isStableLocation {
                    Toggle("Launch at Login", isOn: $viewModel.launchAtLogin)
                } else {
                    Toggle("Launch at Login", isOn: .constant(false))
                        .disabled(true)

                    Button("Reveal App in Finder") {
                        viewModel.revealAppInFinder()
                    }
                    .controlSize(.small)
                }
            }

            Divider()

            settingsSection(
                title: "Auto-Save",
                footer: "Automatically keep an up-to-date auto profile for the current display setup."
            ) {
                Toggle("Save automatically when quitting", isOn: $viewModel.autoSaveOnQuit)
                Toggle("Save periodically in the background", isOn: $viewModel.autoSaveOnTimer)

                HStack(alignment: .firstTextBaseline) {
                    Text("Save every")
                    Spacer(minLength: 12)
                    Picker("Save every", selection: $viewModel.autoSaveIntervalMinutes) {
                        ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                .disabled(!viewModel.autoSaveOnTimer)
                .opacity(viewModel.autoSaveOnTimer ? 1.0 : 0.55)
            }

            Divider()

            settingsSection(
                title: "Auto-Restore",
                footer: "Reapply saved icon positions when the app starts or your display arrangement changes."
            ) {
                Toggle("Restore after display changes", isOn: $viewModel.autoRestoreEnabled)
                Toggle("Restore when the app launches", isOn: $viewModel.autoRestoreOnLaunch)
            }

            Divider()

            settingsSection(
                title: "Profiles",
                footer: "Auto-generated profiles are matched to the current display configuration."
            ) {
                Toggle("Show auto-generated profiles", isOn: $viewModel.showAutoProfiles)
            }
        }
        .padding(20)
        .frame(width: 420, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        title: String,
        footer: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content()

            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
