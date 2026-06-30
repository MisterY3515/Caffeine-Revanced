//
//  SleepPreventionManager.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 11.11.25.
//

import AppKit
import DZFoundation
import Foundation
import IOKit.pwr_mgt

/// Manages the core functionality of preventing system sleep
final class SleepPreventionManager {
    static let shared = SleepPreventionManager()

    var preventLidCloseSleep = false

    private var sleepAssertionID: IOPMAssertionID?
    private var assertionTimer: Timer?
    private var isUserSessionActive = true
    private var sleepDisabledByUs = false

    private init() {
        self.setupWorkspaceNotifications()
    }

    deinit {
        self.releaseDisplaySleepAssertion()
        self.assertionTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public Methods

    func preventSleep() {
        self.assertionTimer?.invalidate()
        self.assertionTimer = Timer.scheduledTimer(
            withTimeInterval: 10.0,
            repeats: true
        ) { [weak self] _ in
            self?.refreshDisplaySleepAssertion()
        }
        self.assertionTimer?.fire()

        DZLog("preventLidCloseSleep=\(self.preventLidCloseSleep)")
        if self.preventLidCloseSleep {
            self.setSystemSleepDisabled(true)
        } else {
            self.setSystemSleepDisabled(false)
        }
    }

    func allowSleep() {
        self.assertionTimer?.invalidate()
        self.assertionTimer = nil
        self.releaseDisplaySleepAssertion()
        self.setSystemSleepDisabled(false)
    }

    /// Synchronous version for use during app termination — blocks until pmset completes.
    func cleanupSynchronously() {
        self.assertionTimer?.invalidate()
        self.assertionTimer = nil
        self.releaseDisplaySleepAssertion()
        self.setSystemSleepDisabled(false, synchronous: true)
    }

    // MARK: - Private Methods

    private func refreshDisplaySleepAssertion() {
        guard self.isUserSessionActive else { return }

        if let assertionID = self.sleepAssertionID {
            IOPMAssertionRelease(assertionID)
        }
        var assertionID: IOPMAssertionID = 0
        let reason = String(localized: "Caffeine Revanced prevents sleep") as CFString
        let result = IOPMAssertionCreateWithDescription(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            reason,
            nil as CFString?,
            nil as CFString?,
            nil as CFString?,
            20,
            nil as CFString?,
            &assertionID
        )
        if result == kIOReturnSuccess {
            self.sleepAssertionID = assertionID
        }
    }

    /// Enables or disables clamshell sleep via `pmset -a disablesleep`.
    /// Requires administrator privileges — shows a system password dialog.
    /// - Parameter synchronous: When true, blocks the calling thread until pmset exits.
    ///   Use this only during app termination to ensure cleanup before the process dies.
    private func setSystemSleepDisabled(_ disabled: Bool, synchronous: Bool = false) {
        guard self.sleepDisabledByUs != disabled else { return }

        let value = disabled ? "1" : "0"
        let script = "do shell script \"pmset -a disablesleep \(value)\" with administrator privileges"
        DZLog("setSystemSleepDisabled \(value) (sync=\(synchronous))")

        let work = { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    self?.sleepDisabledByUs = disabled
                    DZLog("pmset disablesleep \(value) OK")
                } else {
                    DZLog("pmset disablesleep \(value) cancelled or failed (status=\(process.terminationStatus))")
                }
            } catch {
                DZLog("pmset disablesleep error: \(error)")
            }
        }

        if synchronous {
            DispatchQueue.global(qos: .userInitiated).sync(execute: work)
        } else {
            DispatchQueue.global(qos: .userInitiated).async(execute: work)
        }
    }

    private func releaseDisplaySleepAssertion() {
        if let assertionID = self.sleepAssertionID {
            IOPMAssertionRelease(assertionID)
            self.sleepAssertionID = nil
        }
    }

    private func setupWorkspaceNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        notificationCenter.addObserver(
            self,
            selector: #selector(self.sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(self.sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    @objc
    private func sessionDidResignActive() {
        self.isUserSessionActive = false
    }

    @objc
    private func sessionDidBecomeActive() {
        self.isUserSessionActive = true
    }
}
