//
//  CPUMonitor.swift
//  Caffeine
//

import Darwin
import DZFoundation
import Foundation

/// Polls per-core CPU tick counts via `host_processor_info` every 30 s and reports
/// sustained high load. Uses hysteresis (2 consecutive high readings to trigger,
/// 3 consecutive normal readings to clear) to avoid flapping on brief spikes.
final class CPUMonitor {
    static let shared = CPUMonitor()

    var onHighLoad: (() -> Void)?
    var onLoadNormalized: (() -> Void)?
    var thresholdPercent = 80

    private var timer: Timer?
    private var previousTicks: [processor_cpu_load_info] = []
    private var aboveCount = 0
    private var belowCount = 0
    private var isHigh = false

    private init() {}

    deinit {
        self.stop()
    }

    /// Asynchronous because instantaneous usage requires two samples over a short
    /// interval; used for the initial check when the preference is enabled.
    static func currentUsage(completion: @escaping (Double) -> Void) {
        guard let first = sampleTicks() else {
            completion(0)
            return
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) {
            guard let second = Self.sampleTicks() else {
                DispatchQueue.main.async { completion(0) }
                return
            }
            let usage = Self.usageDelta(from: first, to: second)
            DispatchQueue.main.async { completion(usage) }
        }
    }

    func start() {
        guard self.timer == nil else { return }
        self.previousTicks = Self.sampleTicks() ?? []
        self.aboveCount = 0
        self.belowCount = 0
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
        DZLog("CPUMonitor started, threshold=\(self.thresholdPercent)%")
    }

    func stop() {
        self.timer?.invalidate()
        self.timer = nil
        self.previousTicks = []
        self.aboveCount = 0
        self.belowCount = 0
        self.isHigh = false
        DZLog("CPUMonitor stopped")
    }

    // MARK: - Private

    private static func sampleTicks() -> [processor_cpu_load_info]? {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &infoArray, &infoCount
        )
        guard result == KERN_SUCCESS, let infoArray else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: Int(bitPattern: infoArray)),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.size)
            )
        }
        return infoArray.withMemoryRebound(to: processor_cpu_load_info.self, capacity: Int(cpuCount)) {
            Array(UnsafeBufferPointer(start: $0, count: Int(cpuCount)))
        }
    }

    private static func usageDelta(
        from: [processor_cpu_load_info], to: [processor_cpu_load_info]
    )
        -> Double
    {
        guard from.count == to.count, !from.isEmpty else { return 0 }
        var busy: UInt64 = 0
        var total: UInt64 = 0
        for i in 0..<from.count {
            let user = UInt64(to[i].cpu_ticks.0 &- from[i].cpu_ticks.0)
            let system = UInt64(to[i].cpu_ticks.1 &- from[i].cpu_ticks.1)
            let idle = UInt64(to[i].cpu_ticks.2 &- from[i].cpu_ticks.2)
            let nice = UInt64(to[i].cpu_ticks.3 &- from[i].cpu_ticks.3)
            busy += user + system + nice
            total += user + system + idle + nice
        }
        guard total > 0 else { return 0 }
        return Double(busy) / Double(total) * 100
    }

    private func poll() {
        guard let current = Self.sampleTicks() else { return }
        defer { self.previousTicks = current }
        guard !self.previousTicks.isEmpty else { return }

        let usage = Self.usageDelta(from: self.previousTicks, to: current)
        DZLog("CPUMonitor: usage=\(usage)%")

        if usage >= Double(self.thresholdPercent) {
            self.aboveCount += 1
            self.belowCount = 0
        } else {
            self.belowCount += 1
            self.aboveCount = 0
        }

        if !self.isHigh, self.aboveCount >= 2 {
            self.isHigh = true
            self.onHighLoad?()
        } else if self.isHigh, self.belowCount >= 3 {
            self.isHigh = false
            self.onLoadNormalized?()
        }
    }
}
