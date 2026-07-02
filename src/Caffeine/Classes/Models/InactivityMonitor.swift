//
//  InactivityMonitor.swift
//  Caffeine
//

import DZFoundation
import Foundation
import IOKit

/// Polls `HIDIdleTime` on `IOHIDSystem` every 60 s to detect user inactivity
/// (no keyboard or mouse input) and calls `onThresholdReached` once the
/// configured threshold is exceeded.
final class InactivityMonitor {
    static let shared = InactivityMonitor()

    var onThresholdReached: (() -> Void)?
    var thresholdMinutes = 10

    private var timer: Timer?

    private init() {}

    deinit {
        self.stop()
    }

    static func idleSeconds() -> TimeInterval {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != IO_OBJECT_NULL else { return 0 }
        defer { IOObjectRelease(service) }
        guard
            let raw = IORegistryEntryCreateCFProperty(
                service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0
            ) else { return 0 }
        let nanoseconds = (raw.takeRetainedValue() as? NSNumber)?.doubleValue ?? 0
        return nanoseconds / 1_000_000_000
    }

    func start() {
        guard self.timer == nil else { return }
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
        DZLog("InactivityMonitor started, threshold=\(self.thresholdMinutes)min")
    }

    func stop() {
        self.timer?.invalidate()
        self.timer = nil
        DZLog("InactivityMonitor stopped")
    }

    private func poll() {
        let idle = Self.idleSeconds()
        let threshold = TimeInterval(self.thresholdMinutes * 60)
        guard idle >= threshold else { return }
        DZLog("InactivityMonitor: idle=\(idle)s >= threshold=\(threshold)s")
        self.onThresholdReached?()
    }
}
