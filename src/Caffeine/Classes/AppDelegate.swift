//
//  AppDelegate.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 11.11.25.
//

import AppIntents
import Cocoa
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    /// Make this lazy so `self` can be used safely
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )
    private var statusItem: NSStatusItem?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_: Notification) {
        // Create the menu bar controller
        self.menuBarController = MenuBarController(updaterController: self.updaterController)

        // Hide the dock icon - this is a menu bar only app
        NSApp.setActivationPolicy(.accessory)

        if let viewModel = CaffeineViewModel.shared {
            AppDependencyManager.shared.add(dependency: viewModel)
        }
    }

    func applicationWillTerminate(_: Notification) {
        // Restore pmset synchronously before the process exits so it can't be skipped.
        SleepPreventionManager.shared.cleanupSynchronously()
        self.menuBarController?.cleanup()
    }

    // MARK: SPUStandardUserDriverDelegate

    // MARK: - --

    func supportsGentleScheduledUpdateReminders() -> Bool {
        true
    }
}
