//
//  CaffeineViewModel.swift
//  Caffeine
//

import AppKit
import Combine
import DZFoundation
import ServiceManagement
import SwiftUI
import UserNotifications

struct WatchedApp: Codable, Identifiable, Equatable {
    let bundleID: String
    let name: String
    var id: String {
        self.bundleID
    }
}

@MainActor
class CaffeineViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var isActive = false
    @Published var timeRemaining: TimeInterval?
    @Published var showPreferences = false

    // MARK: - Private Properties

    private var timeoutTimer: Timer?
    private var displayTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private var manuallyActivated = false
    private var autoActiveSources = Set<String>()
    private var suppressedAutoSources = Set<String>()

    // MARK: - Initialization

    init() {
        self.isActive = false
        self.timeRemaining = nil

        self.setupObservers()
        self.setupMonitors()

        SleepPreventionManager.shared.preventLidCloseSleep =
            UserDefaults.standard.bool(forKey: PreferenceKeys.preventSleepOnLidClose)
        SleepPreventionManager.shared.dimOnLidClose =
            UserDefaults.standard.bool(forKey: PreferenceKeys.dimOnLidClose)
        SleepPreventionManager.shared.dimScreenOnLidClose =
            UserDefaults.standard.bool(forKey: PreferenceKeys.dimScreenOnLidClose)

        if UserDefaults.standard.bool(forKey: PreferenceKeys.activateAtLaunch) {
            self.activate(promptForAuth: false)
        }

        if !UserDefaults.standard.bool(forKey: PreferenceKeys.suppressLaunchMessage) {
            self.showPreferences = true
        }
    }

    // MARK: - Public Methods

    func toggleActive() {
        if self.isActive {
            self.suppressedAutoSources.formUnion(self.autoActiveSources)
            self.autoActiveSources.removeAll()
            self.manuallyActivated = false
            self.deactivate(promptForAuth: true)
        } else {
            self.manuallyActivated = true
            self.suppressedAutoSources.removeAll()
            self.activate()
        }
    }

    /// Activates Caffeine. The icon changes immediately.
    ///
    /// If lid-close prevention is enabled and credentials are not cached, the
    /// system password dialog appears after activation — cancelling it leaves
    /// Caffeine active but without lid-close prevention for this session.
    ///
    /// Pass `promptForAuth: false` for automated activations so no unexpected
    /// dialog appears without direct user intent.
    func activate(withTimeout timeout: TimeInterval? = nil, promptForAuth: Bool = true) {
        self.startActivation(withTimeout: timeout, promptForAuth: promptForAuth)
    }

    private func startActivation(withTimeout timeout: TimeInterval?, promptForAuth: Bool = true) {
        let duration: TimeInterval?
        if let timeout {
            duration = timeout > 0 ? timeout : nil
        } else {
            let defaultMinutes = UserDefaults.standard.integer(forKey: PreferenceKeys.defaultDuration)
            duration = defaultMinutes > 0 ? TimeInterval(defaultMinutes * 60) : nil
        }

        self.cancelTimers()

        if let duration {
            self.timeRemaining = duration

            self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) {
                [weak self] _ in
                DispatchQueue.main.async { self?.handleTimerExpiry() }
            }

            self.displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
                [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, let timeoutTimer = self.timeoutTimer else {
                        self?.displayTimer?.invalidate()
                        return
                    }
                    self.timeRemaining = max(0, timeoutTimer.fireDate.timeIntervalSinceNow)
                    if self.timeRemaining ?? 0 <= 0 {
                        self.displayTimer?.invalidate()
                        self.displayTimer = nil
                    }
                }
            }
        } else {
            self.timeRemaining = nil
        }

        self.isActive = true
        SleepPreventionManager.shared.preventSleep(promptIfNeeded: promptForAuth)

        if UserDefaults.standard.bool(forKey: PreferenceKeys.keepAppsActive) {
            ActivitySimulator.shared.startMonitoring()
        }
    }

    func deactivate(promptForAuth: Bool = false) {
        self.cancelTimers()
        self.timeRemaining = nil
        self.isActive = false
        SleepPreventionManager.shared.allowSleep(promptIfNeeded: promptForAuth)
        ActivitySimulator.shared.stopMonitoring()
    }

    // MARK: - Auto-Activation

    func autoActivate(source: String) {
        guard !self.suppressedAutoSources.contains(source) else {
            DZLog("autoActivate: \(source) suppressed")
            return
        }
        self.autoActiveSources.insert(source)
        DZLog("autoActivate: \(source), sources=\(self.autoActiveSources)")
        if !self.isActive {
            self.activate(promptForAuth: false)
        }
    }

    func autoDeactivate(source: String) {
        self.autoActiveSources.remove(source)
        self.suppressedAutoSources.remove(source)
        DZLog("autoDeactivate: \(source), remaining=\(self.autoActiveSources)")
        if self.autoActiveSources.isEmpty, !self.manuallyActivated, self.isActive {
            self.deactivate()
        }
    }

    // MARK: - Preference Update Helpers

    /// Called when the user toggles "Prevent sleep when lid is closed" in Preferences.
    ///
    /// Enabling installs `/etc/sudoers.d/caffeine-revanced` on first use (one admin
    /// password prompt) so all future pmset calls are silent. Disabling removes
    /// the sudoers file automatically. Rolls back the preference on failure.
    func updateLidCloseSleepPrevention(enabled: Bool, completion: @escaping (Bool) -> Void) {
        SleepPreventionManager.shared.preventLidCloseSleep = enabled

        if enabled {
            if self.isActive {
                // Caffeine running: apply pmset 1 now (installs sudoers if first use).
                SleepPreventionManager.shared.applyLidCloseChange(true, promptIfNeeded: true) { success in
                    if !success { SleepPreventionManager.shared.preventLidCloseSleep = false }
                    completion(success)
                }
            } else {
                // Caffeine not running: install sudoers entry now (pmset 0, no-op for sleep state)
                // so activation/deactivation later are fully silent.
                SleepPreventionManager.shared.ensureAdminAccess { success in
                    if !success { SleepPreventionManager.shared.preventLidCloseSleep = false }
                    completion(success)
                }
            }
        } else {
            // Disabling: restore pmset 0 if Caffeine is active, then remove sudoers file.
            if self.isActive {
                SleepPreventionManager.shared.applyLidCloseChange(false, promptIfNeeded: true) { success in
                    if !success { SleepPreventionManager.shared.preventLidCloseSleep = true }
                    SleepPreventionManager.shared.removeSudoersEntry { _ in }
                    completion(success)
                }
            } else {
                SleepPreventionManager.shared.removeSudoersEntry { _ in }
                completion(true)
            }
        }
    }

    func updateActivitySimulation(enabled: Bool) {
        if enabled {
            ActivitySimulator.shared.requestPermission()
        }
        if enabled, self.isActive {
            ActivitySimulator.shared.startMonitoring()
        } else {
            ActivitySimulator.shared.stopMonitoring()
        }
    }

    func updateGlobalHotkey(enabled: Bool) {
        if enabled {
            HotkeyManager.shared.register()
        } else {
            HotkeyManager.shared.unregister()
        }
    }

    func updateClaudeCodeActivation(enabled: Bool) {
        if enabled {
            ProcessMonitor.shared.watch(processName: "claude")
            if !ProcessMonitor.shared.isRunning {
                ProcessMonitor.shared.start()
            }
        } else {
            ProcessMonitor.shared.unwatch(processName: "claude")
            self.autoDeactivate(source: "claude")
            if ProcessMonitor.shared.watchedProcessNames.isEmpty {
                ProcessMonitor.shared.stop()
            }
        }
    }

    func updateNetworkActivation(enabled: Bool) {
        if enabled {
            NetworkMonitor.shared.start()
            if let ssid = NetworkMonitor.shared.currentSSID {
                self.handleSSIDChange(ssid)
            }
        } else {
            NetworkMonitor.shared.stop()
            self.autoDeactivate(source: "network")
        }
    }

    func updateAppActivation(enabled: Bool) {
        if !enabled {
            self.autoDeactivate(source: "appActivation")
        }
    }

    func updateDimOnLidClose(enabled: Bool) {
        SleepPreventionManager.shared.dimOnLidClose = enabled
    }

    func updateDimScreenOnLidClose(enabled: Bool) {
        SleepPreventionManager.shared.dimScreenOnLidClose = enabled
    }

    func updatePowerActivation(enabled: Bool) {
        if !enabled {
            self.autoDeactivate(source: "power")
        } else {
            let (_, isOnBattery) = BatteryMonitor.currentState()
            if !isOnBattery {
                self.autoActivate(source: "power")
            }
        }
    }

    func updateExternalDisplayActivation(enabled: Bool) {
        if enabled {
            ExternalDisplayMonitor.shared.start()
            if ExternalDisplayMonitor.hasExternalDisplay() {
                self.autoActivate(source: "externalDisplay")
            }
        } else {
            ExternalDisplayMonitor.shared.stop()
            self.autoDeactivate(source: "externalDisplay")
        }
    }

    func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
            granted, error in
            DZLog("Notification authorization granted=\(granted)")
            DZErrorLog(error)
        }
    }

    // MARK: - Watched Apps

    func watchedApps() -> [WatchedApp] {
        guard
            let data = UserDefaults.standard.data(forKey: PreferenceKeys.appActivationApps),
            let apps = try? JSONDecoder().decode([WatchedApp].self, from: data) else { return [] }
        return apps
    }

    func saveWatchedApps(_ apps: [WatchedApp]) {
        if let data = try? JSONEncoder().encode(apps) {
            UserDefaults.standard.set(data, forKey: PreferenceKeys.appActivationApps)
        }
    }

    // MARK: - Watched Networks

    func watchedNetworks() -> [String] {
        guard
            let data = UserDefaults.standard.data(forKey: PreferenceKeys.networkActivationSSIDs),
            let nets = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return nets
    }

    func saveWatchedNetworks(_ networks: [String]) {
        if let data = try? JSONEncoder().encode(networks) {
            UserDefaults.standard.set(data, forKey: PreferenceKeys.networkActivationSSIDs)
        }
    }

    // MARK: - Formatted Time

    func formattedTimeRemaining() -> String? {
        guard self.isActive else { return nil }

        if let remaining = self.timeRemaining, remaining > 0 {
            let seconds = Int(remaining)
            if seconds >= 3600 {
                return String(format: "%02d:%02d", seconds / 3600, (seconds % 3600) / 60)
            } else if seconds > 60 {
                let format = String(localized: "%d minutes", comment: "Time remaining in minutes")
                return String.localizedStringWithFormat(format, seconds / 60)
            } else {
                let format = String(localized: "%d seconds", comment: "Time remaining in seconds")
                return String.localizedStringWithFormat(format, seconds)
            }
        }

        return String(localized: "Caffeine Revanced is active")
    }

    func formattedTimeRemainingShort() -> String? {
        guard self.isActive, let remaining = self.timeRemaining, remaining > 0 else { return nil }
        let s = Int(remaining)
        if s >= 3600 {
            return String(format: "%d:%02d", s / 3600, (s % 3600) / 60)
        } else {
            return String(format: "%d:%02d", s / 60, s % 60)
        }
    }

    // MARK: - Private Methods

    private func setupObservers() {
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    if UserDefaults.standard.bool(forKey: PreferenceKeys.deactivateOnManualSleep) {
                        self?.deactivate()
                    }
                }
            }
            .store(in: &self.cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, let timeoutTimer = self.timeoutTimer else { return }
                    if timeoutTimer.fireDate.timeIntervalSinceNow <= 0 {
                        self.deactivate()
                    }
                }
            }
            .store(in: &self.cancellables)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard UserDefaults.standard.bool(forKey: PreferenceKeys.appActivationEnabled) else { return }
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
                let bid = app.bundleIdentifier else { return }

            let watched = Set(self.watchedApps().map(\.bundleID))
            if watched.contains(bid) {
                self.autoActivate(source: "appActivation")
            } else if !watched.isEmpty {
                self.autoDeactivate(source: "appActivation")
            }
        }
    }

    private func setupMonitors() {
        BatteryMonitor.shared.onStateChanged = { [weak self] level, isOnBattery in
            guard let self else { return }

            if UserDefaults.standard.bool(forKey: PreferenceKeys.batteryThresholdEnabled) {
                let threshold = max(
                    1,
                    UserDefaults.standard.integer(forKey: PreferenceKeys.batteryThreshold)
                )
                if isOnBattery, level < threshold, self.isActive {
                    DZLog("Battery below threshold (\(level)% < \(threshold)%), deactivating")
                    self.deactivate()
                }
            }

            if UserDefaults.standard.bool(forKey: PreferenceKeys.powerActivationEnabled) {
                if !isOnBattery {
                    self.autoActivate(source: "power")
                } else {
                    self.autoDeactivate(source: "power")
                }
            }
        }
        BatteryMonitor.shared.start()

        if UserDefaults.standard.bool(forKey: PreferenceKeys.powerActivationEnabled) {
            let (_, isOnBattery) = BatteryMonitor.currentState()
            if !isOnBattery {
                self.autoActivate(source: "power")
            }
        }

        ProcessMonitor.shared.onProcessAppeared = { [weak self] name in
            Task { @MainActor in self?.autoActivate(source: name) }
        }
        ProcessMonitor.shared.onProcessDisappeared = { [weak self] name in
            Task { @MainActor in self?.autoDeactivate(source: name) }
        }

        if UserDefaults.standard.bool(forKey: PreferenceKeys.claudeCodeActivation) {
            ProcessMonitor.shared.watch(processName: "claude")
            ProcessMonitor.shared.start()
        }

        NetworkMonitor.shared.onSSIDChanged = { [weak self] ssid in
            guard let self else { return }
            self.handleSSIDChange(ssid)
        }

        if UserDefaults.standard.bool(forKey: PreferenceKeys.networkActivationEnabled) {
            NetworkMonitor.shared.start()
            if let ssid = NetworkMonitor.shared.currentSSID {
                self.handleSSIDChange(ssid)
            }
        }

        HotkeyManager.shared.onToggle = { [weak self] in
            Task { @MainActor in self?.toggleActive() }
        }
        if UserDefaults.standard.bool(forKey: PreferenceKeys.globalHotkeyEnabled) {
            HotkeyManager.shared.register()
        }

        ExternalDisplayMonitor.shared.onExternalDisplayConnected = { [weak self] in
            Task { @MainActor in self?.autoActivate(source: "externalDisplay") }
        }
        ExternalDisplayMonitor.shared.onExternalDisplayDisconnected = { [weak self] in
            Task { @MainActor in self?.autoDeactivate(source: "externalDisplay") }
        }

        if UserDefaults.standard.bool(forKey: PreferenceKeys.externalDisplayActivation) {
            ExternalDisplayMonitor.shared.start()
            if ExternalDisplayMonitor.hasExternalDisplay() {
                self.autoActivate(source: "externalDisplay")
            }
        }
    }

    private func handleSSIDChange(_ ssid: String?) {
        guard UserDefaults.standard.bool(forKey: PreferenceKeys.networkActivationEnabled) else {
            return
        }
        let watched = self.watchedNetworks()
        if let ssid, watched.contains(ssid) {
            self.autoActivate(source: "network")
        } else {
            self.autoDeactivate(source: "network")
        }
    }

    private func handleTimerExpiry() {
        self.manuallyActivated = false
        self.cancelTimers()
        self.timeRemaining = nil

        if self.autoActiveSources.isEmpty {
            self.deactivate()
            if UserDefaults.standard.bool(forKey: PreferenceKeys.notifyOnExpiry) {
                self.sendExpiryNotification()
            }
        }
    }

    private func sendExpiryNotification() {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Caffeine Revanced deactivated")
        content.body = String(localized: "The activation period has ended.")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "caffeine.expiry.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in DZErrorLog(error) }
    }

    private func cancelTimers() {
        self.timeoutTimer?.invalidate()
        self.timeoutTimer = nil
        self.displayTimer?.invalidate()
        self.displayTimer = nil
    }
}

// MARK: - Preference Keys

enum PreferenceKeys {
    static let activateAtLaunch = "CAActivateAtLaunch"
    static let defaultDuration = "CADefaultDuration"
    static let suppressLaunchMessage = "CASuppressLaunchMessage"
    static let deactivateOnManualSleep = "CADeactivateOnManualSleep"
    static let keepAppsActive = "CAKeepAppsActive"
    static let preventSleepOnLidClose = "CAPreventSleepOnLidClose"
    static let dimOnLidClose = "CADimOnLidClose"
    static let dimScreenOnLidClose = "CADimScreenOnLidClose"
    static let powerActivationEnabled = "CAPowerActivationEnabled"

    static let showTimeInMenuBar = "CAShowTimeInMenuBar"
    static let notifyOnExpiry = "CANotifyOnExpiry"
    static let batteryThresholdEnabled = "CABatteryThresholdEnabled"
    static let batteryThreshold = "CABatteryThreshold"
    static let globalHotkeyEnabled = "CAGlobalHotkeyEnabled"
    static let claudeCodeActivation = "CAClaudeCodeActivation"
    static let appActivationEnabled = "CAAppActivationEnabled"
    static let appActivationApps = "CAAppActivationApps"
    static let networkActivationEnabled = "CANetworkActivationEnabled"
    static let networkActivationSSIDs = "CANetworkActivationSSIDs"
    static let externalDisplayActivation = "CAExternalDisplayActivation"
}
