import SwiftUI

/// Weather, and today's events and reminders, as two cards to the right of
/// the player. Each card opens its app when clicked.
struct SidebarView: View {
    @ObservedObject var calendar: CalendarService
    @ObservedObject var reminders: RemindersService
    @ObservedObject var weather: WeatherService
    let showsCalendar: Bool
    let showsReminders: Bool
    let showsWeather: Bool

    var body: some View {
        let conditions = showsWeather ? weather.current : nil
        let showsAgenda = showsCalendar || showsReminders
        VStack(spacing: 6) {
            if let conditions {
                GlanceCard(action: openWeatherApp) {
                    WeatherSummary(conditions: conditions, large: !showsAgenda)
                }
                // A fixed height leaves the rest to the agenda.
                .frame(height: showsAgenda ? 40 : nil)
            }
            if showsAgenda {
                GlanceCard(action: openAgendaApp) {
                    AgendaSummary(calendar: calendar, reminders: reminders,
                                  showsCalendar: showsCalendar, showsReminders: showsReminders)
                }
            }
        }
    }

    private func openWeatherApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.weather") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Calendar, or Reminders when only reminders are shown.
    private func openAgendaApp() {
        if showsCalendar {
            calendar.access == .granted ? calendar.openCalendarApp() : calendar.requestAccess()
        } else {
            reminders.access == .granted ? reminders.openRemindersApp() : reminders.requestAccess()
        }
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

/// Events for the coming week and unfinished reminders, by day: today
/// (no heading), Tomorrow, the next weekdays, Later, and No date. Scrolls.
private struct AgendaSummary: View {
    @ObservedObject var calendar: CalendarService
    @ObservedObject var reminders: RemindersService
    let showsCalendar: Bool
    let showsReminders: Bool

    private struct AccessPrompt {
        let symbol: String
        let title: String
        let action: () -> Void
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let prompts = accessPrompts
            let sections = sections(now: now)
            PanelScroll(centersWhenFits: true) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(prompts, id: \.title) { prompt in
                        placeholder(prompt.symbol, prompt.title)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: prompt.action)
                    }
                    ForEach(sections) { section in
                        if let title = section.title {
                            Text(title)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                                .padding(.top, section.id == sections.first?.id ? 0 : 3)
                        }
                        ForEach(section.items) { item in
                            AgendaRow(item: item, now: now, isToday: section.isToday,
                                      showsDate: section.showsDates) { open(item) }
                        }
                    }
                    if prompts.isEmpty && sections.isEmpty {
                        placeholder(showsCalendar ? "calendar" : "checklist", emptyText)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var accessPrompts: [AccessPrompt] {
        var prompts: [AccessPrompt] = []
        if showsCalendar && calendar.access != .granted {
            prompts.append(AccessPrompt(symbol: "calendar", title: "Allow calendar access",
                                        action: calendar.requestAccess))
        }
        if showsReminders && reminders.access != .granted {
            prompts.append(AccessPrompt(symbol: "checklist", title: "Allow reminders access",
                                        action: reminders.requestAccess))
        }
        return prompts
    }

    private var emptyText: String {
        switch (showsCalendar, showsReminders) {
        case (true, true): "Nothing coming up"
        case (true, false): "No events this week"
        default: "No reminders"
        }
    }

    private func sections(now: Date) -> [AgendaSection] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today),
              let endOfWeek = cal.date(byAdding: .day, value: 7, to: today) else { return [] }

        var byDay: [Date: [AgendaItem]] = [:]
        var later: [AgendaItem] = []
        var undated: [AgendaItem] = []
        if showsCalendar && calendar.access == .granted {
            for event in calendar.today + calendar.tomorrow + calendar.later {
                // Events that started earlier and are still going count as today.
                byDay[max(cal.startOfDay(for: event.start), today), default: []].append(.event(event))
            }
        }
        if showsReminders && reminders.access == .granted {
            for reminder in reminders.incomplete {
                guard let due = reminder.due else {
                    undated.append(.reminder(reminder))
                    continue
                }
                let day = reminder.isOverdue(now: now) ? today : cal.startOfDay(for: due)
                if day < endOfWeek {
                    byDay[day, default: []].append(.reminder(reminder))
                } else {
                    later.append(.reminder(reminder))
                }
            }
        }

        var sections = byDay.keys.sorted().map { day in
            let title: String? = day == today ? nil
                : day == tomorrow ? "Tomorrow"
                : day.formatted(.dateTime.weekday(.wide))
            let items = byDay[day, default: []].sorted { $0.sortKey(now: now) < $1.sortKey(now: now) }
            return AgendaSection(id: "day-\(day.timeIntervalSince1970)", title: title, items: items,
                                 isToday: day == today)
        }
        if !later.isEmpty {
            sections.append(AgendaSection(id: "later", title: "Later", items: later, showsDates: true))
        }
        if !undated.isEmpty {
            sections.append(AgendaSection(id: "undated", title: "No date", items: undated))
        }
        return sections
    }

    private func open(_ item: AgendaItem) {
        switch item {
        case .event: calendar.openCalendarApp()
        case .reminder: reminders.openRemindersApp()
        }
    }

    private func placeholder(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.45))
    }
}

private struct AgendaSection: Identifiable {
    let id: String
    let title: String?
    let items: [AgendaItem]
    var isToday = false
    /// Rows show their date (the Later section), not just a time.
    var showsDates = false
}

private enum AgendaItem: Identifiable {
    case event(CalendarService.Event)
    case reminder(RemindersService.Reminder)

    var id: String {
        switch self {
        case let .event(event): "event-" + event.id
        case let .reminder(reminder): "reminder-" + reminder.id
        }
    }

    /// Overdue and happening now first, then by time, then all-day items.
    func sortKey(now: Date) -> (Int, Date) {
        switch self {
        case let .event(event):
            event.isAllDay ? (2, event.start) : (event.start <= now ? 0 : 1, event.start)
        case let .reminder(reminder):
            reminder.isOverdue(now: now)
                ? (0, reminder.due ?? now)
                : (reminder.hasTime ? 1 : 2, reminder.due ?? .distantFuture)
        }
    }
}

/// An event (colored bar) or reminder (open circle, like in Reminders), with
/// its time or date on the right.
private struct AgendaRow: View {
    let item: AgendaItem
    let now: Date
    let isToday: Bool
    let showsDate: Bool
    let action: () -> Void

    @Environment(\.hoverClip) private var clip

    private static let green = Color(red: 0.25, green: 0.85, blue: 0.4)
    private static let red = Color(red: 1, green: 0.38, blue: 0.33)

    var body: some View {
        HStack(spacing: 7) {
            marker
                .frame(width: 9)
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(label.text)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(label.color)
                .fixedSize()
        }
        .contentShape(Rectangle())
        // Rows scrolled out of view are still laid out; ignore clicks there.
        .onTapGesture(coordinateSpace: .named(PanelSpace.name)) { location in
            if clip?.contains(location) ?? true { action() }
        }
    }

    @ViewBuilder private var marker: some View {
        switch item {
        case let .event(event):
            Capsule()
                .fill(Color(nsColor: event.color))
                .frame(width: 3, height: 10)
        case let .reminder(reminder):
            Circle()
                .strokeBorder(Color(nsColor: reminder.color), lineWidth: 1.5)
                .frame(width: 9, height: 9)
        }
    }

    private var title: String {
        switch item {
        case let .event(event): event.title
        case let .reminder(reminder): reminder.title
        }
    }

    private var label: (text: String, color: Color) {
        let quiet = Color.white.opacity(0.4)
        switch item {
        case let .event(event):
            if event.isAllDay { return ("All day", quiet) }
            if isToday && event.start <= now { return ("Now", Self.green) }
            return (event.start.formatted(date: .omitted, time: .shortened), quiet)
        case let .reminder(reminder):
            guard let due = reminder.due else { return ("", quiet) }
            if reminder.isOverdue(now: now) { return ("Overdue", Self.red) }
            if showsDate { return (due.formatted(.dateTime.month(.abbreviated).day()), quiet) }
            if reminder.hasTime { return (due.formatted(date: .omitted, time: .shortened), quiet) }
            return (isToday ? "Today" : "", quiet)
        }
    }
}
