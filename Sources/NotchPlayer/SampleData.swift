#if DEBUG
import AppKit

/// Fake content for `--sample-data[=empty]` (debug builds only): lets the
/// expanded layout be worked on without real media, permissions or network.
enum SampleData {
    static func load(into services: NotchServices, empty: Bool) {
        services.player.loadSample(title: "Big Brother", artist: "Dyne Side",
                                   artwork: artwork(), bundleID: "com.spotify.client",
                                   duration: 261, elapsed: 167)
        services.weather.loadSample(.init(temperature: 37.8, high: 38.3, low: 22.8, code: 0, isDay: true))
        services.battery.loadSample(percent: 100, pluggedIn: true)

        let day = Calendar.current.startOfDay(for: Date())
        func event(_ title: String, hour: Double, color: NSColor) -> CalendarService.Event {
            let start = day.addingTimeInterval(hour * 3600)
            return .init(id: title, title: title, start: start, end: start.addingTimeInterval(1800),
                         isAllDay: false, color: color)
        }
        services.calendar.loadSample(today: empty ? [] : [
            event("Design review", hour: 13.5, color: .systemBlue),
            event("1:1 with Sam", hour: 16, color: .systemOrange),
            event("Gym", hour: 18.25, color: .systemGreen),
        ])
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
