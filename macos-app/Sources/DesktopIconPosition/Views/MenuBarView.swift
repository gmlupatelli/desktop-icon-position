import SwiftUI
import AppKit

// MARK: - Modal Panel Helper (handles keyboard input in LSUIElement apps)

/// Button action handler for the save dialog panel.
@MainActor
private final class SaveDialogHandler: NSObject {
    var didSave = false

    @objc func save(_ sender: Any?) {
        didSave = true
        NSApp.stopModal()
    }

    @objc func cancel(_ sender: Any?) {
        didSave = false
        NSApp.stopModal()
    }
}

/// Menu bar dropdown content for the Desktop Icon Position app.
struct MenuBarView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        Text(viewModel.statusMessage)
            .foregroundStyle(.secondary)
            .onAppear { viewModel.refreshProfiles() }

        if !viewModel.permissionGranted {
            Divider()
            Button("Open System Settings") {
                viewModel.openAutomationSettings()
            }
            Button("Re-check Permission") {
                viewModel.recheckPermission()
            }
        }

        Divider()

        Button("Save Auto") {
            viewModel.saveAuto()
        }
        .keyboardShortcut("s")

        Button("Save As...") {
            promptAndSave()
        }

        if !viewModel.visibleProfiles.isEmpty {
            Menu("Update Profile") {
                ForEach(viewModel.visibleProfiles) { profile in
                    Button(profile.name) {
                        viewModel.updateProfile(name: profile.name)
                    }
                }
            }
        }

        Divider()

        if viewModel.visibleProfiles.isEmpty {
            Text("No saved profiles")
                .foregroundStyle(.secondary)
        } else {
            Menu("Restore") {
                Button("Auto (match display config)") {
                    viewModel.restoreAuto()
                }
                Divider()
                ForEach(viewModel.visibleProfiles) { profile in
                    let displaySuffix = profile.displayCount == 1 ? "" : "s"
                    let label = "\(profile.name) (\(profile.iconCount) icons, "
                        + "\(profile.displayCount) display\(displaySuffix))"
                    Button(label) {
                        viewModel.restore(name: profile.name)
                    }
                }
            }
        }

        if !viewModel.visibleProfiles.isEmpty {
            Menu("Manage Profiles") {
                Menu("Rename") {
                    ForEach(viewModel.visibleProfiles.filter { !$0.name.hasPrefix("Auto-") }) { profile in
                        Button(profile.name) {
                            promptAndRename(oldName: profile.name)
                        }
                    }
                }
                Menu("Delete") {
                    ForEach(viewModel.visibleProfiles) { profile in
                        Button(profile.name, role: .destructive) {
                            confirmAndDelete(name: profile.name)
                        }
                    }
                }
            }
        }

        Divider()

        Button("Settings...") {
            viewModel.openSettings()
        }

        Divider()

        Button("Quit") {
            viewModel.quit()
        }
        .keyboardShortcut("q")
    }

    // MARK: - Save Dialog

    private func promptAndSave() {
        let handler = SaveDialogHandler()

        // NSPanel accepts key events even in LSUIElement (menu bar only) apps
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 140),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Save Profile"
        panel.level = .floating
        panel.isReleasedWhenClosed = false

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 140))

        let label = NSTextField(labelWithString: "Enter a name for the new profile:")
        label.frame = NSRect(x: 20, y: 100, width: 280, height: 20)
        contentView.addSubview(label)

        let textField = NSTextField(frame: NSRect(x: 20, y: 68, width: 280, height: 24))
        textField.placeholderString = "e.g. docked, home-office"
        contentView.addSubview(textField)

        let saveButton = NSButton(title: "Save", target: handler, action: #selector(SaveDialogHandler.save(_:)))
        saveButton.frame = NSRect(x: 210, y: 16, width: 90, height: 32)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"  // Enter key triggers Save
        contentView.addSubview(saveButton)

        let cancelButton = NSButton(title: "Cancel", target: handler, action: #selector(SaveDialogHandler.cancel(_:)))
        cancelButton.frame = NSRect(x: 110, y: 16, width: 90, height: 32)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"  // Escape key triggers Cancel
        contentView.addSubview(cancelButton)

        panel.contentView = contentView
        panel.center()

        // Temporarily become a regular app to receive keyboard events.
        // LSUIElement/.accessory apps don't get key events even with activate().
        NSApp.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textField)

        NSApp.runModal(for: panel)

        let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        panel.orderOut(nil)

        // Switch back to accessory (menu bar only, no dock icon)
        NSApp.setActivationPolicy(.accessory)

        if handler.didSave && !name.isEmpty {
            viewModel.save(name: name)
        }
    }

    // MARK: - Rename Dialog

    private func promptAndRename(oldName: String) {
        let handler = SaveDialogHandler()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 140),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Rename Profile"
        panel.level = .floating
        panel.isReleasedWhenClosed = false

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 140))

        let label = NSTextField(labelWithString: "Rename \"\(oldName)\" to:")
        label.frame = NSRect(x: 20, y: 100, width: 280, height: 20)
        contentView.addSubview(label)

        let textField = NSTextField(frame: NSRect(x: 20, y: 68, width: 280, height: 24))
        textField.stringValue = oldName
        contentView.addSubview(textField)

        let renameButton = NSButton(title: "Rename", target: handler, action: #selector(SaveDialogHandler.save(_:)))
        renameButton.frame = NSRect(x: 210, y: 16, width: 90, height: 32)
        renameButton.bezelStyle = .rounded
        renameButton.keyEquivalent = "\r"
        contentView.addSubview(renameButton)

        let cancelButton = NSButton(title: "Cancel", target: handler, action: #selector(SaveDialogHandler.cancel(_:)))
        cancelButton.frame = NSRect(x: 110, y: 16, width: 90, height: 32)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        contentView.addSubview(cancelButton)

        panel.contentView = contentView
        panel.center()

        NSApp.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textField)

        NSApp.runModal(for: panel)

        let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        panel.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)

        if handler.didSave && !newName.isEmpty && newName != oldName {
            viewModel.renameProfile(from: oldName, to: newName)
        }
    }

    // MARK: - Delete Confirmation

    private func confirmAndDelete(name: String) {
        NSApp.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Delete \"\(name)\"?"
        alert.informativeText = "This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        NSApp.setActivationPolicy(.accessory)

        if response == .alertFirstButtonReturn {
            viewModel.deleteProfile(name: name)
        }
    }
}
