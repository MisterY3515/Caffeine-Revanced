//
//  NetworkMonitor.swift
//  Caffeine
//

import CoreWLAN
import DZFoundation
import Foundation

final class NetworkMonitor: NSObject {
    static let shared = NetworkMonitor()

    var onSSIDChanged: ((String?) -> Void)?

    private var wifiClient: CWWiFiClient?
    private var monitoring = false

    private override init() {
        super.init()
    }

    deinit {
        self.stop()
    }

    var currentSSID: String? {
        CWWiFiClient.shared().interface()?.ssid()
    }

    func start() {
        guard !self.monitoring else { return }
        self.wifiClient = CWWiFiClient.shared()
        self.wifiClient?.delegate = self
        do {
            try self.wifiClient?.startMonitoringEvent(with: .ssidDidChange)
            self.monitoring = true
            DZLog("NetworkMonitor started, current SSID: \(self.currentSSID ?? "none")")
        } catch {
            DZErrorLog(error)
        }
    }

    func stop() {
        guard self.monitoring else { return }
        try? self.wifiClient?.stopMonitoringAllEvents()
        self.wifiClient?.delegate = nil
        self.monitoring = false
        DZLog("NetworkMonitor stopped")
    }
}

extension NetworkMonitor: CWEventDelegate {
    func ssidDidChangeForWiFiInterface(withName _: String) {
        let ssid = self.currentSSID
        DZLog("SSID changed: \(ssid ?? "none")")
        DispatchQueue.main.async { self.onSSIDChanged?(ssid) }
    }
}
