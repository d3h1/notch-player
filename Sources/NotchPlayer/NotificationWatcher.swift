import AppKit
import ApplicationServices

/// A notification another app posted, as read from its macOS banner.
struct NotchNotification: Identifiable, Equatable {
    let id: String
    let appName: String
    let title: String
    let subtitle: String
    let body: String
    let date: Date
    let appURL: URL?
    let icon: NSImage?
}

/// Watches the banners macOS shows for other apps' notifications (Messages,
/// Claude, Slack…) and keeps the recent ones. Also takes notifications
/// sent straight to it (see `directName`), e.g. from Claude Code and Cursor
/// hooks via `notch-notify`.
///
/// There's no public API for this, so it reads the banner through the
/// Accessibility API, which needs Accessibility access. Only notifications
/// that actually pop up are seen: not ones silenced by Focus, or apps whose
/// alert style is None.
final class NotificationWatcher: ObservableObject {
    @Published private(set) var recent: [NotchNotification] = []
    @Published private(set) var unreadCount = 0
    @Published private(set) var hasAccess = AXIsProcessTrusted()

    var onNew: ((NotchNotification) -> Void)?
    /// Close each macOS banner as soon as it's been read, so notifications
    /// only show in the notch. Closing also removes it from Notification
    /// Center, and clicking it in the notch then opens just the app.
    var closesBanners = false

    private static let bundleID = "com.apple.notificationcenterui"
    private static let maxRecent = 20
    /// Distributed notification with `app`, `title`, `body` and optionally
    /// `appPath` in userInfo.
    static let directName = Notification.Name("com.notchplayer.notify")
    /// A banner from an app that just notified directly is the same news.
    private static let duplicateWindow: TimeInterval = 10

    private var observer: AXObserver?
    private var appElement: AXUIElement?
    /// Banners that are on screen right now, for opening them.
    private var liveBanners: [String: AXUIElement] = [:]
    private var seen = Set<String>()
    private var pendingScan: DispatchWorkItem?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var accessObserver: NSObjectProtocol?
    private var directObserver: NSObjectProtocol?
    private var lastDirect: [String: Date] = [:]

    func start() {
        guard workspaceObservers.isEmpty else { return }
        // Notification Center can be relaunched by the system; follow it.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == Self.bundleID else { return }
                self?.detach()
                self?.attach()
            })
        }
        accessObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            // The new state takes a moment to apply.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.accessChanged() }
        }
        directObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.directName, object: nil, queue: .main
        ) { [weak self] note in self?.receiveDirect(note.userInfo ?? [:]) }
        attach()
    }

    func stop() {
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers = []
        for observer in [accessObserver, directObserver].compactMap({ $0 }) {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        accessObserver = nil
        directObserver = nil
        detach()
    }

    /// Opens the notification the way clicking its banner would, or just its
    /// app once the banner has gone.
    func open(_ notification: NotchNotification) {
        if let banner = liveBanners[notification.id],
           AXUIElementPerformAction(banner, kAXPressAction as CFString) == .success {
            // Done: macOS opens the right conversation, document, etc.
        } else if let url = notification.appURL {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        dismiss(notification)
    }

    func dismiss(_ notification: NotchNotification) {
        recent.removeAll { $0.id == notification.id }
        unreadCount = min(unreadCount, recent.count)
    }

    func markAllRead() {
        if unreadCount != 0 { unreadCount = 0 }
    }

    func clear() {
        recent = []
        unreadCount = 0
    }

    /// A notification sent straight to the notch. Needs no Accessibility
    /// access, and works even while the sending app is in front.
    private func receiveDirect(_ info: [AnyHashable: Any]) {
        let appName = info["app"] as? String ?? ""
        let title = info["title"] as? String ?? ""
        guard !appName.isEmpty || !title.isEmpty else { return }
        lastDirect[appName] = Date()
        // The sender may name the exact app (e.g. Cursor, for Claude Code
        // running inside it); otherwise find it by name.
        let givenURL = (info["appPath"] as? String).flatMap { path in
            FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        let appURL = givenURL ?? Self.appURL(named: appName)
        add(NotchNotification(id: UUID().uuidString, appName: appName, title: title,
                              subtitle: "", body: info["body"] as? String ?? "", date: Date(),
                              appURL: appURL, icon: appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }))
    }

    private func add(_ notification: NotchNotification) {
        recent.insert(notification, at: 0)
        if recent.count > Self.maxRecent { recent.removeLast(recent.count - Self.maxRecent) }
        unreadCount = min(unreadCount + 1, recent.count)
        onNew?(notification)
    }

    // MARK: - Observing Notification Center

    private func accessChanged() {
        hasAccess = AXIsProcessTrusted()
        hasAccess ? attach() : detach()
    }

    private func attach() {
        hasAccess = AXIsProcessTrusted()
        guard observer == nil, hasAccess,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first
        else { return }

        let pid = app.processIdentifier
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<NotificationWatcher>.fromOpaque(refcon).takeUnretainedValue().scheduleScan()
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }

        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        // A banner arriving creates a window, then lays out its content.
        for name in [kAXWindowCreatedNotification, kAXLayoutChangedNotification] {
            AXObserverAddNotification(created, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        appElement = element
        // Whatever is on screen already isn't new.
        scan(announce: false)
    }

    private func detach() {
        pendingScan?.cancel()
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        appElement = nil
        liveBanners = [:]
    }

    /// Events come in bursts while a banner animates in. Read on the first
    /// one, so the banner can be closed before it has fully slid in, and
    /// again once the burst settles for anything whose text wasn't ready.
    private func scheduleScan() {
        if pendingScan == nil { scan(announce: true) }
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingScan = nil
            self?.scan(announce: true)
        }
        pendingScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func scan(announce: Bool) {
        guard let appElement else { return }
        var banners: [(id: String, element: AXUIElement)] = []
        for window in Self.elements(appElement, kAXWindowsAttribute) {
            Self.collectBanners(in: window, depth: 0, into: &banners)
        }
        liveBanners = Dictionary(banners.map { ($0.id, $0.element) }, uniquingKeysWith: { first, _ in first })

        if seen.count > 500 { seen = Set(banners.map(\.id)) }
        let fresh = banners.filter { !seen.contains($0.id) }
        // A burst of "new" banners means a list was revealed, not that
        // several notifications arrived at once.
        guard announce, fresh.count <= 2 else {
            fresh.forEach { seen.insert($0.id) }
            return
        }

        for banner in fresh.reversed() {
            // No text yet: leave it for the next scan.
            guard let notification = Self.read(banner.element, id: banner.id) else { continue }
            seen.insert(banner.id)
            if closesBanners {
                liveBanners[banner.id] = nil
                Self.close(banner.element)
            }
            if let last = lastDirect[notification.appName],
               Date().timeIntervalSince(last) < Self.duplicateWindow { continue }
            add(notification)
        }
    }

    /// Runs the banner's own Close action (Clear All for a stack). macOS
    /// ignores it until the banner has finished sliding in, so keep trying
    /// every tenth of a second until the banner is gone.
    private static func close(_ banner: AXUIElement, attemptsLeft: Int = 25) {
        guard attemptsLeft > 0, string(banner, kAXRoleAttribute) != nil else { return }
        performClose(banner)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            close(banner, attemptsLeft: attemptsLeft - 1)
        }
    }

    private static func performClose(_ banner: AXUIElement) {
        var names: CFArray?
        guard AXUIElementCopyActionNames(banner, &names) == .success,
              let actions = names as? [String] else { return }
        // Custom actions are named like "Name:Close\nTarget:…".
        let close = actions.first { $0.hasPrefix("Name:Close") }
            ?? actions.first { $0.hasPrefix("Name:Clear All") }
        if let close {
            AXUIElementPerformAction(banner, close as CFString)
        }
    }

    /// Pop-up banners sit directly in Notification Center's scroll area. The
    /// list you see when opening Notification Center nests them one level
    /// deeper; those are old notifications and are skipped.
    private static func collectBanners(in element: AXUIElement, depth: Int,
                                       into found: inout [(id: String, element: AXUIElement)]) {
        guard depth < 8 else { return }
        let isScrollArea = string(element, kAXRoleAttribute) == kAXScrollAreaRole
        for child in elements(element, kAXChildrenAttribute) {
            let subrole = string(child, kAXSubroleAttribute) ?? ""
            if subrole.hasPrefix("AXNotificationCenterBanner") {
                if isScrollArea, let id = string(child, kAXIdentifierAttribute) {
                    found.append((id, child))
                }
            } else {
                collectBanners(in: child, depth: depth + 1, into: &found)
            }
        }
    }

    private static func read(_ banner: AXUIElement, id: String) -> NotchNotification? {
        var texts: [String: String] = [:]
        collectTexts(in: banner, depth: 0, into: &texts)
        // The description reads "App, title, subtitle, body".
        let appName = string(banner, kAXDescriptionAttribute)?
            .components(separatedBy: ", ").first ?? ""
        let title = texts["title"] ?? ""
        guard !title.isEmpty || !(texts["body"] ?? "").isEmpty else { return nil }

        let appURL = appURL(named: appName)
        return NotchNotification(id: id, appName: appName, title: title,
                                 subtitle: texts["subtitle"] ?? "", body: texts["body"] ?? "",
                                 date: Date(), appURL: appURL,
                                 icon: appURL.map { NSWorkspace.shared.icon(forFile: $0.path) })
    }

    /// Title, subtitle and body are static texts identified by those names.
    /// For a stack, the first (newest) of each wins.
    private static func collectTexts(in element: AXUIElement, depth: Int, into texts: inout [String: String]) {
        guard depth < 5 else { return }
        for child in elements(element, kAXChildrenAttribute) {
            if string(child, kAXRoleAttribute) == kAXStaticTextRole,
               let key = string(child, kAXIdentifierAttribute), texts[key] == nil,
               let value = string(child, kAXValueAttribute) {
                texts[key] = value
            }
            collectTexts(in: child, depth: depth + 1, into: &texts)
        }
    }

    private static func appURL(named name: String) -> URL? {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) {
            return app.bundleURL
        }
        let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                       NSHomeDirectory() + "/Applications"]
        return folders.lazy
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name + ".app") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - AX helpers

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
}

#if DEBUG
extension NotificationWatcher {
    func loadSample(_ notifications: [NotchNotification], unread: Int) {
        recent = notifications
        unreadCount = unread
    }
}
#endif
