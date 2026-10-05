import SwiftUI

/// Blue used for unread notifications.
let unreadBlue = Color(red: 0.2, green: 0.55, blue: 1)

/// A new notification dropping down from the notch: the app beside the notch,
/// then its icon, sender or title, and a line of the message.
struct NotificationPill: View {
    let notification: NotchNotification
    let metrics: NotchMetrics
    let showsPreview: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(notification.appName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                // Keep both labels clear of the notch itself.
                Spacer(minLength: metrics.notchWidth + 16)
                Text("now")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, metrics.ear + 16)
            .frame(height: metrics.notchHeight)
            HStack(spacing: 10) {
                AppIcon(image: notification.icon, size: 30)
                NotificationText(notification: notification, showsPreview: showsPreview, titleSize: 13)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, metrics.ear + 14)
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity)
        }
    }
}

/// Recent notifications, newest first; scrolls with the trackpad or wheel.
/// Clicking one opens it.
struct NotificationList: View {
    @ObservedObject var watcher: NotificationWatcher
    let showsPreview: Bool

    var body: some View {
        TimelineView(.everyMinute) { context in
            // Rows pad themselves 8pt for the hover highlight.
            PanelScroll(bleed: 8) {
                VStack(spacing: 2) {
                    ForEach(watcher.recent) { notification in
                        NotificationRow(notification: notification, showsPreview: showsPreview,
                                        now: context.date) { watcher.open(notification) }
                    }
                }
            }
        }
    }
}

private struct NotificationRow: View {
    let notification: NotchNotification
    let showsPreview: Bool
    let now: Date
    let action: () -> Void

    @Environment(\.hoverClip) private var clip
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            AppIcon(image: notification.icon, size: 26)
            NotificationText(notification: notification, showsPreview: showsPreview, titleSize: 12)
            Spacer(minLength: 6)
            Text(age)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(hovering ? 0.09 : 0))
        )
        .contentShape(Rectangle())
        // Rows scrolled out of view are still laid out; ignore clicks there.
        .onTapGesture(coordinateSpace: .named(PanelSpace.name)) { location in
            if clip?.contains(location) ?? true { action() }
        }
        .onPointerHover(pointer: true) { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var age: String {
        let seconds = Int(now.timeIntervalSince(notification.date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return notification.date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Sender or title, then the message (or just the subtitle when previews
/// are off).
private struct NotificationText: View {
    let notification: NotchNotification
    let showsPreview: Bool
    let titleSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(notification.title.isEmpty ? notification.appName : notification.title)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(.white)
            if let detail {
                Text(detail)
                    .font(.system(size: titleSize - 1))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .lineLimit(1)
    }

    private var detail: String? {
        let parts = showsPreview ? [notification.subtitle, notification.body] : [notification.subtitle]
        let line = parts.filter { !$0.isEmpty }.joined(separator: " · ")
        return line.isEmpty ? nil : line
    }
}

struct AppIcon: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(.white.opacity(0.15))
                .frame(width: size * 0.84, height: size * 0.84)
                .overlay {
                    Image(systemName: "bell.fill")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(width: size, height: size)
        }
    }
}

/// Bell in the panel header: switches between the player and notifications,
/// and carries the unread count.
struct BellButton: View {
    let unread: Int
    let isActive: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isActive ? "bell.fill" : "bell")
                .font(.system(size: 10.5, weight: .semibold))
            if unread > 0 {
                Text("\(unread)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
            }
        }
        .foregroundStyle(.white.opacity(unread > 0 || hovering || isActive ? 1 : 0.55))
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(
            Capsule().fill(unread > 0 ? unreadBlue : .white.opacity(isActive ? 0.16 : hovering ? 0.1 : 0))
        )
        .contentShape(Capsule())
        .onTapGesture(perform: action)
        .onPointerHover(pointer: true) { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Small blue dot marking unread notifications.
struct UnreadDot: View {
    var body: some View {
        Circle()
            .fill(unreadBlue)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(.black, lineWidth: 1.5))
    }
}

/// Small text button for the panel header, e.g. "Clear".
struct HeaderTextButton: View {
    let title: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.45))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onPointerHover(pointer: true) { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
