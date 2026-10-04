import AppKit
import EventKit

/// Today's remaining events and tomorrow's, from every calendar in the
/// Calendar app.
final class CalendarService: ObservableObject {
    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let color: NSColor
    }

    enum Access {
        case notAsked, granted, denied
    }

    @Published private(set) var access: Access = .notAsked
    @Published private(set) var today: [Event] = []
    @Published private(set) var tomorrow: [Event] = []

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var timer: Timer?

    func start() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            access = .granted
            begin()
        case .notDetermined:
            requestAccess()
        default:
            access = .denied
        }
    }

    /// Shows the system prompt the first time; after that the user has to
    /// change it in System Settings.
    func requestAccess() {
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
            NSWorkspace.shared.open(url)
            return
        }
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.access = granted ? .granted : .denied
                if granted { self?.begin() }
            }
        }
    }

    func openCalendarApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func begin() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in self?.reload() }
        // Once a minute, so finished events drop off and the day rolls over.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.reload() }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        reload()
    }

    private func reload() {
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
              let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday) else { return }

        let predicate = store.predicateForEvents(withStart: startOfToday, end: endOfTomorrow, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { event in
                event.endDate > now
                    && event.status != .canceled
                    && event.attendees?.first(where: \.isCurrentUser)?.participantStatus != .declined
            }
            .map { event in
                Event(id: event.eventIdentifier ?? UUID().uuidString,
                      title: event.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled",
                      start: event.startDate,
                      end: event.endDate,
                      isAllDay: event.isAllDay,
                      color: event.calendar?.color ?? .systemBlue)
            }
            // Timed events first: in a short list they matter more than
            // all-day ones like birthdays and holidays.
            .sorted { ($0.isAllDay ? 1 : 0, $0.start) < ($1.isAllDay ? 1 : 0, $1.start) }

        let newToday = events.filter { $0.start < startOfTomorrow }
        let newTomorrow = events.filter { $0.start >= startOfTomorrow }
        if newToday != today { today = newToday }
        if newTomorrow != tomorrow { tomorrow = newTomorrow }
    }
}

#if DEBUG
extension CalendarService {
    func loadSample(today: [Event], tomorrow: [Event] = []) {
        access = .granted
        self.today = today
        self.tomorrow = tomorrow
    }
}
#endif
