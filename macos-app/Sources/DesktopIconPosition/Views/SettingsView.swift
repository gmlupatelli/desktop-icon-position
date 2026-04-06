import AppKit
import SwiftUI

/// Settings window content for Desktop Icon Position.
struct SettingsView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        TabView {
            GeneralSettingsView(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gearshape") }

            AboutSettingsView(viewModel: viewModel)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480)
    }
}

// MARK: - General Tab

private struct GeneralSettingsView: View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsSection(
        title: String,
        footer: String,
        @ViewBuilder content: () -> some View
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

// MARK: - About Tab

private struct AboutSettingsView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 8) {
                    Text(bundleString("CFBundleName") ?? "Desktop Icon Position")
                        .font(.title)
                        .fontWeight(.semibold)

                    Text("Version \(bundleString("CFBundleShortVersionString") ?? "1.0")"
                        + " Build \(bundleString("CFBundleVersion") ?? "1")")
                        .foregroundStyle(.secondary)

                    Text(bundleString("NSHumanReadableCopyright") ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
            .padding(.top, 24)

            Divider()
                .padding(.vertical, 16)

            VStack(alignment: .leading, spacing: 10) {
                Text("License")
                    .font(.headline)

                Text("Desktop Icon Position is source-available for private personal use only. "
                    + "Redistribution and commercial use require separate written permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button("Open Bundled License") {
                        viewModel.openBundledLicense()
                    }
                    .controlSize(.small)

                    Button("Request Commercial License") {
                        viewModel.requestCommercialLicense()
                    }
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bundleString(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
