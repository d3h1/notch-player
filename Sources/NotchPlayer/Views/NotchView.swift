import SwiftUI

struct NotchView: View {
    @ObservedObject var controller: NotchController
    @ObservedObject private var player: NowPlayingService
    @ObservedObject private var activities: ActivityCenter
    @ObservedObject private var settings: AppSettings
    @ObservedObject private var weather: WeatherService
    @ObservedObject private var mediaKeys: MediaKeyTap
    @State private var opensAtLogin = LoginItem.isEnabled

    init(controller: NotchController) {
        let services = controller.services
        self.controller = controller
        _player = ObservedObject(wrappedValue: services.player)
        _activities = ObservedObject(wrappedValue: services.activities)
        _settings = ObservedObject(wrappedValue: services.settings)
        _weather = ObservedObject(wrappedValue: services.weather)
        _mediaKeys = ObservedObject(wrappedValue: services.mediaKeys)
    }

    var body: some View {
        let metrics = controller.metrics
        let expanded = controller.isExpanded
        let size = expanded ? controller.expandedSize : controller.closedSize
        let shape = NotchShape(topRadius: metrics.ear, bottomRadius: expanded ? 26 : 10)

        // Content is laid out at its final size and revealed by the clip as
        // the shape grows, so text never reflows mid-animation.
        ZStack(alignment: .top) {
            if expanded {
                ExpandedNotchView(metrics: metrics,
                                  size: controller.expandedSize,
                                  showsSidebar: controller.showsSidebar,
                                  services: controller.services)
                    .frame(width: controller.expandedSize.width, height: controller.expandedSize.height)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .top)).animation(.easeOut(duration: 0.16).delay(0.03)),
                        removal: .opacity.animation(.easeIn(duration: 0.06))))
            } else if let activity = activities.current {
                ActivityView(activity: activity, metrics: metrics)
                    .frame(width: controller.closedSize.width, height: metrics.notchHeight)
                    .id(activity.kind)
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
            } else if player.hasMedia {
                ClosedNotchView(metrics: metrics, player: player)
                    .frame(width: metrics.closedSize(wing: metrics.wing).width, height: metrics.notchHeight)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(shape.fill(.black))
        .clipShape(shape)
        .shadow(color: .black.opacity(expanded ? 0.6 : 0), radius: 18, y: 8)
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
    }

    @ViewBuilder private var menu: some View {
        Toggle("Open at Login", isOn: Binding(
            get: { opensAtLogin },
            set: { LoginItem.setEnabled($0); opensAtLogin = LoginItem.isEnabled }))
        Divider()
        Section("Show in Notch") {
            Toggle("Calendar", isOn: $settings.showCalendar)
            Toggle("Weather", isOn: $settings.showWeather)
            Toggle("Volume & Brightness", isOn: $settings.notchHUD)
            if settings.notchHUD && !mediaKeys.hasAccess {
                Button("Allow Accessibility Access…") { mediaKeys.openAccessibilitySettings() }
            }
        }
        Divider()
        Button("Quit Notch Player") { NSApp.terminate(nil) }
    }
}

/// Artwork on the left of the notch, equalizer on the right.
private struct ClosedNotchView: View {
    let metrics: NotchMetrics
    @ObservedObject var player: NowPlayingService

    var body: some View {
        HStack(spacing: 0) {
            ArtworkView(image: player.artwork, size: metrics.notchHeight - 12, cornerRadius: 6)
                .frame(width: metrics.wing)
            Spacer(minLength: 0)
            EqualizerBars(isPlaying: player.isPlaying, color: player.accentColor)
                .frame(width: 13, height: metrics.notchHeight * 0.3)
                .frame(width: metrics.wing)
        }
        .padding(.horizontal, metrics.ear)
    }
}

private struct ExpandedNotchView: View {
    let metrics: NotchMetrics
    let size: CGSize
    let showsSidebar: Bool
    let services: NotchServices
    @ObservedObject private var player: NowPlayingService
    @ObservedObject private var battery: BatteryMonitor
    @ObservedObject private var settings: AppSettings

    /// Height of the player block: artwork row, gap, progress row. The
    /// sidebar matches it so both columns start and end together.
    static let contentHeight: CGFloat = 64 + 12 + 14

    init(metrics: NotchMetrics, size: CGSize, showsSidebar: Bool, services: NotchServices) {
        self.metrics = metrics
        self.size = size
        self.showsSidebar = showsSidebar
        self.services = services
        _player = ObservedObject(wrappedValue: services.player)
        _battery = ObservedObject(wrappedValue: services.battery)
        _settings = ObservedObject(wrappedValue: services.settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: metrics.notchHeight)
            HStack(alignment: .top, spacing: 18) {
                Group {
                    if player.hasMedia {
                        nowPlaying
                    } else {
                        nothingPlaying
                    }
                }
                .frame(maxWidth: .infinity)
                if showsSidebar {
                    SidebarView(calendar: services.calendar,
                                weather: services.weather,
                                showsCalendar: settings.showCalendar,
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

    /// Source app and a playing indicator left of the notch, battery right of it.
    private var header: some View {
        let side = max(0, (size.width - metrics.notchWidth) / 2 - metrics.ear - 26)
        return HStack(spacing: 0) {
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
            .frame(width: side, alignment: .leading)
            Spacer(minLength: 0)
            if battery.hasBattery {
                batteryStatus
                    .frame(width: side, alignment: .trailing)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(player.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                controls
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
