//
//  MenuBarController.swift
//  Caffeine
//

import Cocoa
import Combine
import Sparkle
import SwiftUI

@MainActor
class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var viewModel: CaffeineViewModel
    private var preferencesWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private let updaterController: SPUStandardUpdaterController

    init(updaterController: SPUStandardUpdaterController) {
        self.updaterController = updaterController
        self.viewModel = CaffeineViewModel()
        super.init()
        self.setupMenuBar()
        self.setupObservers()
        self.updateIcon()
    }

    func cleanup() {
        self.viewModel.deactivate()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    private func setupMenuBar() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.action = #selector(self.statusItemClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupObservers() {
        self.viewModel.$isActive
            .sink { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async { self.updateIcon() }
            }
            .store(in: &self.cancellables)

        self.viewModel.$timeRemaining
            .sink { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async { self.updateMenuBarTitle() }
            }
            .store(in: &self.cancellables)

        self.viewModel.$showPreferences
            .sink { [weak self] show in
                if show { self?.showPreferencesWindow() }
            }
            .store(in: &self.cancellables)
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let imageName = self.viewModel.isActive ? "active" : "inactive"
        if let image = NSImage(named: NSImage.Name(imageName)) {
            button.image = image
        }
        self.updateMenuBarTitle()
    }

    private func updateMenuBarTitle() {
        guard let button = statusItem?.button else { return }
        guard UserDefaults.standard.bool(forKey: PreferenceKeys.showTimeInMenuBar) else {
            button.title = ""
            return
        }
        if let short = self.viewModel.formattedTimeRemainingShort() {
            button.title = " \(short)"
        } else if self.viewModel.isActive {
            button.title = " ∞"
        } else {
            button.title = ""
        }
    }

    @objc
    private func statusItemClicked(_: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || (event.type == .leftMouseUp && event.modifierFlags.contains(.control)) {
            self.showContextMenu()
        } else {
            self.viewModel.toggleActive()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        if self.viewModel.isActive, let timeString = viewModel.formattedTimeRemaining() {
            let infoItem = NSMenuItem(title: timeString, action: nil, keyEquivalent: "")
            infoItem.isEnabled = false
            menu.addItem(infoItem)
            menu.addItem(NSMenuItem.separator())
        }

        let activateForItem = NSMenuItem(
            title: String(localized: "Activate for"),
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu()

        var durations: [(String, Int)] = [
            (String(localized: "Indefinitely"), 0),
            (String(localized: "5 minutes"), 5),
            (String(localized: "10 minutes"), 10),
            (String(localized: "15 minutes"), 15),
            (String(localized: "30 minutes"), 30),
            (String(localized: "1 hour"), 60),
            (String(localized: "2 hours"), 120),
            (String(localized: "5 hours"), 300),
        ]

        #if DEBUG
        durations.insert((String(localized: "1 minute"), 1), at: 1)
        #endif

        for (title, minutes) in durations {
            let item = NSMenuItem(
                title: title,
                action: #selector(activateWithDuration(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = minutes
            submenu.addItem(item)
        }

        let customDurations = self.viewModel.customDurations().sorted()
        if !customDurations.isEmpty {
            submenu.addItem(NSMenuItem.separator())
            for minutes in customDurations {
                let item = NSMenuItem(
                    title: String.localizedStringWithFormat(String(localized: "%d minutes"), minutes),
                    action: #selector(self.activateWithDuration(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = minutes
                submenu.addItem(item)
            }
        }

        activateForItem.submenu = submenu
        menu.addItem(activateForItem)
        menu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(
            title: String(localized: "Preferences..."),
            action: #selector(showPreferences(_:)),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        let aboutItem = NSMenuItem(
            title: String(localized: "About Caffeine Revanced"),
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let updatesItem = NSMenuItem(
            title: String(localized: "Check for Updates..."),
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updatesItem.target = self
        menu.addItem(updatesItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: String(localized: "Quit"),
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem?.menu = menu
        self.statusItem?.button?.performClick(nil)
        self.statusItem?.menu = nil
    }

    @objc
    private func activateWithDuration(_ sender: NSMenuItem) {
        let minutes = sender.tag
        let seconds = minutes > 0 ? TimeInterval(minutes * 60) : 0
        self.viewModel.activate(withTimeout: seconds)
    }

    @objc
    private func showPreferences(_: Any?) {
        self.showPreferencesWindow()
    }

    @objc
    private func checkForUpdates(_ sender: Any?) {
        self.updaterController.checkForUpdates(sender)
    }

    private func showPreferencesWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if self.preferencesWindow == nil {
            let contentView = PreferencesView(viewModel: viewModel)
            let hostingController = NSHostingController(rootView: contentView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = String(localized: "Welcome to Caffeine Revanced")
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 680, height: 600))
            window.center()

            self.preferencesWindow = window
        }

        self.preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    @objc
    private func showAbout(_: Any?) {
        NSApp.activate(ignoringOtherApps: true)

        let credits = String(
            localized: "© 2006 Tomas Franzén\n© 2018 Michael Jones\n© 2022 Dominic Rodemer\n\nSource code:\nhttps://github.caffeine-app.net"
        )

        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: credits),
        ])
    }

    @objc
    private func quit(_: Any?) {
        NSApp.terminate(nil)
    }
}
