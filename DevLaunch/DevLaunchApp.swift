import SwiftUI

@main
struct DevLaunchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // LSUIElement=true のメニューバーアプリでは Settings シーンが機能しないため、
        // 設定ウィンドウは AppDelegate.openSettings() で NSWindowController 経由で表示する。
        Settings {
            EmptyView()
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var viewModel: ProjectListViewModel!
    private var shortcutManager: GlobalShortcutManager!
    private var settingsWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            AppStorageKey.editorCommand: AppDefaults.editorCommand,
            AppStorageKey.aiCliCommand: AppDefaults.aiCliCommand,
            AppStorageKey.usesIntegratedTerminal: AppDefaults.usesIntegratedTerminal,
            AppStorageKey.sortOrder: AppDefaults.sortOrder,
            AppStorageKey.launchAtLogin: AppDefaults.launchAtLogin,
            AppStorageKey.globalShortcutKeyCode: AppDefaults.globalShortcutKeyCode,
            AppStorageKey.globalShortcutModifiers: AppDefaults.globalShortcutModifiers,
        ])

        let scanner = ProjectScanner()
        let launcher = ProjectLauncher()
        viewModel = ProjectListViewModel(scanner: scanner, launcher: launcher)

        setupStatusItem()
        setupPopover()
        setupShortcutManager()
        setupNotificationObservers()

        if viewModel.hasScanFolder {
            Task { await viewModel.performScan() }
        } else {
            showInitialPopover()
        }
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
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: ProjectListView(viewModel: viewModel)
                .frame(width: 300)
        )
    }

    private func setupShortcutManager() {
        Task { @MainActor in
            shortcutManager = GlobalShortcutManager()
            shortcutManager.onTrigger = { [weak self] in
                guard let self, let button = self.statusItem.button else { return }
                self.togglePopover(button)
            }
            startShortcutFromDefaults()
        }
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .shortcutDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.startShortcutFromDefaults()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.startShortcutFromDefaults()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .scanFolderDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let url = note.object as? URL else { return }
            Task { [weak self] in
                await self?.viewModel.scanner.scan(folderURL: url)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .popoverShouldClose,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.popover.performClose(nil)
        }

        NotificationCenter.default.addObserver(
            forName: .openSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openSettings()
        }
    }

    @MainActor
    private func startShortcutFromDefaults() {
        let keyCode = UserDefaults.standard.integer(forKey: AppStorageKey.globalShortcutKeyCode)
        let modifiers = UserDefaults.standard.integer(forKey: AppStorageKey.globalShortcutModifiers)
        let shortcut = GlobalShortcut(keyCode: keyCode, modifiers: UInt64(max(0, modifiers)))
        shortcutManager.start(shortcut: shortcut)
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

    private func showInitialPopover() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self,
                  !self.viewModel.hasScanFolder,
                  let button = self.statusItem.button,
                  !self.popover.isShown else { return }

            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            self.popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func openSettings() {
        popover.performClose(nil)

        if let wc = settingsWindowController, let window = wc.window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
        } else {
            let hostingController = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hostingController)
            window.title = ""
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.setContentSize(NSSize(width: 420, height: 340))
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.level = .floating
            settingsWindowController = NSWindowController(window: window)
            settingsWindowController?.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - NSPopoverDelegate

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        viewModel.searchText = ""
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // 設定ウィンドウが閉じたらメニューバー専用アプリに戻す
        // 少し遅延を入れないと Dock アイコンが残ることがある
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
