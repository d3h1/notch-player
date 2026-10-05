import SwiftUI

struct NotchView: View {
    @ObservedObject var controller: NotchController
    @ObservedObject private var player: NowPlayingService
    @ObservedObject private var activities: ActivityCenter
    @ObservedObject private var settings: AppSettings
    @ObservedObject private var weather: WeatherService
    @ObservedObject private var mediaKeys: MediaKeyTap
    @ObservedObject private var notifications: NotificationWatcher
    @State private var opensAtLogin = LoginItem.isEnabled

    init(controller: NotchController) {
        let services = controller.services
        self.controller = controller
        _player = ObservedObject(wrappedValue: services.player)
        _activities = ObservedObject(wrappedValue: services.activities)
        _settings = ObservedObject(wrappedValue: services.settings)
        _weather = ObservedObject(wrappedValue: services.weather)
        _mediaKeys = ObservedObject(wrappedValue: services.mediaKeys)
        _notifications = ObservedObject(wrappedValue: services.notifications)
    }

    var body: some View {
        let metrics = controller.metrics
        let expanded = controller.isExpanded
        let size = expanded ? controller.expandedSize : controller.closedSize
        // Taller than the notch: open, or a notification dropping down.
        let dropsDown = size.height > metrics.notchHeight
        let shape = NotchShape(topRadius: metrics.ear, bottomRadius: expanded ? 26 : dropsDown ? 20 : 10)

        // Content is laid out at its final size and revealed by the clip as
        // the shape grows, so text never reflows mid-animation.
        ZStack(alignment: .top) {
            if expanded {
                ExpandedNotchView(metrics: metrics,
                                  size: controller.expandedSize,
                                  showsSidebar: controller.showsSidebar,
                                  showsNotifications: $controller.showsNotifications,
                                  services: controller.services)
                    .frame(width: controller.expandedSize.width, height: controller.expandedSize.height)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .top)).animation(.easeOut(duration: 0.16).delay(0.03)),
                        removal: .opacity.animation(.easeIn(duration: 0.06))))
            } else if let activity = activities.current {
                ActivityView(activity: activity, metrics: metrics, showsPreview: settings.notificationPreviews)
                    .frame(width: controller.closedSize.width, height: controller.closedSize.height)
                    .id(activity.kind)
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
            } else if player.hasMedia || controller.hasUnread {
                ClosedNotchView(metrics: metrics, player: player, notifications: notifications,
                                showsUnread: controller.hasUnread)
                    .frame(width: metrics.closedSize(wing: metrics.wing).width, height: metrics.notchHeight)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(shape.fill(.black))
        .clipShape(shape)
        // With nothing to show the physical notch already looks right.
        .opacity(expanded || controller.showsClosedContent ? 1 : 0)
        .contextMenu { menu }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .coordinateSpace(name: PanelSpace.name)
        .onPreferenceChange(HandFramesKey.self) { controller.pointer.handFrames = $0 }
        .environmentObject(controller.pointer)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: player.hasMedia)
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: activities.current?.kind)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: controller.hasUnread)
    }

    @ViewBuilder private var menu: some View {
        Toggle("Open at Login", isOn: Binding(
            get: { opensAtLogin },
            set: { LoginItem.setEnabled($0); opensAtLogin = LoginItem.isEnabled }))
        Divider()
        Section("Show in Notch") {
            Toggle("Calendar", isOn: $settings.showCalendar)
            Toggle("Reminders", isOn: $settings.showReminders)
            Toggle("Weather", isOn: $settings.showWeather)
            Toggle("Volume & Brightness", isOn: $settings.notchHUD)
            Toggle("Notifications", isOn: $settings.showNotifications)
            if settings.showNotifications {
                Toggle("Message Previews", isOn: $settings.notificationPreviews)
                Toggle("Hide macOS Pop-ups", isOn: $settings.hideSystemBanners)
            }
            if (settings.notchHUD && !mediaKeys.hasAccess)
                || (settings.showNotifications && !notifications.hasAccess) {
                Button("Allow Accessibility Access…") { mediaKeys.openAccessibilitySettings() }
            }
        }
        Divider()
        Button("Quit Notch Player") { NSApp.terminate(nil) }
    }
}

/// Artwork on the left of the notch, equalizer on the right, with a dot for
/// unread notifications. With nothing playing: the latest notification's app
/// and the unread count.
private struct ClosedNotchView: View {
    let metrics: NotchMetrics
    @ObservedObject var player: NowPlayingService
    @ObservedObject var notifications: NotificationWatcher
    let showsUnread: Bool

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if player.hasMedia {
                    ArtworkView(image: player.artwork, size: metrics.notchHeight - 12, cornerRadius: 6)
                        .overlay(alignment: .topTrailing) {
                            if showsUnread {
                                UnreadDot()
                                    .offset(x: 3, y: -3)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                } else if let latest = notifications.recent.first {
                    AppIcon(image: latest.icon, size: metrics.notchHeight - 12)
                }
            }
            .frame(width: metrics.wing)
            Spacer(minLength: 0)
            Group {
                if player.hasMedia {
                    EqualizerBars(isPlaying: player.isPlaying, color: player.accentColor)
                        .frame(width: 13, height: metrics.notchHeight * 0.3)
                } else {
                    Text("\(notifications.unreadCount)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(unreadBlue))
                }
            }
            .frame(width: metrics.wing)
        }
        .padding(.horizontal, metrics.ear)
    }
}

private struct ExpandedNotchView: View {
    let metrics: NotchMetrics
    let size: CGSize
    let showsSidebar: Bool
    @Binding var showsNotifications: Bool
    let services: NotchServices
    @ObservedObject private var player: NowPlayingService
    @ObservedObject private var battery: BatteryMonitor
    @ObservedObject private var settings: AppSettings
    @ObservedObject private var notifications: NotificationWatcher
    @State private var titleRowWidth: CGFloat = 0
    @State private var revealingTitle = false

    /// Height of the player block: artwork row, gap, progress row. The
    /// sidebar matches it so both columns start and end together.
    static let contentHeight: CGFloat = 64 + 12 + 14

    init(metrics: NotchMetrics, size: CGSize, showsSidebar: Bool, showsNotifications: Binding<Bool>,
         services: NotchServices) {
        self.metrics = metrics
        self.size = size
        self.showsSidebar = showsSidebar
        _showsNotifications = showsNotifications
        self.services = services
        _player = ObservedObject(wrappedValue: services.player)
        _battery = ObservedObject(wrappedValue: services.battery)
        _settings = ObservedObject(wrappedValue: services.settings)
        _notifications = ObservedObject(wrappedValue: services.notifications)
    }

    /// The notifications list is only offered while there's something in it.
    private var listingNotifications: Bool {
        showsNotifications && settings.showNotifications && !notifications.recent.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: metrics.notchHeight)
            HStack(alignment: .top, spacing: 36) {
                Group {
                    if listingNotifications {
                        NotificationList(watcher: notifications, showsPreview: settings.notificationPreviews)
                            .frame(height: Self.contentHeight)
                    } else if player.hasMedia {
                        nowPlaying
                    } else {
                        nothingPlaying
                    }
                }
                .frame(maxWidth: .infinity)
                if showsSidebar {
                    SidebarView(calendar: services.calendar,
                                reminders: services.reminders,
                                weather: services.weather,
                                showsCalendar: settings.showCalendar,
                                showsReminders: settings.showReminders,
                                showsWeather: settings.showWeather)
                        .frame(width: 200, height: Self.contentHeight)
                }
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.ear + 18)
        .padding(.bottom, 14)
    }

    /// Source app and a playing indicator (or the notifications title) left
    /// of the notch; notifications bell and battery right of it.
    private var header: some View {
        let side = max(0, (size.width - metrics.notchWidth) / 2 - metrics.ear - 26)
        return HStack(spacing: 0) {
            Group {
                if listingNotifications {
                    notificationsTitle
                } else {
                    playerTitle
                }
            }
            .frame(width: side, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                if settings.showNotifications && !notifications.recent.isEmpty {
                    BellButton(unread: notifications.unreadCount, isActive: listingNotifications) {
                        withAnimation(.easeOut(duration: 0.15)) { showsNotifications.toggle() }
                    }
                }
                if battery.hasBattery {
                    batteryStatus
                }
            }
            .frame(width: side, alignment: .trailing)
        }
    }

    private var notificationsTitle: some View {
        HStack(spacing: 8) {
            Text("Notifications")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            HeaderTextButton(title: "Clear") {
                withAnimation(.easeOut(duration: 0.15)) {
                    notifications.clear()
                    showsNotifications = false
                }
            }
        }
    }

    private var playerTitle: some View {
        HStack(spacing: 6) {
            if let icon = player.sourceIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
            }
            if let name = player.sourceName {
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            if player.hasMedia {
                EqualizerBars(isPlaying: player.isPlaying, color: player.accentColor)
                    .frame(width: 12, height: 10)
                    .padding(.leading, 1)
            }
        }
    }

    private var batteryStatus: some View {
        let tint: Color = battery.isCharging
            ? Color(red: 0.25, green: 0.85, blue: 0.4)
            : battery.percent <= 20 && !battery.isPluggedIn
                ? Color(red: 1, green: 0.27, blue: 0.23)
                : .white.opacity(0.85)
        return HStack(spacing: 5) {
            Text("\(battery.percent)%")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
            BatteryGlyph(percent: battery.percent, tint: tint, showsBolt: battery.isPluggedIn)
        }
    }

    private var nowPlaying: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                OpenAppArtwork(image: player.artwork, size: 64) { player.openSourceApp() }
                // Controls sit right after the title instead of at the far edge.
                HuggingRow(spacing: 18) {
                    TrackTitle(title: player.title, artist: player.artist,
                               revealWidth: titleRowWidth, revealing: $revealingTitle)
                    controls
                        .opacity(revealingTitle ? 0 : 1)
                        .animation(.easeOut(duration: 0.15), value: revealingTitle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { titleRowWidth = $0 }
            }
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let elapsed = player.elapsed(at: context.date)
                HStack(spacing: 8) {
                    timeLabel(formatTime(elapsed), alignment: .trailing)
                    ProgressBar(progress: player.duration > 0 ? elapsed / player.duration : 0,
                                tint: .white.opacity(0.85)) { fraction in
                        player.seek(to: fraction * player.duration)
                    }
                    timeLabel(player.duration > 0 ? formatTime(player.duration) : "--:--",
                              alignment: .leading)
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 2) {
            ControlButton(symbol: "backward.fill", size: 14) { player.send(.previousTrack) }
            ControlButton(symbol: player.isPlaying ? "pause.fill" : "play.fill", size: 20) {
                player.togglePlayPause()
            }
            ControlButton(symbol: "forward.fill", size: 14) { player.send(.nextTrack) }
        }
    }

    @ViewBuilder private var nothingPlaying: some View {
        if showsSidebar {
            // Same shape as the player so the panel keeps its layout.
            HStack(spacing: 14) {
                ArtworkView(image: nil, size: 64, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nothing playing")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Play something to see it here")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: Self.contentHeight, alignment: .top)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 14, weight: .medium))
                Text("Nothing playing")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
    }

    private func timeLabel(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.4))
            .frame(width: 32, alignment: alignment)
    }
}

/// Title and artist. When the title is cut off, hovering it shows the whole
/// title in place of the controls next to it.
private struct TrackTitle: View {
    let title: String
    let artist: String
    /// How far the full title may extend when revealed.
    let revealWidth: CGFloat
    /// Set while the full title is showing, so the controls can step aside.
    @Binding var revealing: Bool

    @State private var hovering = false
    @State private var shownWidth: CGFloat = 0
    @State private var fullWidth: CGFloat = 0

    private var isTruncated: Bool { fullWidth > shownWidth + 0.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            titleText
                // The cut-off version would show through the full one.
                .opacity(hovering && isTruncated ? 0 : 1)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { shownWidth = $0 }
                .background(alignment: .leading) {
                    titleText
                        .fixedSize()
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fullWidth = $0 }
                }
                .overlay(alignment: .leading) {
                    if hovering && isTruncated {
                        titleText
                            .frame(width: min(fullWidth, revealWidth), alignment: .leading)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .onPointerHover { hovering = $0 }
                .onChange(of: hovering && isTruncated) { _, reveal in revealing = reveal }
                .animation(.easeOut(duration: 0.15), value: hovering)
            Text(artist)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
        }
        .lineLimit(1)
    }

    private var titleText: some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
    }
}
