import Foundation

/// Something that briefly takes over the closed notch.
enum NotchActivity: Equatable {
    case volume(level: Float, muted: Bool)
    case brightness(level: Float)
    case charging(percent: Int)
    case lowBattery(percent: Int)
    case audioOutput(name: String, symbol: String)

    enum Kind {
        case volume, brightness, charging, lowBattery, audioOutput
    }

    /// Changing the value within a kind (e.g. volume going up) updates in
    /// place; changing kind cross-fades.
    var kind: Kind {
        switch self {
        case .volume: .volume
        case .brightness: .brightness
        case .charging: .charging
        case .lowBattery: .lowBattery
        case .audioOutput: .audioOutput
        }
    }
}

/// Shows one activity at a time; the newest replaces whatever is showing.
final class ActivityCenter: ObservableObject {
    @Published private(set) var current: NotchActivity?
    private var hideWork: DispatchWorkItem?

    func show(_ activity: NotchActivity, for duration: TimeInterval) {
        current = activity
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.current = nil }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
