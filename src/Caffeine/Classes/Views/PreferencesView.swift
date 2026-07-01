//
//  PreferencesView.swift
//  Caffeine
//

import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct PreferencesView: View {
    @ObservedObject var viewModel: CaffeineViewModel

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GeneralSection(viewModel: self.viewModel)
                    sectionDivider(String(localized: "Sleep"))
                    SleepSection(viewModel: self.viewModel)
                    sectionDivider(String(localized: "Shortcut"))
                    ShortcutSection(viewModel: self.viewModel)
                    sectionDivider(String(localized: "Auto-Activate"))
                    AutoActivateSection(viewModel: self.viewModel)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            Divider()
            footerView
        }
        .frame(width: 680)
    }

    private func sectionDivider(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 8)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "Caffeine Revanced is now running. You can find its icon in the right side of your menu bar. Click it to disable automatic sleep, click it again to enable automatic sleep."
                )
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)

                Text("Right-click (or ⌃-click) the menu bar icon to show the Caffeine Revanced menu.")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button(String(localized: "Quit")) { NSApp.terminate(nil) }
                .controlSize(.large)
            Spacer()
            Button(String(localized: "Close")) { NSApp.keyWindow?.close() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - General Section

private struct GeneralSection: View {
    @ObservedObject var viewModel: CaffeineViewModel

    @AppStorage(PreferenceKeys.defaultDuration) private var defaultDuration = 0
    @AppStorage(PreferenceKeys.activateAtLaunch) private var activateAtLaunch = false
    @AppStorage(PreferenceKeys.deactivateOnManualSleep) private var deactivateOnManualSleep = false
    @AppStorage(PreferenceKeys.suppressLaunchMessage) private var suppressLaunchMessage = false
    @AppStorage(PreferenceKeys.keepAppsActive) private var keepAppsActive = false
    @AppStorage(PreferenceKeys.showTimeInMenuBar) private var showTimeInMenuBar = false
    @AppStorage(PreferenceKeys.notifyOnExpiry) private var notifyOnExpiry = false
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Default duration:")
                    .font(.system(size: 13))

                Picker("", selection: self.$defaultDuration) {
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                    Text("5 hours").tag(300)
                    Text("Indefinitely").tag(0)
                }
                .pickerStyle(.menu)
                .frame(width: 180)

                Spacer()
            }
            .padding(.bottom, 8)

            Toggle("Activate when starting Caffeine Revanced", isOn: self.$activateAtLaunch)
                .font(.system(size: 13))

            Toggle("Deactivate when device goes to sleep manually", isOn: self.$deactivateOnManualSleep)
                .font(.system(size: 13))

            Toggle(
                "Show this message when starting Caffeine Revanced",
                isOn: Binding(
                    get: { !self.suppressLaunchMessage },
                    set: { self.suppressLaunchMessage = !$0 }
                )
            )
            .font(.system(size: 13))

            Toggle("Launch at Login", isOn: self.$launchAtLogin)
                .font(.system(size: 13))
                .onChange(of: self.launchAtLogin) { _, newValue in
                    if newValue {
                        try? SMAppService.mainApp.register()
                    } else {
                        try? SMAppService.mainApp.unregister()
                    }
                }

            descriptionText("Automatically start Caffeine Revanced when you log in.")

            Divider().padding(.vertical, 6)

            Toggle(
                "Keep apps active",
                isOn: Binding(
                    get: { self.keepAppsActive },
                    set: { newValue in
                        self.keepAppsActive = newValue
                        self.viewModel.updateActivitySimulation(enabled: newValue)
                    }
                )
            )
            .font(.system(size: 13))

            descriptionText("Prevents apps from becoming inactive and the screen saver from starting.")

            Divider().padding(.vertical, 6)

            Toggle("Show time remaining in menu bar", isOn: self.$showTimeInMenuBar)
                .font(.system(size: 13))

            descriptionText("Displays the countdown timer next to the menu bar icon.")

            Divider().padding(.vertical, 6)

            Toggle(
                "Notify when timer expires",
                isOn: Binding(
                    get: { self.notifyOnExpiry },
                    set: { newValue in
                        self.notifyOnExpiry = newValue
                        if newValue {
                            self.viewModel.requestNotificationAuthorization()
                        }
                    }
                )
            )
            .font(.system(size: 13))

            descriptionText("Shows a system notification when the activation period ends.")
        }
    }
}

// MARK: - Sleep Section

private struct SleepSection: View {
    @ObservedObject var viewModel: CaffeineViewModel

    @AppStorage(PreferenceKeys.preventSleepOnLidClose) private var preventSleepOnLidClose = false
    @AppStorage(PreferenceKeys.dimOnLidClose) private var dimOnLidClose = false
    @AppStorage(PreferenceKeys.batteryThresholdEnabled) private var batteryThresholdEnabled = false
    @AppStorage(PreferenceKeys.batteryThreshold) private var batteryThreshold = 20

    @State private var showSudoersAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "Prevent sleep when lid is closed",
                isOn: Binding(
                    get: { self.preventSleepOnLidClose },
                    set: { newValue in
                        if newValue {
                            self.preventSleepOnLidClose = true
                            self.showSudoersAlert = true
                        } else {
                            self.preventSleepOnLidClose = false
                            self.viewModel.updateLidCloseSleepPrevention(enabled: false) { success in
                                if !success { self.preventSleepOnLidClose = true }
                            }
                        }
                    }
                )
            )
            .font(.system(size: 13))
            .alert(
                String(localized: "Administrator Access Required"),
                isPresented: self.$showSudoersAlert
            ) {
                Button(String(localized: "Continue")) {
                    self.viewModel.updateLidCloseSleepPrevention(enabled: true) { success in
                        if !success { self.preventSleepOnLidClose = false }
                    }
                }
                Button(String(localized: "Cancel"), role: .cancel) {
                    self.preventSleepOnLidClose = false
                }
            } message: {
                Text(
                    "Enabling this option creates a system file that allows Caffeine Revanced to prevent lid-close sleep without asking for your password each time. Disabling will remove the file automatically."
                )
            }

            descriptionText(
                "Keeps the Mac awake when the lid is closed while Caffeine Revanced is running. Requires one-time administrator authorization."
            )

            Toggle(
                "Dim backlight when lid is closed",
                isOn: Binding(
                    get: { self.dimOnLidClose },
                    set: { newValue in
                        self.dimOnLidClose = newValue
                        self.viewModel.updateDimOnLidClose(enabled: newValue)
                    }
                )
            )
            .font(.system(size: 13))
            .disabled(!self.preventSleepOnLidClose)
            .padding(.leading, 20)
            .padding(.top, 4)

            descriptionText(
                "Dims the display and keyboard backlight to zero when the lid is closed, restoring them when reopened."
            )

            Divider().padding(.vertical, 6)

            Toggle(String(localized: "Deactivate on low battery"), isOn: self.$batteryThresholdEnabled)
                .font(.system(size: 13))

            if self.batteryThresholdEnabled {
                HStack(spacing: 10) {
                    Text("Threshold:")
                        .font(.system(size: 12))
                    Slider(
                        value: Binding(
                            get: { Double(self.batteryThreshold) },
                            set: { self.batteryThreshold = Int($0) }
                        ), in: 5...50, step: 5)
                    Text("\(self.batteryThreshold)%")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 36, alignment: .trailing)
                }
                .padding(.leading, 20)
            }

            descriptionText(
                "Automatically deactivates when on battery power and the battery level drops below the threshold."
            )
        }
    }
}

// MARK: - Shortcut Section

private struct ShortcutSection: View {
    @ObservedObject var viewModel: CaffeineViewModel
    @AppStorage(PreferenceKeys.globalHotkeyEnabled) private var globalHotkeyEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "Enable global keyboard shortcut (⌘⌥C)",
                isOn: Binding(
                    get: { self.globalHotkeyEnabled },
                    set: { newValue in
                        self.globalHotkeyEnabled = newValue
                        self.viewModel.updateGlobalHotkey(enabled: newValue)
                    }
                )
            )
            .font(.system(size: 13))

            descriptionText(
                "Toggles Caffeine Revanced on and off from anywhere in the system. Requires Accessibility permission (System Settings → Privacy & Security → Accessibility)."
            )
        }
    }
}

// MARK: - Auto-Activate Section

private struct AutoActivateSection: View {
    @ObservedObject var viewModel: CaffeineViewModel

    @AppStorage(PreferenceKeys.powerActivationEnabled) private var powerActivationEnabled = false
    @AppStorage(PreferenceKeys.claudeCodeActivation) private var claudeCodeActivation = false
    @AppStorage(PreferenceKeys.appActivationEnabled) private var appActivationEnabled = false
    @AppStorage(PreferenceKeys.networkActivationEnabled) private var networkActivationEnabled = false

    @State private var watchedApps: [WatchedApp] = []
    @State private var watchedNetworks: [String] = []
    @State private var newNetworkName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "Activate when connected to power",
                isOn: Binding(
                    get: { self.powerActivationEnabled },
                    set: { newValue in
                        self.powerActivationEnabled = newValue
                        self.viewModel.updatePowerActivation(enabled: newValue)
                    }
                )
            )
            .font(.system(size: 13))

            descriptionText(
                "Automatically activates when the Mac is connected to AC power, and deactivates when it switches to battery."
            )

            Divider().padding(.vertical, 6)

            Toggle(
                "Activate when Claude Code is running",
                isOn: Binding(
                    get: { self.claudeCodeActivation },
                    set: { newValue in
                        self.claudeCodeActivation = newValue
                        self.viewModel.updateClaudeCodeActivation(enabled: newValue)
                    }
                )
            )
            .font(.system(size: 13))

            descriptionText("Automatically activates while the Claude Code CLI is running.")

            Divider().padding(.vertical, 6)

            Toggle(
                "Activate when these apps are in the foreground",
                isOn: Binding(
                    get: { self.appActivationEnabled },
                    set: { newValue in
                        self.appActivationEnabled = newValue
                        self.viewModel.updateAppActivation(enabled: newValue)
                    }
                )
            )
            .font(.system(size: 13))

            descriptionText(
                "Automatically activates when any of these apps is the frontmost application.")

            appList

            Divider().padding(.vertical, 6)

            Toggle(
                "Activate on these Wi-Fi networks",
                isOn: Binding(
                    get: { self.networkActivationEnabled },
                    set: { newValue in
                        self.networkActivationEnabled = newValue
                        self.viewModel.updateNetworkActivation(enabled: newValue)
                    }
                )
            )
            .font(.system(size: 13))

            descriptionText("Automatically activates when connected to any of these Wi-Fi networks.")

            networkList
        }
        .onAppear {
            self.watchedApps = self.viewModel.watchedApps()
            self.watchedNetworks = self.viewModel.watchedNetworks()
        }
    }

    private var appList: some View {
        VStack(alignment: .leading, spacing: 4) {
            if self.watchedApps.isEmpty {
                Text("No apps added. Click Add App to get started.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
            } else {
                ForEach(self.watchedApps) { app in
                    HStack {
                        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
                        let icon = appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
                        if let icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                        Text(app.name)
                            .font(.system(size: 12))
                        Text(app.bundleID)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(String(localized: "Remove")) {
                            self.watchedApps.removeAll { $0.bundleID == app.bundleID }
                            self.viewModel.saveWatchedApps(self.watchedApps)
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.borderless)
                        .foregroundColor(.red)
                    }
                    .padding(.leading, 20)
                }
            }

            Button(String(localized: "Add App...")) {
                self.pickApp()
            }
            .padding(.leading, 20)
            .padding(.top, 2)
        }
    }

    private var networkList: some View {
        VStack(alignment: .leading, spacing: 4) {
            if self.watchedNetworks.isEmpty {
                Text("No networks added.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
            } else {
                ForEach(self.watchedNetworks, id: \.self) { ssid in
                    HStack {
                        Image(systemName: "wifi")
                            .font(.system(size: 12))
                        Text(ssid)
                            .font(.system(size: 12))
                        Spacer()
                        Button(String(localized: "Remove")) {
                            self.watchedNetworks.removeAll { $0 == ssid }
                            self.viewModel.saveWatchedNetworks(self.watchedNetworks)
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.borderless)
                        .foregroundColor(.red)
                    }
                    .padding(.leading, 20)
                }
            }

            HStack(spacing: 6) {
                Button(String(localized: "Add Current Network")) {
                    if let ssid = NetworkMonitor.shared.currentSSID, !ssid.isEmpty,
                        !self.watchedNetworks.contains(ssid)
                    {
                        self.watchedNetworks.append(ssid)
                        self.viewModel.saveWatchedNetworks(self.watchedNetworks)
                    }
                }

                TextField("Enter network name...", text: self.$newNetworkName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onSubmit { self.addManualNetwork() }

                Button("+") { self.addManualNetwork() }
                    .disabled(self.newNetworkName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.leading, 20)
            .padding(.top, 2)
        }
    }

    private func addManualNetwork() {
        let name = self.newNetworkName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !self.watchedNetworks.contains(name) else { return }
        self.watchedNetworks.append(name)
        self.viewModel.saveWatchedNetworks(self.watchedNetworks)
        self.newNetworkName = ""
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.title = String(localized: "Add App...")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let bundle = Bundle(url: url)
        let bundleID = bundle?.bundleIdentifier ?? url.deletingPathExtension().lastPathComponent
        let name =
            bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent

        guard !self.watchedApps.contains(where: { $0.bundleID == bundleID }) else { return }

        self.watchedApps.append(WatchedApp(bundleID: bundleID, name: name))
        self.viewModel.saveWatchedApps(self.watchedApps)
    }
}

// MARK: - Shared Helper

private func descriptionText(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(.leading, 20)
        .fixedSize(horizontal: false, vertical: true)
}

#Preview {
    PreferencesView(viewModel: CaffeineViewModel())
        .environment(\.locale, .init(identifier: "en"))
}
