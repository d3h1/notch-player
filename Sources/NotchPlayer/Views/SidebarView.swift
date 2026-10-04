import SwiftUI

/// Weather and upcoming events as two cards to the right of the player.
/// Each card opens its app when clicked.
struct SidebarView: View {
    @ObservedObject var calendar: CalendarService
    @ObservedObject var weather: WeatherService
    let showsCalendar: Bool
    let showsWeather: Bool

    var body: some View {
        let conditions = showsWeather ? weather.current : nil
        VStack(spacing: 6) {
            if let conditions {
                GlanceCard(action: openWeatherApp) {
                    WeatherSummary(conditions: conditions, large: !showsCalendar)
                }
                // A fixed height leaves the rest to the calendar.
                .frame(height: showsCalendar ? 40 : nil)
            }
            if showsCalendar {
                GlanceCard(action: calendar.access == .granted ? calendar.openCalendarApp : calendar.requestAccess) {
                    EventsSummary(calendar: calendar, maxRows: conditions == nil ? 4 : 2)
                }
            }
        }
    }

    private func openWeatherApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.weather") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Soft rounded panel that brightens on hover.
private struct GlanceCard<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content

    @State private var hovering = false

    var body: some View {
        content
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(hovering ? 0.11 : 0.065))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture(perform: action)
            .onPointerHover(pointer: true) { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

private struct WeatherSummary: View {
    let conditions: WeatherService.Conditions
    /// Bigger type when the card has the column to itself.
    let large: Bool

    var body: some View {
        HStack(spacing: large ? 12 : 9) {
            Image(systemName: conditions.symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: large ? 26 : 17))
                .frame(width: large ? 32 : 22)
            VStack(alignment: .leading, spacing: large ? 3 : 0) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(conditions.temperature.temperatureText)
                        .font(.system(size: large ? 22 : 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                    Text(conditions.summary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Text("H \(conditions.high.temperatureText)  L \(conditions.low.temperatureText)")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
            }
            .lineLimit(1)
        }
    }
}

private struct EventsSummary: View {
    @ObservedObject var calendar: CalendarService
    let maxRows: Int

    var body: some View {
        switch calendar.access {
        case .granted:
            TimelineView(.everyMinute) { context in
                if !calendar.today.isEmpty {
                    rows(calendar.today.prefix(maxRows), now: context.date)
                } else if !calendar.tomorrow.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tomorrow")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                        rows(calendar.tomorrow.prefix(maxRows - 1), now: context.date)
                    }
                } else {
                    placeholder("No events today")
                }
            }
        case .notAsked, .denied:
            placeholder("Allow calendar access")
        }
    }

    private func rows(_ events: ArraySlice<CalendarService.Event>, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(events) { EventRow(event: $0, now: now) }
        }
    }

    private func placeholder(_ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .medium))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.45))
    }
}

private struct EventRow: View {
    let event: CalendarService.Event
    let now: Date

    private var isHappening: Bool { !event.isAllDay && event.start <= now }

    private var time: String {
        if event.isAllDay { return "All day" }
        if isHappening { return "Now" }
        return event.start.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(Color(nsColor: event.color))
                .frame(width: 3, height: 10)
            Text(event.title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(time)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(isHappening ? Color(red: 0.25, green: 0.85, blue: 0.4) : .white.opacity(0.4))
                .fixedSize()
        }
    }
}
