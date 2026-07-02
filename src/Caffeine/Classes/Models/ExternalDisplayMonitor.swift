//
//  ExternalDisplayMonitor.swift
//  Caffeine
//

import AppKit
import CoreGraphics
import DZFoundation
import Foundation

final class ExternalDisplayMonitor {
    static let shared = ExternalDisplayMonitor()

    var onExternalDisplayConnected: (() -> Void)?
    var onExternalDisplayDisconnected: (() -> Void)?

    private var monitoring = false
    private var hasExternal = false

    private init() {}

    deinit {
        self.stop()
    }

    static func hasExternalDisplay() -> Bool {
        NSScreen.screens.contains { screen in
            guard
                let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(id) == 0
        }
    }

    func start() {
        guard !self.monitoring else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        self.monitoring = true
        self.hasExternal = ExternalDisplayMonitor.hasExternalDisplay()
        DZLog("ExternalDisplayMonitor started, hasExternal=\(self.hasExternal)")
    }

    func stop() {
        guard self.monitoring else { return }
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        self.monitoring = false
        DZLog("ExternalDisplayMonitor stopped")
    }

    @objc
    private func screensChanged() {
        let current = ExternalDisplayMonitor.hasExternalDisplay()
        guard current != self.hasExternal else { return }
        self.hasExternal = current
        DZLog("ExternalDisplayMonitor: hasExternal=\(current)")
        if current {
            self.onExternalDisplayConnected?()
        } else {
            self.onExternalDisplayDisconnected?()
        }
    }
}
