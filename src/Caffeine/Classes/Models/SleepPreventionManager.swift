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

/// Manages the core functionality of preventing system sleep.
///
/// Two IOPMAssertions are held while Caffeine is active:
/// - `NoDisplaySleep` — prevents display and idle system sleep.
/// - `NoIdleSleep`    — additional guard against idle system sleep.
///
/// Lid-close prevention uses `pmset -a disablesleep`. On first use an entry is
/// written to `/etc/sudoers.d/caffeine-revanced` (requires one admin password prompt)
/// so that all subsequent `sudo -n pmset` calls run silently — forever, no cache TTL.
/// Disabling the preference removes the sudoers file automatically.
final class SleepPreventionManager {
    static let shared = SleepPreventionManager()

    var preventLidCloseSleep = false {
        didSet { self.syncLidMonitoring() }
    }

    var dimOnLidClose = false {
        didSet { self.syncLidMonitoring() }
    }

    var dimScreenOnLidClose = false {
        didSet { self.syncLidMonitoring() }
    }

    private var savedBacklightState: BacklightController.State?
    private var displayAssertionID: IOPMAssertionID = 0
    private var systemAssertionID: IOPMAssertionID = 0
    private var isCurrentlyPreventing = false
    private var isUserSessionActive = true
    private var sleepDisabledByUs = false

    private init() {
        self.setupWorkspaceNotifications()
    }

    deinit {
        self.releaseAssertions()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public Methods

    /// Acquires IOPMAssertions to prevent display and idle system sleep.
    ///
    /// If lid-close prevention is enabled and `promptIfNeeded` is `true`, the
    /// system password dialog may appear (once; credential cached by macOS) to
    /// obtain admin rights for `pmset disablesleep 1`. Pass `false` for
    /// background / auto-activations where no dialog should appear.
    func preventSleep(promptIfNeeded: Bool = true) {
        self.isCurrentlyPreventing = true
        self.acquireAssertions()

        if self.preventLidCloseSleep {
            self.setDisableSleep(true, promptIfNeeded: promptIfNeeded) { _ in }
        }
    }

    /// Releases IOPMAssertions and resets `pmset disablesleep 0`.
    ///
    /// Pass `promptIfNeeded: true` for manual deactivation so the admin dialog
    /// appears if the credential cache has expired. Pass `false` for automated
    /// paths (battery threshold, timer) where an unexpected dialog would be jarring.
    func allowSleep(promptIfNeeded: Bool = false) {
        self.isCurrentlyPreventing = false
        self.releaseAssertions()
        if self.sleepDisabledByUs {
            self.setDisableSleep(false, promptIfNeeded: promptIfNeeded) { [weak self] ok in
                // macOS does not re-evaluate the closed-lid sleep policy after disablesleep
                // changes dynamically. If the lid is still closed we must request sleep
                // explicitly, otherwise the Mac stays awake indefinitely.
                //
                // Skip if an external display is active (clamshell mode): the user is
                // intentionally running with the lid closed and should not be put to sleep.
                DZLog(
                    "allowSleep: pmset ok=\(ok) preventing=\(String(describing: self?.isCurrentlyPreventing)) "
                        + "lidClosed=\(LidStateMonitor.isClosed()) "
                        + "externalDisplay=\(SleepPreventionManager.hasActiveExternalDisplay())"
                )
                guard
                    ok,
                    self?.isCurrentlyPreventing == false,
                    LidStateMonitor.isClosed(),
                    !SleepPreventionManager.hasActiveExternalDisplay() else { return }
                self?.waitForDisableSleepClearedThenSleep()
            }
        }
    }

    /// `pmset -a disablesleep 0` reporting success does not mean powerd has internally
    /// re-armed lid-close sleep yet — that propagation is itself asynchronous, so a fixed
    /// delay before requesting sleep is unreliable. Poll the real system state via
    /// `pmset -g custom` until it confirms `disablesleep` is actually cleared (or give up
    /// after ~3s and force the sleep request anyway).
    private func waitForDisableSleepClearedThenSleep(attempt: Int = 0) {
        guard
            self.isCurrentlyPreventing == false,
            LidStateMonitor.isClosed(),
            !SleepPreventionManager.hasActiveExternalDisplay() else
        {
            DZLog("waitForDisableSleepClearedThenSleep: aborting, state changed")
            return
        }
        guard attempt < 10 else {
            DZLog("waitForDisableSleepClearedThenSleep: gave up waiting, forcing sleep anyway")
            self.triggerSystemSleep()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let stillDisabled = SleepPreventionManager.isSystemSleepCurrentlyDisabled()
            DispatchQueue.main.async {
                guard let self else { return }
                if stillDisabled {
                    DZLog("waitForDisableSleepClearedThenSleep: still disabled, attempt \(attempt)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.waitForDisableSleepClearedThenSleep(attempt: attempt + 1)
                    }
                } else {
                    DZLog("waitForDisableSleepClearedThenSleep: cleared after \(attempt) checks")
                    self.triggerSystemSleep()
                }
            }
        }
    }

    /// Installs `/etc/sudoers.d/caffeine-revanced` via a one-time admin password prompt
    /// so that subsequent `pmset` and `removeSudoersEntry` calls need no password.
    /// Call this when the preference is enabled while Caffeine is inactive.
    func ensureAdminAccess(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            // pmset 0 is a no-op here (Caffeine is inactive); its only purpose is to
            // trigger the one-time sudoers installation via the slow path.
            let ok = self.pmset(value: "0", promptIfNeeded: true)
            DispatchQueue.main.async { completion(ok) }
        }
    }

    /// Removes `/etc/sudoers.d/caffeine-revanced` using the `sudo -n rm` rule that
    /// was installed alongside the pmset rules. Call when the preference is disabled.
    func removeSudoersEntry(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            process.arguments = ["-n", "/bin/rm", "-f", "/etc/sudoers.d/caffeine-revanced"]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do { try process.run() } catch {
                DZLog("removeSudoersEntry: \(error)")
                DispatchQueue.main.async { completion(false) }
                return
            }
            process.waitUntilExit()
            let ok = process.terminationStatus == 0
            DZLog("removeSudoersEntry: status=\(process.terminationStatus)")
            DispatchQueue.main.async { completion(ok) }
        }
    }

    /// Synchronous cleanup for `applicationWillTerminate`. Releases assertions and
    /// resets `pmset disablesleep 0`; may show the administrator password dialog if
    /// the credential cache has expired.
    func cleanupSynchronously() {
        self.isCurrentlyPreventing = false
        self.releaseAssertions()
        guard self.sleepDisabledByUs else { return }
        if self.pmset(value: "0", promptIfNeeded: true) {
            self.sleepDisabledByUs = false
        }
    }

    /// Applies the lid-close prevention state immediately. Call this when the
    /// preference toggles while Caffeine is already active.
    func applyLidCloseChange(
        _ enabled: Bool, promptIfNeeded: Bool = true, completion: @escaping (Bool) -> Void
    ) {
        self.setDisableSleep(enabled, promptIfNeeded: promptIfNeeded, completion: completion)
    }

    /// Reads `pmset -g custom` to check whether `disablesleep 1` is currently set.
    static func isSystemSleepCurrentlyDisabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "custom"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let output =
            String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.contains("disablesleep\t1") || output.contains("disablesleep 1")
    }

    // MARK: - Private

    private func acquireAssertions() {
        guard self.isUserSessionActive else { return }
        let reason = "Caffeine Revanced prevents sleep" as CFString
        if self.displayAssertionID == 0 {
            IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &self.displayAssertionID
            )
            DZLog("acquired NoDisplaySleep assertion \(self.displayAssertionID)")
        }
        if self.systemAssertionID == 0 {
            IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoIdleSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &self.systemAssertionID
            )
            DZLog("acquired NoIdleSleep assertion \(self.systemAssertionID)")
        }
    }

    private func releaseAssertions() {
        if self.displayAssertionID != 0 {
            IOPMAssertionRelease(self.displayAssertionID)
            DZLog("released NoDisplaySleep assertion \(self.displayAssertionID)")
            self.displayAssertionID = 0
        }
        if self.systemAssertionID != 0 {
            IOPMAssertionRelease(self.systemAssertionID)
            DZLog("released NoIdleSleep assertion \(self.systemAssertionID)")
            self.systemAssertionID = 0
        }
    }

    private func setDisableSleep(
        _ enabled: Bool,
        promptIfNeeded: Bool = true,
        completion: @escaping (Bool) -> Void
    ) {
        guard self.sleepDisabledByUs != enabled else {
            completion(true)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let ok = self.pmset(value: enabled ? "1" : "0", promptIfNeeded: promptIfNeeded)
            if ok { self.sleepDisabledByUs = enabled }
            DispatchQueue.main.async { completion(ok) }
        }
    }

    /// Runs `pmset -a disablesleep <value>`. Tries `sudo -n` first (instant, no dialog
    /// once sudoers is installed). Falls back to installing the sudoers entry via
    /// osascript if `promptIfNeeded` is true; silent failure otherwise.
    private func pmset(value: String, promptIfNeeded: Bool) -> Bool {
        if self.runSudo(args: ["/usr/bin/pmset", "-a", "disablesleep", value]) {
            DZLog("pmset disablesleep \(value): sudo ok")
            return true
        }
        guard promptIfNeeded else {
            DZLog("pmset disablesleep \(value): sudo failed, no prompt allowed")
            return false
        }
        return self.installSudoersAndRun(value: value)
    }

    private func runSudo(args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n"] + args
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do { try process.run() } catch {
            DZLog("runSudo \(args): launch failed: \(error)")
            return false
        }
        process.waitUntilExit()
        DZLog("runSudo \(args): status=\(process.terminationStatus)")
        return process.terminationStatus == 0
    }

    /// Writes `/etc/sudoers.d/caffeine-revanced` with three NOPASSWD rules (pmset 0,
    /// pmset 1, rm self) and immediately runs `pmset -a disablesleep <value>` — all in
    /// one privileged shell so the user sees a single password dialog.
    private func installSudoersAndRun(value: String) -> Bool {
        let username = NSUserName()
        guard !username.contains("'"), !username.isEmpty else {
            DZLog("pmset: username unsafe for sudoers")
            return false
        }
        let line0 = "\(username) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0"
        let line1 = "\(username) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1"
        let line2 = "\(username) ALL=(root) NOPASSWD: /bin/rm -f /etc/sudoers.d/caffeine-revanced"
        let shellCmd = "echo '\(line0)' > /etc/sudoers.d/caffeine-revanced"
            + " && echo '\(line1)' >> /etc/sudoers.d/caffeine-revanced"
            + " && echo '\(line2)' >> /etc/sudoers.d/caffeine-revanced"
            + " && chmod 440 /etc/sudoers.d/caffeine-revanced"
            + " && /usr/bin/pmset -a disablesleep \(value)"
        let appleScript = "do shell script \"\(shellCmd)\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            DZLog("pmset: osascript launch failed: \(error)")
            return false
        }
        process.waitUntilExit()
        let ok = process.terminationStatus == 0
        DZLog("pmset disablesleep \(value) via sudoers install: status=\(process.terminationStatus)")
        return ok
    }

    /// Returns true when an external display is active while the lid is closed
    /// (clamshell mode): the built-in panel is in hardware sleep so only external
    /// displays appear in `CGGetActiveDisplayList`.
    private static func hasActiveExternalDisplay() -> Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &count)
        return Array(ids.prefix(Int(count))).contains { CGDisplayIsBuiltin($0) == 0 }
    }

    /// Requests system sleep, then retries a few times in case the first request is vetoed
    /// (macOS is known to sometimes ignore the first sleep request after a policy change —
    /// see "macOS won't sleep from the Apple menu" reports requiring multiple attempts).
    /// If the Mac actually sleeps, the process suspends and later-scheduled retries simply
    /// never fire until wake, at which point they are harmless no-ops if state has changed.
    private func triggerSystemSleep(attempt: Int = 0) {
        // Primary: pmset sleepnow is user-accessible without root (documented in man pmset).
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["sleepnow"]
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do {
            try p.run()
            p.waitUntilExit()
            DZLog("triggerSystemSleep: pmset sleepnow attempt=\(attempt) status=\(p.terminationStatus)")
        } catch {
            DZLog("triggerSystemSleep: pmset sleepnow attempt=\(attempt) launch failed: \(error)")
        }

        // Belt-and-suspenders: IOPMSleepSystem as a secondary path.
        let fb = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        if fb != MACH_PORT_NULL {
            let result = IOPMSleepSystem(fb)
            mach_port_deallocate(mach_task_self_, fb)
            DZLog("triggerSystemSleep: IOPMSleepSystem attempt=\(attempt) result=\(result)")
        }

        guard attempt < 2 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard
                let self,
                self.isCurrentlyPreventing == false,
                LidStateMonitor.isClosed(),
                !SleepPreventionManager.hasActiveExternalDisplay() else { return }
            self.triggerSystemSleep(attempt: attempt + 1)
        }
    }

    private func syncLidMonitoring() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.preventLidCloseSleep, self.dimOnLidClose || self.dimScreenOnLidClose {
                LidStateMonitor.shared.onLidClosed = { [weak self] in self?.handleLidClosed() }
                LidStateMonitor.shared.onLidOpened = { [weak self] in self?.handleLidOpened() }
                LidStateMonitor.shared.start()
            } else {
                LidStateMonitor.shared.stop()
                LidStateMonitor.shared.onLidClosed = nil
                LidStateMonitor.shared.onLidOpened = nil
            }
        }
    }

    private func handleLidClosed() {
        self.savedBacklightState = BacklightController.captureState()
        if self.dimScreenOnLidClose { BacklightController.dimDisplays() }
        if self.dimOnLidClose { BacklightController.dimKeyboard() }
    }

    private func handleLidOpened() {
        guard let state = self.savedBacklightState else { return }
        self.savedBacklightState = nil
        if self.dimOnLidClose { BacklightController.restoreKeyboard(state.keyboard) }
        if self.dimScreenOnLidClose {
            // Delay slightly so the panel fully exits hardware sleep before we write brightness.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                BacklightController.restoreDisplays(state.displays)
            }
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
        self.releaseAssertions()
    }

    @objc
    private func sessionDidBecomeActive() {
        self.isUserSessionActive = true
        if self.isCurrentlyPreventing {
            self.acquireAssertions()
        }
    }
}
