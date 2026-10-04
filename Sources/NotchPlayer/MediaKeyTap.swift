import AppKit
import ApplicationServices

/// Catches the volume and brightness keys, applies the change itself and
/// reports it so the notch can show it instead of the macOS pop-up.
///
/// Needs Accessibility access. Without it, or for anything it can't handle
/// (e.g. an HDMI output with fixed volume), keys pass through to macOS.
final class MediaKeyTap: ObservableObject {
    @Published private(set) var hasAccess = AXIsProcessTrusted()

    var onVolume: ((_ level: Float, _ muted: Bool) -> Void)?
    var onBrightness: ((Float) -> Void)?

    private enum Key: Int {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var accessObserver: NSObjectProtocol?
    /// Keys whose key-down we handled; their key-up is swallowed too.
    private var heldKeys = Set<Key>()
    private lazy var feedbackSound = NSSound(
        contentsOfFile: "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff",
        byReference: true)

    /// Starts right away if allowed. Otherwise optionally shows the system
    /// prompt, and starts as soon as access is granted.
    func start(askIfNeeded: Bool) {
        if accessObserver == nil {
            // Posted whenever the Accessibility list in System Settings changes.
            accessObserver = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
            ) { [weak self] _ in
                // The new state takes a moment to apply.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.accessChanged() }
            }
        }
        if AXIsProcessTrusted() {
            install()
        } else if askIfNeeded {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    func stop() {
        if let accessObserver {
            DistributedNotificationCenter.default().removeObserver(accessObserver)
        }
        accessObserver = nil
        uninstall()
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func accessChanged() {
        hasAccess = AXIsProcessTrusted()
        if hasAccess {
            install()
        } else {
            uninstall()
        }
    }

    // MARK: - Event tap

    private func install() {
        hasAccess = true
        guard tap == nil else { return }
        let systemDefined = CGEventMask(1 << NSEvent.EventType.systemDefined.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: systemDefined,
                                          callback: mediaKeyCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            NSLog("NotchPlayer: could not create media key event tap")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    private func uninstall() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        heldKeys.removeAll()
    }

    /// Returns nil to swallow the event.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return passThrough
        }
        guard type.rawValue == UInt32(NSEvent.EventType.systemDefined.rawValue),
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8, // NX_SUBTYPE_AUX_CONTROL_BUTTONS
              let key = Key(rawValue: (nsEvent.data1 & 0xFFFF_0000) >> 16) else { return passThrough }

        let isKeyDown = (nsEvent.data1 & 0xFF00) >> 8 == 0xA
        guard isKeyDown else {
            return heldKeys.remove(key) != nil ? nil : passThrough
        }

        // Option alone opens Sound or Displays settings; leave that to macOS.
        // Option-Shift adjusts in quarter steps, like macOS.
        let flags = nsEvent.modifierFlags
        if flags.contains(.option) && !flags.contains(.shift) { return passThrough }
        let steps: Float = flags.contains(.option) && flags.contains(.shift) ? 64 : 16

        guard press(key, steps: steps) else { return passThrough }
        heldKeys.insert(key)
        return nil
    }

    /// Applies a key press. Returns false if macOS should handle it instead.
    private func press(_ key: Key, steps: Float) -> Bool {
        switch key {
        case .soundUp, .soundDown:
            guard let device = SystemAudio.outputDevice, SystemAudio.canSetVolume(device),
                  let current = SystemAudio.volume(device) else { return false }
            var muted = SystemAudio.isMuted(device)
            let step: Float = key == .soundUp ? 1 : -1
            let level = min(max((current * steps).rounded() + step, 0), steps) / steps
            if key == .soundUp && muted {
                SystemAudio.setMuted(false, device)
                muted = false
            }
            SystemAudio.setVolume(level, device)
            playFeedback()
            onVolume?(level, muted || level == 0)

        case .mute:
            guard let device = SystemAudio.outputDevice, SystemAudio.canMute(device) else { return false }
            let muted = !SystemAudio.isMuted(device)
            SystemAudio.setMuted(muted, device)
            onVolume?(SystemAudio.volume(device) ?? 0, muted)

        case .brightnessUp, .brightnessDown:
            guard let display = DisplayBrightness.builtInDisplayUnderPointer,
                  let current = DisplayBrightness.brightness(display) else { return false }
            let step: Float = key == .brightnessUp ? 1 : -1
            let level = min(max((current * steps).rounded() + step, 0), steps) / steps
            guard DisplayBrightness.setBrightness(level, display) else { return false }
            onBrightness?(level)
        }
        return true
    }

    /// The "pop" macOS plays when "Play feedback when volume is changed" is on.
    private func playFeedback() {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        guard global?["com.apple.sound.beep.feedback"] as? Int == 1, let sound = feedbackSound else { return }
        sound.stop()
        sound.play()
    }
}

private let mediaKeyCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<MediaKeyTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
}
