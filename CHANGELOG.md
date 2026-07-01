# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- "Prevent sleep when lid is closed" preference: keeps the Mac awake when the lid is closed while Caffeine Revanced is active.
- "Dim backlight when lid is closed" preference (under lid-close sleep): automatically dims display and keyboard backlight to zero when the lid is closed, restoring them on lid open.
- "Activate when connected to power" preference: automatically activates when the Mac is connected to AC power and deactivates when it switches to battery.
- Launch at Login: automatically start Caffeine Revanced at login via SMAppService.
- Show time remaining in menu bar: displays countdown timer next to the menu bar icon.
- Notify when timer expires: sends a system notification when the activation period ends.
- Deactivate on low battery: auto-deactivates when on battery power below a configurable threshold.
- Global keyboard shortcut ⌘⌥C: toggles Caffeine Revanced from anywhere in the system (requires Accessibility permission in System Settings).
- Auto-activate when Claude Code CLI is running: activates automatically while `claude` process is detected; deactivates when it exits.
- Auto-activate for specific apps: activates when a watched app is the frontmost application.
- Auto-activate on specific Wi-Fi networks: activates when connected to a saved SSID.
- Preferences reorganised into four tabs: General, Sleep, Shortcut, Auto-Activate.

### Changed

- Renamed to Caffeine Revanced throughout all user-facing strings and all 13 localizations.
- Improved Ukrainian translation.

### Fixed

- Timer no longer stays active and shows negative seconds after the Mac sleeps past the activation period.
- Global shortcut ⌘⌥C now correctly toggles Caffeine when enabled from Preferences (callback was only wired at launch if already enabled).
- Claude Code auto-activation now detects `claude` immediately when the feature is enabled, without waiting for the next 5-second poll.
- Display sleep assertion timeout increased from 8 s to 20 s to eliminate a 2-second gap between the 10-second refresh timer and assertion expiry.
- "Prevent sleep when lid is closed" now uses `pmset -a disablesleep` via a sudoers entry (`/etc/sudoers.d/caffeine-revanced`) written on first use. A single administrator password prompt appears when enabling the preference; all subsequent activations and deactivations run silently without any dialog. Disabling the preference removes the sudoers file automatically.
- Sleep prevention now holds two IOPMAssertions simultaneously (`NoDisplaySleep` + `NoIdleSleep`) with no timeout, eliminating the timing gap that previously caused the Mac to enter standby.

## [1.6.3] - 2026-01-26

### Added

- Ukrainian translation.

### Fixed

- Activity simulation now properly resets the system idle timer.

## [1.6.2] - 2025-12-14

### Added

- Optional "Keep apps active" preference that simulates activity to prevent apps from going idle.

### Fixed

- Corrected the Control-click instruction symbol.

## [1.6.1] - 2025-11-13

### Fixed

- Menu bar icon tinting.

## [1.6.0] - 2025-11-12

### Added

- Rewritten in SwiftUI.
- Automatic update reminders via Sparkle.
- App accent color and category.

### Changed

- Updated the icon for Tahoe with a static gradient.
- Repositioned menu items.

### Fixed

- Entitlements.
- Deprecation warnings.
- Typo on the preferences screen.

## [1.5.3] - 2025-06-25

### Added

- Control-click is now treated the same as a right-click.

## [1.5.2] - 2025-05-23

### Fixed

- Default duration is now respected.

## [1.5.1] - 2025-03-03

### Fixed

- Preferences window no longer appears unexpectedly on launch.

## [1.5.0] - 2025-01-22

### Added

- Automatic updates via Sparkle.

### Changed

- Migrated the project to Swift.
- Updated for macOS Sequoia.

## [1.4.0] - 2023-10-17

### Changed

- Updated icon for macOS Sonoma.

## [1.3.0] - 2023-10-17

### Added

- Japanese localization, plus localizations with dynamic layout support.
- Preference to deactivate Caffeine when the device is manually put to sleep.
- Sonoma-styled app icon.
- GitHub sponsorship support.

### Changed

- Refactored the preferences window.

### Fixed

- Deactivating the app now reliably releases the system sleep assertion.
- App icon drop shadow.
- View autoresizing.

## [1.1.3] - 2020-05-12

### Added

- Initial public release.
