import Foundation

/// On/off switches from the right-click menu, kept in UserDefaults.
final class AppSettings: ObservableObject {
    @Published var showCalendar: Bool {
        didSet { defaults.set(showCalendar, forKey: Key.calendar) }
    }
    @Published var showReminders: Bool {
        didSet { defaults.set(showReminders, forKey: Key.reminders) }
    }
    @Published var showWeather: Bool {
        didSet { defaults.set(showWeather, forKey: Key.weather) }
    }
    @Published var showNotifications: Bool {
        didSet { defaults.set(showNotifications, forKey: Key.notifications) }
    }
    /// Close the macOS pop-up once the notch has shown it.
    @Published var hideSystemBanners: Bool {
        didSet { defaults.set(hideSystemBanners, forKey: Key.hideBanners) }
    }
    /// Include message text, not just who it's from.
    @Published var notificationPreviews: Bool {
        didSet { defaults.set(notificationPreviews, forKey: Key.previews) }
    }
    /// Show volume and brightness changes in the notch instead of the macOS pop-up.
    @Published var notchHUD: Bool {
        didSet { defaults.set(notchHUD, forKey: Key.hud) }
    }

    private let defaults: UserDefaults

    private enum Key {
        static let calendar = "showCalendar"
        static let reminders = "showReminders"
        static let weather = "showWeather"
        static let hud = "notchHUD"
        static let notifications = "showNotifications"
        static let previews = "notificationPreviews"
        static let hideBanners = "hideSystemBanners"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.calendar: true, Key.reminders: true, Key.weather: true, Key.hud: true,
                                     Key.notifications: true, Key.previews: true, Key.hideBanners: true])
        showCalendar = defaults.bool(forKey: Key.calendar)
        showReminders = defaults.bool(forKey: Key.reminders)
        showWeather = defaults.bool(forKey: Key.weather)
        notchHUD = defaults.bool(forKey: Key.hud)
        showNotifications = defaults.bool(forKey: Key.notifications)
        notificationPreviews = defaults.bool(forKey: Key.previews)
        hideSystemBanners = defaults.bool(forKey: Key.hideBanners)
    }
}
