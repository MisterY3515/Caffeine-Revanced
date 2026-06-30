//
//  ProcessMonitor.swift
//  Caffeine
//

import Darwin
import DZFoundation
import Foundation

final class ProcessMonitor {
    static let shared = ProcessMonitor()

    private(set) var watchedProcessNames = Set<String>()
    private var activeProcesses = Set<String>()
    private var pollTimer: Timer?
    private(set) var isRunning = false

    var onProcessAppeared: ((String) -> Void)?
    var onProcessDisappeared: ((String) -> Void)?

    private init() {}

    deinit {
        self.stop()
    }

    func watch(processName: String) {
        self.watchedProcessNames.insert(processName)
        if self.isRunning {
            self.poll()
        }
    }

    func unwatch(processName: String) {
        self.watchedProcessNames.remove(processName)
        self.activeProcesses.remove(processName)
    }

    func start() {
        guard !self.isRunning else { return }
        self.isRunning = true
        self.pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        self.poll()
        DZLog("ProcessMonitor started, watching: \(self.watchedProcessNames)")
    }

    func stop() {
        self.pollTimer?.invalidate()
        self.pollTimer = nil
        self.isRunning = false
        DZLog("ProcessMonitor stopped")
    }

    private func poll() {
        let running = Self.runningProcessNames()

        for name in self.watchedProcessNames {
            let isRunning = running.contains(name)
            let wasRunning = self.activeProcesses.contains(name)

            if isRunning, !wasRunning {
                self.activeProcesses.insert(name)
                DZLog("Process appeared: \(name)")
                DispatchQueue.main.async { self.onProcessAppeared?(name) }
            } else if !isRunning, wasRunning {
                self.activeProcesses.remove(name)
                DZLog("Process disappeared: \(name)")
                DispatchQueue.main.async { self.onProcessDisappeared?(name) }
            }
        }
    }

    private static func runningProcessNames() -> Set<String> {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        sysctl(&mib, 4, nil, &size, nil, 0)

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        sysctl(&mib, 4, &procs, &size, nil, 0)

        return Set(procs.compactMap { proc -> String? in
            var p = proc
            return withUnsafeBytes(of: &p.kp_proc.p_comm) { buf in
                let bytes = buf.prefix(while: { $0 != 0 })
                return String(bytes: bytes, encoding: .utf8)
            }
        })
    }
}
