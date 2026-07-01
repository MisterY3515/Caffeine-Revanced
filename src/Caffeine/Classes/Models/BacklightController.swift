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
/// Display brightness tries DisplayServices.framework first (reliable on Apple Silicon),
/// then falls back to CoreDisplay.framework (Intel). Both paths use CGMainDisplayID()
/// directly so they work even when the built-in panel is not in CGGetActiveDisplayList
/// (i.e. while the lid is closed). Keyboard backlight uses IOHIDSystem parameters.
/// All paths fail silently.
enum BacklightController {
    struct State {
        let displays: [(CGDirectDisplayID, Double)]
        let keyboard: Double
    }

    // MARK: - Capture

    static func captureState() -> State {
        State(
            displays: Self.captureDisplayBrightnesses(),
            keyboard: Self.keyboardBrightness() ?? 1.0
        )
    }

    // MARK: - Dim

    static func dimDisplays() {
        for id in Self.allKnownDisplayIDs() {
            Self.setDisplayBrightness(0, for: id)
        }
        DZLog("BacklightController: dimmed displays")
    }

    static func dimKeyboard() {
        Self.setKeyboardBrightness(0)
        DZLog("BacklightController: dimmed keyboard")
    }

    // MARK: - Restore

    static func restoreDisplays(_ displays: [(CGDirectDisplayID, Double)]) {
        if displays.isEmpty {
            Self.setDisplayBrightness(0.5, for: CGMainDisplayID())
        } else {
            for (id, brightness) in displays {
                Self.setDisplayBrightness(brightness, for: id)
            }
        }
        DZLog("BacklightController: restored displays")
    }

    static func restoreKeyboard(_ brightness: Double) {
        Self.setKeyboardBrightness(brightness)
        DZLog("BacklightController: restored keyboard")
    }

    // MARK: - Display via DisplayServices (primary) + CoreDisplay (fallback)

    private typealias DSGetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias DSSetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CDGetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Double>) -> Int32
    private typealias CDSetFn = @convention(c) (CGDirectDisplayID, Double) -> Int32

    private static let displayServicesHandle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_NOW | RTLD_LOCAL
    )
    private static let coreDisplayHandle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
        RTLD_NOW | RTLD_LOCAL
    )

    /// Returns the main display ID plus any other currently active displays.
    /// Always includes CGMainDisplayID() so we can set brightness even when
    /// the built-in panel is in hardware sleep (not in the active list).
    private static func allKnownDisplayIDs() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &count)
        var result = Array(ids.prefix(Int(count)))
        let main = CGMainDisplayID()
        if !result.contains(main) { result.insert(main, at: 0) }
        return result
    }

    private static func captureDisplayBrightnesses() -> [(CGDirectDisplayID, Double)] {
        Self.allKnownDisplayIDs().compactMap { id in
            guard let b = Self.displayBrightness(for: id) else { return nil }
            return (id, b)
        }
    }

    private static func displayBrightness(for id: CGDirectDisplayID) -> Double? {
        if let handle = Self.displayServicesHandle,
            let sym = dlsym(handle, "DisplayServicesGetBrightness")
        {
            var v: Float = 0
            if unsafeBitCast(sym, to: DSGetFn.self)(id, &v) == 0 { return Double(v) }
        }
        if let handle = Self.coreDisplayHandle,
            let sym = dlsym(handle, "CoreDisplay_Display_GetUserBrightness")
        {
            var v = 0.0
            if unsafeBitCast(sym, to: CDGetFn.self)(id, &v) == 0 { return v }
        }
        return nil
    }

    private static func setDisplayBrightness(_ value: Double, for id: CGDirectDisplayID) {
        if let handle = Self.displayServicesHandle,
            let sym = dlsym(handle, "DisplayServicesSetBrightness")
        {
            let result = unsafeBitCast(sym, to: DSSetFn.self)(id, Float(value))
            DZLog("BacklightController: DS set \(id) brightness=\(value) result=\(result)")
            if result == 0 { return }
        }
        if let handle = Self.coreDisplayHandle,
            let sym = dlsym(handle, "CoreDisplay_Display_SetUserBrightness")
        {
            let result = unsafeBitCast(sym, to: CDSetFn.self)(id, value)
            DZLog("BacklightController: CD set \(id) brightness=\(value) result=\(result)")
        }
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
