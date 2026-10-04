import Foundation
import IOKit.ps

/// Battery level and power adapter state, updated by IOKit as they change.
final class BatteryMonitor: ObservableObject {
    @Published private(set) var hasBattery = false
    @Published private(set) var percent = 0
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false

    var onPluggedIn: ((Int) -> Void)?
    var onLowBattery: ((Int) -> Void)?

    private static let lowThresholds = [10, 20]
    private var source: CFRunLoopSource?

    func start() {
        guard source == nil else { return }
        read(notify: false)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue().read(notify: true)
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        self.source = source
    }

    private func read(notify: Bool) {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        let battery = sources.lazy
            .compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
            .first { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }
        guard let battery else {
            if hasBattery { hasBattery = false }
            return
        }

        let current = battery[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = battery[kIOPSMaxCapacityKey] as? Int ?? 100
        let newPercent = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
        let pluggedIn = battery[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        let charging = battery[kIOPSIsChargingKey] as? Bool ?? false

        if notify && hasBattery {
            if pluggedIn && !isPluggedIn {
                onPluggedIn?(newPercent)
            } else if !pluggedIn,
                      Self.lowThresholds.contains(where: { newPercent <= $0 && percent > $0 }) {
                onLowBattery?(newPercent)
            }
        }

        if !hasBattery { hasBattery = true }
        if percent != newPercent { percent = newPercent }
        if isPluggedIn != pluggedIn { isPluggedIn = pluggedIn }
        if isCharging != charging { isCharging = charging }
    }
}

#if DEBUG
extension BatteryMonitor {
    func loadSample(percent: Int, pluggedIn: Bool) {
        hasBattery = true
        self.percent = percent
        isPluggedIn = pluggedIn
        isCharging = pluggedIn && percent < 100
    }
}
#endif
