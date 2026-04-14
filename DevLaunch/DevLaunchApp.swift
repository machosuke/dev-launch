import SwiftUI

@main
struct DevLaunchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsPlaceholderView()
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "terminal.fill",
                accessibilityDescription: "DevLaunch"
            )
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(handleStatusItemClick(_:))
            button.target = self
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 340)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .frame(width: 300)
        )
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: "Settings\u{2026}",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit DevLaunch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - ContentView

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "terminal.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("No projects yet")
                .font(.headline)

            Text("Configure a scan folder in Settings")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - SettingsPlaceholderView

struct SettingsPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gearshape")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("Settings coming soon")
                .font(.headline)
        }
        .frame(width: 400, height: 200)
    }
}
