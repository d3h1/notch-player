import SwiftUI

/// A short-lived alert in the closed notch: an icon in the left wing and a
/// level bar or label in the right one.
struct ActivityView: View {
    let activity: NotchActivity
    let metrics: NotchMetrics

    private static let green = Color(red: 0.25, green: 0.85, blue: 0.4)
    private static let red = Color(red: 1, green: 0.27, blue: 0.23)

    var body: some View {
        // 12pt from the outer edge, 8pt clear of the notch.
        let side = metrics.wing(for: activity) - 20
        HStack(spacing: 0) {
            leading
                .frame(width: side, alignment: .leading)
            Spacer(minLength: 0)
            trailing
                .frame(width: side, alignment: .trailing)
        }
        .padding(.horizontal, metrics.ear + 12)
        .frame(height: metrics.notchHeight)
    }

    @ViewBuilder private var leading: some View {
        switch activity {
        case let .volume(level, muted):
            symbol(Self.volumeSymbol(level: level, muted: muted))
        case let .brightness(level):
            symbol(level < 0.5 ? "sun.min.fill" : "sun.max.fill")
        case .charging:
            symbol("bolt.fill", color: Self.green)
        case let .lowBattery(percent):
            BatteryGlyph(percent: percent, tint: Self.red)
        case let .audioOutput(_, symbolName):
            symbol(symbolName, size: 15)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch activity {
        case let .volume(level, muted):
            LevelBar(level: muted ? 0 : level)
        case let .brightness(level):
            LevelBar(level: level)
        case let .charging(percent):
            HStack(spacing: 6) {
                label("\(percent)%")
                BatteryGlyph(percent: percent, tint: Self.green)
            }
        case let .lowBattery(percent):
            label("\(percent)%", color: Self.red)
        case let .audioOutput(name, _):
            label(name)
        }
    }

    private func symbol(_ name: String, size: CGFloat = 13, color: Color = .white) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .contentTransition(.symbolEffect(.replace))
    }

    private func label(_ text: String, color: Color = .white) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private static func volumeSymbol(level: Float, muted: Bool) -> String {
        if muted || level == 0 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

/// Thin horizontal level, like the macOS volume pop-up.
struct LevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule().fill(.white)
                    .frame(width: geo.size.width * CGFloat(min(max(level, 0), 1)))
            }
        }
        .frame(height: 5)
        .animation(.spring(response: 0.2, dampingFraction: 0.9), value: level)
    }
}

/// Battery outline filled to the charge level.
struct BatteryGlyph: View {
    let percent: Int
    let tint: Color
    var showsBolt = false

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(.white.opacity(0.4), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tint)
                    .frame(width: max(1.5, 18 * CGFloat(min(max(percent, 0), 100)) / 100))
                    .padding(2)
                if showsBolt {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7.5, weight: .black))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 0.5)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 22, height: 11)
            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.4))
                .frame(width: 1.5, height: 4)
        }
    }
}
