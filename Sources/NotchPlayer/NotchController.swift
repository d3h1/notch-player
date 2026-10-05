import AppKit
import Combine
import SwiftUI

/// Everything the notch shows, created once by the app delegate.
struct NotchServices {
    let player: NowPlayingService
    let activities: ActivityCenter
    let battery: BatteryMonitor
    let calendar: CalendarService
    let reminders: RemindersService
    let weather: WeatherService
    let mediaKeys: MediaKeyTap
    let notifications: NotificationWatcher
    let settings: AppSettings
}

/// Owns the overlay panel, keeps it pinned over the notch and expands it while
/// the pointer is over it.
final class NotchController: ObservableObject {
    @Published private(set) var metrics = NotchMetrics()
    @Published private(set) var isExpanded: Bool
    /// The open panel shows recent notifications instead of the player.
    @Published var showsNotifications = false {
        didSet { if showsNotifications { services.notifications.markAllRead() } }
    }

    let services: NotchServices
    let pointer = PointerState()
    private let pinExpanded: Bool
    private let panel = NotchPanel()
    private var screen: NSScreen?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var pendingChange: DispatchWorkItem?
    private var showingHand = false

    /// The panel never resizes. The visible shape animates inside it, and the
    /// panel ignores the mouse whenever the pointer is outside that shape so
    /// clicks pass through to whatever is underneath.
    private static let panelSize = CGSize(width: 720, height: 280)

    init(services: NotchServices, pinExpanded: Bool = false) {
        self.services = services
        self.pinExpanded = pinExpanded
        isExpanded = pinExpanded
    }

    // MARK: - Layout

    var showsSidebar: Bool {
        let settings = services.settings
        return settings.showCalendar || settings.showReminders
            || (settings.showWeather && services.weather.current != nil)
    }

    var hasUnread: Bool {
        services.settings.showNotifications && services.notifications.unreadCount > 0
    }

    /// Whether the closed notch shows anything beyond the physical notch.
    var showsClosedContent: Bool {
        services.player.hasMedia || services.activities.current != nil || hasUnread
    }

    var closedSize: CGSize {
        if let activity = services.activities.current {
            return metrics.activitySize(for: activity)
        }
        return metrics.closedSize(wing: services.player.hasMedia || hasUnread ? metrics.wing : 0)
    }

    var expandedSize: CGSize {
        metrics.expandedSize(hasMedia: services.player.hasMedia || showsNotifications, hasSidebar: showsSidebar)
    }

    // MARK: - Panel

    func show() {
        let host = FirstClickHostingView(rootView: NotchView(controller: self))
        host.sizingOptions = []
        panel.contentView = host
        positionPanel()
        panel.orderFrontRegardless()

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.positionPanel() })

        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            self?.pointerMoved()
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.pointerMoved()
            return event
        }) {
            monitors.append(monitor)
        }
        // Scrolling goes to the window under the pointer, so the panel gets
        // it even while another app is active.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            if self?.isExpanded == true {
                // Mouse wheels report lines, trackpads points.
                self?.pointer.scrolled.send(event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 12))
            }
            return event
        }) {
            monitors.append(monitor)
        }

        // The hit area changes size when media, an alert or the sidebar comes or goes.
        let layoutChanges: [AnyPublisher<Void, Never>] = [
            services.player.$title.map { !$0.isEmpty }.removeDuplicates().map { _ in }.eraseToAnyPublisher(),
            services.activities.$current.map { $0?.kind }.removeDuplicates().map { _ in }.eraseToAnyPublisher(),
            services.settings.objectWillChange.eraseToAnyPublisher(),
            services.weather.$current.map { $0 != nil }.removeDuplicates().map { _ in }.eraseToAnyPublisher(),
            services.notifications.$unreadCount.map { $0 > 0 }.removeDuplicates().map { _ in }.eraseToAnyPublisher(),
            $showsNotifications.removeDuplicates().map { _ in }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(layoutChanges)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.pointerMoved() }
            .store(in: &cancellables)
    }

    private func positionPanel() {
        guard let screen = NotchMetrics.preferredScreen() else { return }
        self.screen = screen
        metrics = NotchMetrics(screen: screen)
        let size = Self.panelSize
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2,
                              y: screen.frame.maxY - size.height,
                              width: size.width, height: size.height),
                       display: true)
    }

    private func pointerMoved() {
        let mouse = NSEvent.mouseLocation
        let inside = hitRect().contains(mouse)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        updatePointer(mouse, inside: inside)
        guard !pinExpanded else { return }

        if inside == isExpanded {
            pendingChange?.cancel()
            pendingChange = nil
            return
        }
        guard pendingChange == nil else { return }

        // A short delay on open avoids flicker when the pointer just passes by;
        // a longer one on close forgives slightly overshooting the edge.
        let work = DispatchWorkItem { [weak self] in
            self?.pendingChange = nil
            self?.setExpanded(inside)
        }
        pendingChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.0 : 0.05), execute: work)
    }

    private func setExpanded(_ expanded: Bool) {
        let animation: Animation = expanded
            ? .spring(response: 0.3, dampingFraction: 0.66)
            : .easeOut(duration: 0.15)
        withAnimation(animation) {
            if expanded, case .notification = services.activities.current {
                // Hovering a new notification opens straight to the list.
                showsNotifications = true
                services.activities.hide()
            } else if !expanded {
                showsNotifications = false
            }
            isExpanded = expanded
        }
        pointerMoved()
    }

    /// Feeds the pointer position to the views' hover effects and shows the
    /// pointing hand over clickable parts.
    private func updatePointer(_ mouse: CGPoint, inside: Bool) {
        let frame = panel.frame
        let location = inside && isExpanded
            ? CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)
            : nil
        if pointer.location != location { pointer.location = location }

        let wantsHand = location.map { point in pointer.handFrames.contains { $0.contains(point) } } ?? false
        // Re-assert on every move: the active app may reset the cursor.
        if wantsHand {
            NSCursor.pointingHand.set()
        } else if showingHand {
            NSCursor.arrow.set()
        }
        showingHand = wantsHand
    }

    /// The area of the visible shape, in screen coordinates.
    private func hitRect() -> CGRect {
        guard let screen else { return .zero }
        let size: CGSize
        if isExpanded {
            size = expandedSize
        } else if showsClosedContent || metrics.hasNotch {
            size = closedSize
        } else {
            return .zero
        }
        // Reach slightly past the top edge so the topmost pixel row counts.
        return CGRect(x: screen.frame.midX - size.width / 2,
                      y: screen.frame.maxY - size.height,
                      width: size.width,
                      height: size.height + 2)
    }
}

/// Acts on the first click even when the panel isn't the key window. Without
/// this, after switching to another app (e.g. one the notch just opened),
/// the next click only focuses the panel and a second click is needed.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
