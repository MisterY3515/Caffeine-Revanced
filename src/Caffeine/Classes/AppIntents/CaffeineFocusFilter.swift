//
//  CaffeineFocusFilter.swift
//  Caffeine
//

import AppIntents

/// Lets a Focus (e.g. Do Not Disturb, Work) activate or deactivate Caffeine Revanced.
/// Configured under System Settings > Focus > [a Focus] > Focus Filters.
///
/// Apple only calls `perform()` while the app is running; a change made to this
/// filter while Caffeine Revanced is not running has no effect until relaunch.
struct CaffeineFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Caffeine Revanced"

    @Parameter(title: "Activate Caffeine Revanced", default: true)
    var isActive: Bool

    @Dependency
    private var viewModel: CaffeineViewModel

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: self.isActive ? "Turn On Caffeine Revanced" : "Turn Off Caffeine Revanced"
        )
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if self.isActive {
            self.viewModel.autoActivate(source: "focus")
        } else {
            self.viewModel.autoDeactivate(source: "focus")
        }
        return .result()
    }
}
