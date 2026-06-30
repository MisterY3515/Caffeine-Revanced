//
//  BatteryMonitor.swift
//  Caffeine
//

import DZFoundation
import Foundation
import IOKit.ps

final class BatteryMonitor {
    static let shared = BatteryMonitor()

    var onStateChanged: ((Int, Bool) -> Void)?

    private var runLoopSource: CFRunLoopSource?

    private init() {}

    deinit {
        self.stop()
    }

    func start() {
        guard self.runLoopSource == nil else { return }

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource(
            { ptr in
                guard let ptr else { return }
                Unmanaged<BatteryMonitor>.fromOpaque(ptr).takeUnretainedValue().notify()
            },
            ctx
        )?.takeRetainedValue() else {
            DZLog("BatteryMonitor: failed to create run loop source")
            return
        }

        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        DZLog("BatteryMonitor started")
        self.notify()
    }

    func stop() {
        guard let source = self.runLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        self.runLoopSource = nil
        DZLog("BatteryMonitor stopped")
    }

    static func currentState() -> (level: Int, isOnBattery: Bool) {
        guard let infoUnmanaged = IOPSCopyPowerSourcesInfo() else { return (100, false) }
        let info = infoUnmanaged.takeRetainedValue()

        guard
            let sourcesUnmanaged = IOPSCopyPowerSourcesList(info),
            let sources = sourcesUnmanaged.takeRetainedValue() as? [CFTypeRef],
            let source = sources.first,
            let descUnmanaged = IOPSGetPowerSourceDescription(info, source),
            let desc = descUnmanaged.takeUnretainedValue() as? [String: Any]
        else {
            return (100, false)
        }

        let isOnBattery = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
        let capacity = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
        let maxCapacity = desc[kIOPSMaxCapacityKey] as? Int ?? 100
        let level = maxCapacity > 0 ? (capacity * 100) / maxCapacity : 100
        return (level, isOnBattery)
    }

    private func notify() {
        let (level, isOnBattery) = Self.currentState()
        DZLog("Battery: \(level)% onBattery=\(isOnBattery)")
        DispatchQueue.main.async { [weak self] in
            self?.onStateChanged?(level, isOnBattery)
        }
    }
}
