#if DEBUG
import AppKit

/// Fake content for `--sample-data[=variant]` (debug builds only): lets the
/// layout be worked on without real media, permissions or network.
/// `empty`: no events. `long`: a title too long to fit. `notification`: a
/// notification dropping down. `notifications`: the open notifications list.
enum SampleData {
    static func load(into services: NotchServices, variant: String) {
        let empty = variant == "empty"
        let title = variant == "long" ? "Watch the World Burn (Live at the Royal Albert Hall)" : "Big Brother"
        services.player.loadSample(title: title, artist: "Dyne Side",
                                   artwork: artwork(), bundleID: "com.spotify.client",
                                   duration: 261, elapsed: 167)
        services.weather.loadSample(.init(temperature: 37.8, high: 38.3, low: 22.8, code: 0, isDay: true))
        services.battery.loadSample(percent: 100, pluggedIn: true)
        services.notifications.loadSample(notifications(), unread: 2)

        let day = Calendar.current.startOfDay(for: Date())
        func event(_ title: String, hour: Double, color: NSColor) -> CalendarService.Event {
            let start = day.addingTimeInterval(hour * 3600)
            return .init(id: title, title: title, start: start, end: start.addingTimeInterval(1800),
                         isAllDay: false, color: color)
        }
        func reminder(_ title: String, dayOffset: Int?, hour: Double?, color: NSColor) -> RemindersService.Reminder {
            let due = dayOffset.map { day.addingTimeInterval(Double($0) * 86400 + (hour ?? 0) * 3600) }
            return .init(id: title, title: title, due: due, hasTime: hour != nil, color: color)
        }
        services.reminders.loadSample(empty ? [] : [
            reminder("Pay rent", dayOffset: -1, hour: nil, color: .systemRed),
            reminder("Call mom", dayOffset: 0, hour: 17.5, color: .systemOrange),
            reminder("Pick up dry cleaning", dayOffset: 0, hour: nil, color: .systemOrange),
            reminder("Renew passport", dayOffset: 3, hour: nil, color: .systemBlue),
            reminder("Dentist follow-up", dayOffset: 12, hour: nil, color: .systemBlue),
            reminder("Buy a new HDMI cable", dayOffset: nil, hour: nil, color: .systemGreen),
        ])
        services.calendar.loadSample(today: empty ? [] : [
            event("Design review", hour: 13.5, color: .systemBlue),
            event("1:1 with Sam", hour: 16, color: .systemOrange),
            event("Gym", hour: 18.25, color: .systemGreen),
        ], tomorrow: empty ? [] : [
            event("Team lunch", hour: 24 + 12.5, color: .systemOrange),
        ], later: empty ? [] : [
            event("Flight to Austin", hour: 72 + 9, color: .systemPurple),
        ])
    }

    static func notifications() -> [NotchNotification] {
        func make(_ app: String, _ title: String, _ subtitle: String, _ body: String, minutesAgo: Double) -> NotchNotification {
            let url = ["/Applications", "/System/Applications"].lazy
                .map { URL(fileURLWithPath: $0).appendingPathComponent(app + ".app") }
                .first { FileManager.default.fileExists(atPath: $0.path) }
            // No app URL: clicking a sample shouldn't open real apps.
            return .init(id: UUID().uuidString, appName: app, title: title, subtitle: subtitle, body: body,
                         date: Date().addingTimeInterval(-minutesAgo * 60), appURL: nil,
                         icon: url.map { NSWorkspace.shared.icon(forFile: $0.path) })
        }
        return [
            make("Messages", "Alex Rivera", "", "Are we still on for dinner tonight? I can book the place on 5th", minutesAgo: 0),
            make("Claude", "Claude", "", "Your task is finished: notch layout updated", minutesAgo: 4),
            make("Calendar", "Standup in 10 minutes", "", "Zoom · Engineering", minutesAgo: 52),
            make("Cursor", "Cursor finished", "", "portfolio-website", minutesAgo: 75),
            make("Claude", "Claude needs you", "", "Claude needs your permission to use Bash", minutesAgo: 90),
        ]
    }

    private static func artwork() -> NSImage {
        NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.75, green: 0.2, blue: 0.2, alpha: 1),
                                NSColor(red: 0.2, green: 0.05, blue: 0.1, alpha: 1)])?
                .draw(in: rect, angle: -60)
            return true
        }
    }
}
#endif
