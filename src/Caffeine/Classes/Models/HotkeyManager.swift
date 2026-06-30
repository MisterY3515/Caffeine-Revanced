//
//  HotkeyManager.swift
//  Caffeine
//
//  Registers ⌘⌥C as a system-wide hotkey using NSEvent global monitor.
//  Requires Accessibility permission — the system dialog is shown automatically.
//

import AppKit
import ApplicationServices
import DZFoundation

final class HotkeyManager {
    static let shared = HotkeyManager()

    var onToggle: (() -> Void)?

    private var monitor: Any?

    private init() {}

    deinit {
        self.unregister()
    }

    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityIfNeeded() {
        guard !self.isAccessibilityGranted else { return }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    func register() {
        guard self.monitor == nil else { return }

        self.requestAccessibilityIfNeeded()

        self.monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // ⌘⌥C: keyCode 8
            guard event.keyCode == 8 else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == [.command, .option] else { return }
            DispatchQueue.main.async { self?.onToggle?() }
        }

        DZLog("HotkeyManager: ⌘⌥C registered (accessibility=\(self.isAccessibilityGranted))")
    }

    func unregister() {
        if let monitor = self.monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            DZLog("HotkeyManager: unregistered")
        }
    }
}
