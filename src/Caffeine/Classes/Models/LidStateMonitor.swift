//
//  LidStateMonitor.swift
//  Caffeine
//

import DZFoundation
import Foundation
import IOKit

/// Polls IOKit `AppleClamshellState` every 250 ms to detect lid open/close transitions.
/// Only works while the Mac is awake (lid-close sleep prevention must be active).
/// Callbacks fire on the main queue.
final class LidStateMonitor {
    static let shared = LidStateMonitor()

    var onLidClosed: (() -> Void)?
    var onLidOpened: (() -> Void)?

    private var timer: Timer?
    private var lastState: Bool?

    private init() {}

    func start() {
        guard self.timer == nil else { return }
        let current = Self.isClosed()
        self.lastState = current
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
        DZLog("LidStateMonitor started (lid closed=\(current))")
    }

    func stop() {
        self.timer?.invalidate()
        self.timer = nil
        self.lastState = nil
        DZLog("LidStateMonitor stopped")
    }

    static func isClosed() -> Bool {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }
        guard let raw = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        ) else { return false }
        return (raw.takeRetainedValue() as? Bool) ?? false
    }

    private func poll() {
        let closed = Self.isClosed()
        guard closed != self.lastState else { return }
        self.lastState = closed
        if closed {
            DZLog("LidStateMonitor: lid closed")
            self.onLidClosed?()
        } else {
            DZLog("LidStateMonitor: lid opened")
            self.onLidOpened?()
        }
    }
}
