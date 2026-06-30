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
    private var lidCloseSleepAssertionID: IOPMAssertionID?
    private var assertionTimer: Timer?
    private var isUserSessionActive = true

    private init() {
        self.setupWorkspaceNotifications()
    }

    deinit {
        releaseDisplaySleepAssertion()
        releaseLidCloseAssertion()
        assertionTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public Methods

    /// Prevents the system from sleeping
    func preventSleep() {
        self.assertionTimer?.invalidate()
        self.assertionTimer = Timer.scheduledTimer(
            withTimeInterval: 10.0,
            repeats: true
        ) { [weak self] _ in
            self?.refreshDisplaySleepAssertion()
        }
        self.assertionTimer?.fire()

        // Lid-close assertion is persistent (no timer) — create once, hold until disabled
        DZLog("preventLidCloseSleep=\(self.preventLidCloseSleep)")
        if self.preventLidCloseSleep {
            self.acquireLidCloseAssertion()
        } else {
            self.releaseLidCloseAssertion()
        }
    }

    /// Allows the system to sleep normally
    func allowSleep() {
        self.assertionTimer?.invalidate()
        self.assertionTimer = nil
        self.releaseDisplaySleepAssertion()
        self.releaseLidCloseAssertion()
    }

    // MARK: - Private Methods

    private func refreshDisplaySleepAssertion() {
        guard self.isUserSessionActive else { return }

        if let assertionID = sleepAssertionID {
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
            8,
            nil as CFString?,
            &assertionID
        )
        if result == kIOReturnSuccess {
            self.sleepAssertionID = assertionID
        }
    }

    private func acquireLidCloseAssertion() {
        guard self.lidCloseSleepAssertionID == nil else {
            DZLog("Lid-close assertion already held (id=\(self.lidCloseSleepAssertionID!))")
            return
        }
        var assertionID: IOPMAssertionID = 0
        let reason = "Caffeine Revanced prevents lid close sleep" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        if result == kIOReturnSuccess {
            self.lidCloseSleepAssertionID = assertionID
            DZLog("Lid-close assertion acquired (id=\(assertionID))")
        } else {
            DZLog("Lid-close assertion FAILED — IOReturn=\(String(format: "0x%08X", result))")
        }
    }

    private func releaseDisplaySleepAssertion() {
        if let assertionID = sleepAssertionID {
            IOPMAssertionRelease(assertionID)
            self.sleepAssertionID = nil
        }
    }

    private func releaseLidCloseAssertion() {
        if let assertionID = lidCloseSleepAssertionID {
            IOPMAssertionRelease(assertionID)
            self.lidCloseSleepAssertionID = nil
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
