import AppKit
import EventKit

/// Unfinished reminders from every list in the Reminders app: those with a
/// due date first, soonest first, then those without one.
final class RemindersService: ObservableObject {
    struct Reminder: Identifiable, Equatable {
        let id: String
        let title: String
        /// The due time, or the start of the due day when there's no time;
        /// nil without a due date.
        let due: Date?
        let hasTime: Bool
        let color: NSColor

        func isOverdue(now: Date) -> Bool {
            guard let due else { return false }
            return hasTime ? due < now : due < Calendar.current.startOfDay(for: now)
        }
    }

    @Published private(set) var access: CalendarService.Access = .notAsked
    @Published private(set) var incomplete: [Reminder] = []

    private static let limit = 100

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var timer: Timer?

    func start() {
        switch EKEventStore.authorizationStatus(for: .reminder) {
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
        guard EKEventStore.authorizationStatus(for: .reminder) == .notDetermined else {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!
            NSWorkspace.shared.open(url)
            return
        }
        store.requestFullAccessToReminders { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.access = granted ? .granted : .denied
                if granted { self?.begin() }
            }
        }
    }

    func openRemindersApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func begin() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in self?.reload() }
        // Every few minutes, so the day rolls over.
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in self?.reload() }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        reload()
    }

    private func reload() {
        let calendar = Calendar.current
        // No dates: every unfinished reminder, with or without a due date.
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil,
                                                              calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let items = (reminders ?? []).map { reminder -> (Reminder, Date) in
                let components = reminder.dueDateComponents
                let date = components.flatMap { calendar.date(from: $0) }
                let hasTime = components?.hour != nil
                let item = Reminder(id: reminder.calendarItemIdentifier,
                                    title: reminder.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled",
                                    due: date.map { hasTime ? $0 : calendar.startOfDay(for: $0) },
                                    hasTime: hasTime,
                                    color: reminder.calendar?.color ?? .systemOrange)
                return (item, reminder.creationDate ?? .distantPast)
            }
            // Dated soonest first; undated newest first.
            let incomplete = items.sorted { a, b in
                switch (a.0.due, b.0.due) {
                case let (x?, y?): x < y
                case (.some, nil): true
                case (nil, .some): false
                case (nil, nil): a.1 > b.1
                }
            }
            .prefix(Self.limit)
            .map(\.0)
            DispatchQueue.main.async {
                guard let self, self.incomplete != incomplete else { return }
                self.incomplete = incomplete
            }
        }
    }
}

#if DEBUG
extension RemindersService {
    func loadSample(_ reminders: [Reminder]) {
        access = .granted
        incomplete = reminders
    }
}
#endif
