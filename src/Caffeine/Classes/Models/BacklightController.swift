//
//  BacklightController.swift
//  Caffeine
//

import CoreGraphics
import DZFoundation
import Foundation
import IOKit.hidsystem

/// Controls display brightness and keyboard backlight.
///
/// Display brightness uses `CoreDisplay.framework` private API (reliable on macOS 13.5+).
/// Keyboard backlight uses `IOHIDSystem` parameters. Both degrade gracefully — a failure
/// in either path leaves the other path unaffected.
enum BacklightController {
    struct State {
        let displays: [(CGDirectDisplayID, Double)]
        let keyboard: Double
    }

    // MARK: - Capture / Dim / Restore

    static func captureState() -> State {
        State(
            displays: Self.captureDisplayBrightnesses(),
            keyboard: Self.keyboardBrightness() ?? 1.0
        )
    }

    static func dimAll() {
        Self.setAllDisplayBrightness(0)
        Self.setKeyboardBrightness(0)
        DZLog("BacklightController: dimmed displays and keyboard")
    }

    static func restore(_ state: State) {
        for (id, brightness) in state.displays {
            Self.setDisplayBrightness(brightness, for: id)
        }
        Self.setKeyboardBrightness(state.keyboard)
        DZLog("BacklightController: restored displays and keyboard")
    }

    // MARK: - Display via CoreDisplay private API

    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Double>) -> Int32
    private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Double) -> Int32

    private static let coreDisplayHandle: UnsafeMutableRawPointer? =
        dlopen(
            "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
            RTLD_NOW | RTLD_LOCAL
        )

    private static func captureDisplayBrightnesses() -> [(CGDirectDisplayID, Double)] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &count)
        return (0 ..< Int(count)).compactMap { i in
            guard let b = Self.displayBrightness(for: ids[i]) else { return nil }
            return (ids[i], b)
        }
    }

    private static func setAllDisplayBrightness(_ value: Double) {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &count)
        for i in 0 ..< Int(count) {
            Self.setDisplayBrightness(value, for: ids[i])
        }
    }

    private static func displayBrightness(for id: CGDirectDisplayID) -> Double? {
        guard let handle = Self.coreDisplayHandle,
            let sym = dlsym(handle, "CoreDisplay_Display_GetUserBrightness")
        else { return nil }
        var brightness = 0.0
        guard unsafeBitCast(sym, to: GetBrightnessFn.self)(id, &brightness) == 0 else { return nil }
        return brightness
    }

    private static func setDisplayBrightness(_ value: Double, for id: CGDirectDisplayID) {
        guard let handle = Self.coreDisplayHandle,
            let sym = dlsym(handle, "CoreDisplay_Display_SetUserBrightness")
        else { return }
        _ = unsafeBitCast(sym, to: SetBrightnessFn.self)(id, value)
    }

    // MARK: - Keyboard via IOHIDSystem

    private static let kKeyboardIlluminationLevel = "HIDKeyboardIlluminationValue" as CFString

    private static func openHIDConnection() -> io_connect_t? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        guard
            IOServiceOpen(
                service,
                mach_task_self_,
                UInt32(kIOHIDParamConnectType),
                &connect
            ) == KERN_SUCCESS
        else { return nil }
        return connect
    }

    private static func keyboardBrightness() -> Double? {
        guard let connect = Self.openHIDConnection() else { return nil }
        defer { IOServiceClose(connect) }
        var value: Float = 0
        var dataSize = IOByteCount(MemoryLayout<Float>.size)
        guard
            IOHIDGetParameter(
                connect,
                Self.kKeyboardIlluminationLevel,
                IOByteCount(MemoryLayout<Float>.size),
                &value,
                &dataSize
            ) == KERN_SUCCESS
        else { return nil }
        return Double(value)
    }

    private static func setKeyboardBrightness(_ value: Double) {
        guard let connect = Self.openHIDConnection() else { return }
        defer { IOServiceClose(connect) }
        var v = Float(value)
        IOHIDSetParameter(
            connect,
            Self.kKeyboardIlluminationLevel,
            &v,
            IOByteCount(MemoryLayout<Float>.size)
        )
    }
}
