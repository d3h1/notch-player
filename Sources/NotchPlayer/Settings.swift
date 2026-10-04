import Foundation

/// On/off switches from the right-click menu, kept in UserDefaults.
final class AppSettings: ObservableObject {
    @Published var showCalendar: Bool {
        didSet { defaults.set(showCalendar, forKey: Key.calendar) }
    }
    @Published var showWeather: Bool {
        didSet { defaults.set(showWeather, forKey: Key.weather) }
    }
    /// Show volume and brightness changes in the notch instead of the macOS pop-up.
    @Published var notchHUD: Bool {
        didSet { defaults.set(notchHUD, forKey: Key.hud) }
    }

    private let defaults: UserDefaults

    private enum Key {
        static let calendar = "showCalendar"
        static let weather = "showWeather"
        static let hud = "notchHUD"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.calendar: true, Key.weather: true, Key.hud: true])
        showCalendar = defaults.bool(forKey: Key.calendar)
        showWeather = defaults.bool(forKey: Key.weather)
        notchHUD = defaults.bool(forKey: Key.hud)
    }
}
