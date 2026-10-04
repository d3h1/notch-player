import AudioToolbox
import CoreAudio
import Foundation

/// Volume and mute of the default output device, through CoreAudio.
enum SystemAudio {
    static var outputDevice: AudioDeviceID? {
        read(AudioObjectID(kAudioObjectSystemObject),
             address(kAudioHardwarePropertyDefaultOutputDevice), AudioDeviceID(0))
            .flatMap { $0 == kAudioObjectUnknown ? nil : $0 }
    }

    // The "virtual main" volume covers devices that only expose per-channel
    // volumes, and is what the system volume slider uses.
    private static let volumeAddress = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                               kAudioDevicePropertyScopeOutput)
    private static let muteAddress = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)

    static func canSetVolume(_ device: AudioDeviceID) -> Bool { isSettable(device, volumeAddress) }
    static func canMute(_ device: AudioDeviceID) -> Bool { isSettable(device, muteAddress) }

    static func volume(_ device: AudioDeviceID) -> Float? {
        read(device, volumeAddress, Float32(0))
    }

    @discardableResult
    static func setVolume(_ volume: Float, _ device: AudioDeviceID) -> Bool {
        write(device, volumeAddress, Float32(min(max(volume, 0), 1)))
    }

    static func isMuted(_ device: AudioDeviceID) -> Bool {
        (read(device, muteAddress, UInt32(0)) ?? 0) != 0
    }

    @discardableResult
    static func setMuted(_ muted: Bool, _ device: AudioDeviceID) -> Bool {
        write(device, muteAddress, UInt32(muted ? 1 : 0))
    }

    static func name(_ device: AudioDeviceID) -> String? {
        var address = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    static func transportType(_ device: AudioDeviceID) -> UInt32 {
        read(device, address(kAudioDevicePropertyTransportType), UInt32(0)) ?? 0
    }

    // MARK: - Property access

    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func read<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ initial: T) -> T? {
        var address = address
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectHasProperty(object, &address),
              AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func write<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) -> Bool {
        var address = address
        var value = value
        return AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value) == noErr
    }

    private static func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(object, &address)
            && AudioObjectIsPropertySettable(object, &address, &settable) == noErr
            && settable.boolValue
    }
}

/// Reports when sound switches to another output, e.g. AirPods connecting.
final class AudioOutputMonitor {
    var onChange: ((_ name: String, _ symbol: String) -> Void)?

    private var current: AudioDeviceID?
    private var pending: DispatchWorkItem?
    private var listener: AudioObjectPropertyListenerBlock?

    func start() {
        guard listener == nil else { return }
        current = SystemAudio.outputDevice
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.outputChanged() }
        var address = SystemAudio.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        self.listener = listener
    }

    /// Connecting a device can switch the output several times in a row;
    /// only announce where it settles.
    private func outputChanged() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let device = SystemAudio.outputDevice, device != current else { return }
            current = device
            let (name, symbol) = Self.describe(device)
            onChange?(name, symbol)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    static func describe(_ device: AudioDeviceID) -> (name: String, symbol: String) {
        var name = SystemAudio.name(device) ?? "Speakers"
        // "Sam's AirPods Pro" -> "AirPods Pro"
        if let owner = name.range(of: "’s ") ?? name.range(of: "'s ") {
            name = String(name[owner.upperBound...])
        }
        let transport = SystemAudio.transportType(device)
        if transport == kAudioDeviceTransportTypeBuiltIn, name.hasSuffix("Speakers") {
            name = "Speakers"
        }

        let lower = name.lowercased()
        let symbol: String
        if lower.contains("airpods max") {
            symbol = "airpodsmax"
        } else if lower.contains("airpods pro") {
            symbol = "airpodspro"
        } else if lower.contains("airpods") {
            symbol = "airpods"
        } else if lower.contains("beats") {
            symbol = "beats.headphones"
        } else {
            switch transport {
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: symbol = "headphones"
            case kAudioDeviceTransportTypeBuiltIn: symbol = "laptopcomputer"
            case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: symbol = "tv"
            case kAudioDeviceTransportTypeAirPlay: symbol = "airplayaudio"
            default: symbol = "hifispeaker.fill"
            }
        }
        return (name, symbol)
    }
}
