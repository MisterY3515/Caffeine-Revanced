//
//  CaffeineIntents.swift
//  Caffeine
//

import AppIntents
import Foundation

struct ToggleCaffeineIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Caffeine Revanced"
    static let description = IntentDescription("Turns Caffeine Revanced on or off.")

    @Dependency
    private var viewModel: CaffeineViewModel

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        self.viewModel.toggleActive()
        return .result(value: self.viewModel.isActive)
    }
}

struct ActivateCaffeineIntent: AppIntent {
    static let title: LocalizedStringResource = "Activate Caffeine Revanced"
    static let description = IntentDescription(
        "Activates Caffeine Revanced, optionally for a specific duration."
    )

    @Parameter(title: "Duration (minutes)", default: 0)
    var duration: Int

    @Dependency
    private var viewModel: CaffeineViewModel

    @MainActor
    func perform() async throws -> some IntentResult {
        let seconds = self.duration > 0 ? TimeInterval(self.duration * 60) : 0
        self.viewModel.activate(withTimeout: seconds, promptForAuth: false)
        return .result()
    }
}

struct DeactivateCaffeineIntent: AppIntent {
    static let title: LocalizedStringResource = "Deactivate Caffeine Revanced"
    static let description = IntentDescription("Deactivates Caffeine Revanced.")

    @Dependency
    private var viewModel: CaffeineViewModel

    @MainActor
    func perform() async throws -> some IntentResult {
        self.viewModel.deactivate()
        return .result()
    }
}

struct GetCaffeineStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Caffeine Revanced Is Active"
    static let description = IntentDescription(
        "Returns whether Caffeine Revanced is currently active."
    )

    @Dependency
    private var viewModel: CaffeineViewModel

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        .result(value: self.viewModel.isActive)
    }
}

struct CaffeineShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleCaffeineIntent(),
            phrases: ["Toggle \(.applicationName)"],
            shortTitle: "Toggle",
            systemImageName: "cup.and.saucer.fill"
        )
        AppShortcut(
            intent: ActivateCaffeineIntent(),
            phrases: ["Activate \(.applicationName)"],
            shortTitle: "Activate",
            systemImageName: "cup.and.saucer.fill"
        )
        AppShortcut(
            intent: DeactivateCaffeineIntent(),
            phrases: ["Deactivate \(.applicationName)"],
            shortTitle: "Deactivate",
            systemImageName: "cup.and.saucer"
        )
    }
}
