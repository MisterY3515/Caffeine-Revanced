//
//  ProfileManager.swift
//  Caffeine
//

import Foundation

/// A saved snapshot of activation-related preferences that can be re-applied later.
struct Profile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var defaultDuration: Int
    var powerActivationEnabled: Bool
    var externalDisplayActivation: Bool
    var audioActivation: Bool
    var inactivityDeactivationEnabled: Bool
    var inactivityThreshold: Int
    var cpuActivationEnabled: Bool
    var cpuThreshold: Int
    var claudeCodeActivation: Bool
    var appActivationEnabled: Bool
    var appActivationApps: Data?
    var networkActivationEnabled: Bool
    var networkActivationSSIDs: Data?
    var batteryThresholdEnabled: Bool
    var batteryThreshold: Int
    var preventSleepOnLidClose: Bool
    var dimScreenOnLidClose: Bool
    var dimOnLidClose: Bool
}

/// Stores up to 5 `Profile` snapshots as JSON in `UserDefaults` and applies them by
/// writing every captured preference back and calling the matching `CaffeineViewModel`
/// update helper, mirroring what the Preferences UI does for each toggle.
enum ProfileManager {
    static let maxProfiles = 5

    static func load() -> [Profile] {
        guard
            let data = UserDefaults.standard.data(forKey: PreferenceKeys.profiles),
            let profiles = try? JSONDecoder().decode([Profile].self, from: data) else { return [] }
        return profiles
    }

    static func save(_ profiles: [Profile]) {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: PreferenceKeys.profiles)
        }
    }

    static func captureCurrent(name: String) -> Profile {
        let defaults = UserDefaults.standard
        return Profile(
            name: name,
            defaultDuration: defaults.integer(forKey: PreferenceKeys.defaultDuration),
            powerActivationEnabled: defaults.bool(forKey: PreferenceKeys.powerActivationEnabled),
            externalDisplayActivation: defaults.bool(forKey: PreferenceKeys.externalDisplayActivation),
            audioActivation: defaults.bool(forKey: PreferenceKeys.audioActivation),
            inactivityDeactivationEnabled: defaults.bool(
                forKey: PreferenceKeys.inactivityDeactivationEnabled
            ),
            inactivityThreshold: defaults.integer(forKey: PreferenceKeys.inactivityThreshold),
            cpuActivationEnabled: defaults.bool(forKey: PreferenceKeys.cpuActivationEnabled),
            cpuThreshold: defaults.integer(forKey: PreferenceKeys.cpuThreshold),
            claudeCodeActivation: defaults.bool(forKey: PreferenceKeys.claudeCodeActivation),
            appActivationEnabled: defaults.bool(forKey: PreferenceKeys.appActivationEnabled),
            appActivationApps: defaults.data(forKey: PreferenceKeys.appActivationApps),
            networkActivationEnabled: defaults.bool(forKey: PreferenceKeys.networkActivationEnabled),
            networkActivationSSIDs: defaults.data(forKey: PreferenceKeys.networkActivationSSIDs),
            batteryThresholdEnabled: defaults.bool(forKey: PreferenceKeys.batteryThresholdEnabled),
            batteryThreshold: defaults.integer(forKey: PreferenceKeys.batteryThreshold),
            preventSleepOnLidClose: defaults.bool(forKey: PreferenceKeys.preventSleepOnLidClose),
            dimScreenOnLidClose: defaults.bool(forKey: PreferenceKeys.dimScreenOnLidClose),
            dimOnLidClose: defaults.bool(forKey: PreferenceKeys.dimOnLidClose)
        )
    }

    @MainActor
    static func apply(_ profile: Profile, to viewModel: CaffeineViewModel) {
        let defaults = UserDefaults.standard
        defaults.set(profile.defaultDuration, forKey: PreferenceKeys.defaultDuration)
        defaults.set(profile.batteryThresholdEnabled, forKey: PreferenceKeys.batteryThresholdEnabled)
        defaults.set(profile.batteryThreshold, forKey: PreferenceKeys.batteryThreshold)
        if let apps = profile.appActivationApps {
            defaults.set(apps, forKey: PreferenceKeys.appActivationApps)
        }
        if let ssids = profile.networkActivationSSIDs {
            defaults.set(ssids, forKey: PreferenceKeys.networkActivationSSIDs)
        }

        // SleepPreventionManager reads this property directly (same as CaffeineViewModel.init()).
        SleepPreventionManager.shared.preventLidCloseSleep = profile.preventSleepOnLidClose
        defaults.set(profile.preventSleepOnLidClose, forKey: PreferenceKeys.preventSleepOnLidClose)

        viewModel.updatePowerActivation(enabled: profile.powerActivationEnabled)
        viewModel.updateExternalDisplayActivation(enabled: profile.externalDisplayActivation)
        viewModel.updateAudioActivation(enabled: profile.audioActivation)
        viewModel.updateInactivityDeactivation(
            enabled: profile.inactivityDeactivationEnabled, threshold: profile.inactivityThreshold
        )
        viewModel.updateCPUActivation(enabled: profile.cpuActivationEnabled, threshold: profile.cpuThreshold)
        viewModel.updateClaudeCodeActivation(enabled: profile.claudeCodeActivation)
        viewModel.updateAppActivation(enabled: profile.appActivationEnabled)
        viewModel.updateNetworkActivation(enabled: profile.networkActivationEnabled)
        viewModel.updateDimOnLidClose(enabled: profile.dimOnLidClose)
        viewModel.updateDimScreenOnLidClose(enabled: profile.dimScreenOnLidClose)

        defaults.set(profile.appActivationEnabled, forKey: PreferenceKeys.appActivationEnabled)
        defaults.set(profile.networkActivationEnabled, forKey: PreferenceKeys.networkActivationEnabled)
        defaults.set(profile.dimOnLidClose, forKey: PreferenceKeys.dimOnLidClose)
        defaults.set(profile.dimScreenOnLidClose, forKey: PreferenceKeys.dimScreenOnLidClose)
    }
}
