import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let player = NowPlayingService()
    private let settings = AppSettings()
    private let activities = ActivityCenter()
    private let battery = BatteryMonitor()
    private let calendar = CalendarService()
    private let reminders = RemindersService()
    private let weather = WeatherService()
    private let mediaKeys = MediaKeyTap()
    private let audioOutput = AudioOutputMonitor()
    private let notifications = NotificationWatcher()
    private var notch: NotchController?
    private var signalSources: [DispatchSourceSignal] = []
    private var cancellables = Set<AnyCancellable>()

    private static let askedForAccessibilityKey = "askedForAccessibility"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `pkill` / Ctrl-C skip applicationWillTerminate by default, which
        // would leave the adapter process running. Route them through it.
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }

        BackgroundCursor.enable()
        if CommandLine.arguments.contains("--enable-login-item") {
            LoginItem.setEnabled(true)
        }
        // `--pin-expanded` keeps the panel open, handy for working on the layout.
        let pinExpanded = CommandLine.arguments.contains("--pin-expanded")
        let services = NotchServices(player: player, activities: activities, battery: battery,
                                     calendar: calendar, reminders: reminders, weather: weather, mediaKeys: mediaKeys,
                                     notifications: notifications, settings: settings)
        let controller = NotchController(services: services, pinExpanded: pinExpanded)
        controller.show()
        notch = controller
        #if DEBUG
        if let flag = CommandLine.arguments.first(where: { $0.hasPrefix("--sample-data") }) {
            let variant = flag.split(separator: "=").dropFirst().first.map(String.init) ?? ""
            SampleData.load(into: services, variant: variant)
            if variant == "notification", let first = notifications.recent.first {
                activities.show(.notification(first), for: 600)
            }
            controller.showsNotifications = variant == "notifications"
            return
        }
        #endif
        player.start()
        startAlerts()
        startSettingsObservers()
        // `--demo-activities` plays every alert once, for working on their layout.
        if CommandLine.arguments.contains("--demo-activities") {
            playActivityDemo()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        player.stop()
    }

    private func startAlerts() {
        battery.onPluggedIn = { [activities] percent in
            activities.show(.charging(percent: percent), for: 3)
        }
        battery.onLowBattery = { [activities] percent in
            activities.show(.lowBattery(percent: percent), for: 4)
        }
        battery.start()

        mediaKeys.onVolume = { [activities] level, muted in
            activities.show(.volume(level: level, muted: muted), for: 1.5)
        }
        mediaKeys.onBrightness = { [activities] level in
            activities.show(.brightness(level: level), for: 1.5)
        }

        audioOutput.onChange = { [activities] name, symbol in
            activities.show(.audioOutput(name: name, symbol: symbol), for: 3)
        }
        audioOutput.start()

        notifications.onNew = { [activities] notification in
            activities.show(.notification(notification), for: 5)
        }
    }

    /// Starts each optional feature now if it's on, and again whenever it's
    /// switched on from the menu.
    private func startSettingsObservers() {
        settings.$showCalendar.removeDuplicates()
            .sink { [calendar] on in if on { calendar.start() } }
            .store(in: &cancellables)

        settings.$showReminders.removeDuplicates()
            .sink { [reminders] on in if on { reminders.start() } }
            .store(in: &cancellables)

        settings.$showWeather.removeDuplicates()
            .sink { [weather] on in on ? weather.start() : weather.stop() }
            .store(in: &cancellables)

        settings.$showNotifications.removeDuplicates()
            .sink { [notifications] on in on ? notifications.start() : notifications.stop() }
            .store(in: &cancellables)
        settings.$hideSystemBanners
            .sink { [notifications] on in notifications.closesBanners = on }
            .store(in: &cancellables)

        // Show the Accessibility prompt once on launch; after that only when
        // switched on from the menu.
        if settings.notchHUD {
            let defaults = UserDefaults.standard
            mediaKeys.start(askIfNeeded: !defaults.bool(forKey: Self.askedForAccessibilityKey))
            defaults.set(true, forKey: Self.askedForAccessibilityKey)
        }
        settings.$notchHUD.dropFirst().removeDuplicates()
            .sink { [mediaKeys] on in on ? mediaKeys.start(askIfNeeded: true) : mediaKeys.stop() }
            .store(in: &cancellables)
    }

    private func playActivityDemo() {
        let demo: [NotchActivity] = [
            .volume(level: 0.625, muted: false),
            .brightness(level: 0.8),
            .charging(percent: 76),
            .lowBattery(percent: 10),
            .audioOutput(name: "AirPods Pro", symbol: "airpodspro"),
        ]
        for (index, activity) in demo.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(index) * 2.5) { [activities] in
                activities.show(activity, for: 2)
            }
        }
    }
}
