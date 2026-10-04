import AppKit

/// Built-in display brightness through the private DisplayServices framework
/// (what the brightness keys use). If it's unavailable the keys are left to
/// macOS.
enum DisplayBrightness {
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let api: (get: Get, set: Set)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness") else {
            NSLog("NotchPlayer: DisplayServices brightness API unavailable")
            return nil
        }
        return (unsafeBitCast(get, to: Get.self), unsafeBitCast(set, to: Set.self))
    }()

    /// The built-in display, if the pointer is on it. On an external display
    /// the keys go to macOS, which knows how to handle that display.
    static var builtInDisplayUnderPointer: CGDirectDisplayID? {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              CGDisplayIsBuiltin(number.uint32Value) != 0 else { return nil }
        return number.uint32Value
    }

    static func brightness(_ display: CGDirectDisplayID) -> Float? {
        guard let api else { return nil }
        var value: Float = 0
        return api.get(display, &value) == 0 ? value : nil
    }

    @discardableResult
    static func setBrightness(_ value: Float, _ display: CGDirectDisplayID) -> Bool {
        api?.set(display, min(max(value, 0), 1)) == 0
    }
}
