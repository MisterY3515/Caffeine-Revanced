//
//  AudioMonitor.swift
//  Caffeine
//

import CoreAudio
import DZFoundation
import Foundation

final class AudioMonitor {
    static let shared = AudioMonitor()

    var onAudioStarted: (() -> Void)?
    var onAudioStopped: (() -> Void)?

    private var monitoring = false
    private var lastPlaying = false
    private var observedDeviceID = AudioDeviceID(kAudioObjectUnknown)
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var runningStateListenerBlock: AudioObjectPropertyListenerBlock?

    private init() {}

    deinit {
        self.stop()
    }

    static func isAudioPlaying() -> Bool {
        let deviceID = Self.defaultOutputDevice()
        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else { return false }
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = Self.runningSomewhereAddress
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &isRunning)
        return status == noErr && isRunning != 0
    }

    func start() {
        guard !self.monitoring else { return }
        self.monitoring = true
        self.lastPlaying = AudioMonitor.isAudioPlaying()
        self.subscribeToDefaultDeviceChanges()
        self.subscribeToRunningState(deviceID: AudioMonitor.defaultOutputDevice())
        DZLog("AudioMonitor started, playing=\(self.lastPlaying)")
    }

    func stop() {
        guard self.monitoring else { return }
        self.unsubscribeFromDefaultDeviceChanges()
        self.unsubscribeFromRunningState()
        self.monitoring = false
        DZLog("AudioMonitor stopped")
    }

    // MARK: - Private

    private static var defaultOutputDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var runningSomewhereAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func defaultOutputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = Self.defaultOutputDeviceAddress
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : AudioDeviceID(kAudioObjectUnknown)
    }

    private func subscribeToDefaultDeviceChanges() {
        var address = Self.defaultOutputDeviceAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.unsubscribeFromRunningState()
            self.subscribeToRunningState(deviceID: AudioMonitor.defaultOutputDevice())
            self.checkState()
        }
        self.defaultDeviceListenerBlock = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block
        )
    }

    private func unsubscribeFromDefaultDeviceChanges() {
        guard let block = self.defaultDeviceListenerBlock else { return }
        var address = Self.defaultOutputDeviceAddress
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block
        )
        self.defaultDeviceListenerBlock = nil
    }

    private func subscribeToRunningState(deviceID: AudioDeviceID) {
        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else { return }
        self.observedDeviceID = deviceID
        var address = Self.runningSomewhereAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.checkState()
        }
        self.runningStateListenerBlock = block
        AudioObjectAddPropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
    }

    private func unsubscribeFromRunningState() {
        guard
            let block = self.runningStateListenerBlock,
            self.observedDeviceID != AudioDeviceID(kAudioObjectUnknown) else { return }
        var address = Self.runningSomewhereAddress
        AudioObjectRemovePropertyListenerBlock(self.observedDeviceID, &address, DispatchQueue.main, block)
        self.runningStateListenerBlock = nil
        self.observedDeviceID = AudioDeviceID(kAudioObjectUnknown)
    }

    private func checkState() {
        let playing = AudioMonitor.isAudioPlaying()
        guard playing != self.lastPlaying else { return }
        self.lastPlaying = playing
        DZLog("AudioMonitor: playing=\(playing)")
        if playing {
            self.onAudioStarted?()
        } else {
            self.onAudioStopped?()
        }
    }
}
