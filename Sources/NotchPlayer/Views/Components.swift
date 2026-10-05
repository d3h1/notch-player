import SwiftUI

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Color.clear
            .frame(width: size, height: size)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(colors: [Color(white: 0.3), Color(white: 0.16)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Four bouncing bars while playing, resting low while paused.
///
/// Animated with Core Animation rather than a SwiftUI timeline: the system
/// compositor runs the animation, so the app itself stays idle while it plays.
struct EqualizerBars: NSViewRepresentable {
    let isPlaying: Bool
    let color: NSColor

    func makeNSView(context: Context) -> EqualizerView {
        EqualizerView()
    }

    func updateNSView(_ view: EqualizerView, context: Context) {
        view.update(isPlaying: isPlaying, color: color)
    }
}

final class EqualizerView: NSView {
    private let bars = (0..<4).map { _ in CALayer() }
    private let durations: [CFTimeInterval] = [0.26, 0.34, 0.22, 0.3]
    private var isPlaying: Bool?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        bars.forEach { layer?.addSublayer($0) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        let gap = bounds.width * 0.14
        let width = (bounds.width - gap * CGFloat(bars.count - 1)) / CGFloat(bars.count)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(i) * (width + gap) + width / 2, y: bounds.midY)
            bar.cornerRadius = width / 2
        }
        CATransaction.commit()
    }

    func update(isPlaying: Bool, color: NSColor) {
        bars.forEach { $0.backgroundColor = color.cgColor }
        guard isPlaying != self.isPlaying else { return }
        self.isPlaying = isPlaying

        for (i, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: "bounce")
            if isPlaying {
                bar.transform = CATransform3DIdentity
                let bounce = CABasicAnimation(keyPath: "transform.scale.y")
                bounce.fromValue = 0.35
                bounce.toValue = 1.0
                bounce.duration = durations[i]
                bounce.autoreverses = true
                bounce.repeatCount = .infinity
                bounce.timeOffset = Double(i) * 0.11
                bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bar.add(bounce, forKey: "bounce")
            } else {
                bar.transform = CATransform3DMakeScale(1, 0.22, 1)
            }
        }
    }
}

/// Playback position bar. Click or drag to seek.
struct ProgressBar: View {
    let progress: Double
    let tint: Color
    let onSeek: (Double) -> Void

    @State private var dragProgress: Double?
    @State private var hovering = false

    private let knob: CGFloat = 11

    var body: some View {
        GeometryReader { geo in
            let value = min(max(dragProgress ?? progress, 0), 1)
            let active = hovering || dragProgress != nil
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(active ? 0.22 : 0.15))
                Capsule().fill(tint).frame(width: geo.size.width * value)
            }
            .frame(height: active ? 6 : 4)
            // An overlay so the knob doesn't stretch the bar to its height.
            .overlay(alignment: .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .scaleEffect(active ? 1 : 0.2)
                    .opacity(active ? 1 : 0)
                    .offset(x: geo.size.width * value - knob / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        dragProgress = min(max(drag.location.x / geo.size.width, 0), 1)
                    }
                    .onEnded { drag in
                        onSeek(min(max(drag.location.x / geo.size.width, 0), 1))
                        dragProgress = nil
                    }
            )
            .onPointerHover(pointer: true) { hovering = $0 }
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: active)
        }
        .frame(height: 14)
    }
}

/// Round icon button: a soft circle grows in behind the icon on hover and the
/// icon dips when pressed.
struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.85))
                .frame(width: size + 18, height: size + 18)
                .background(
                    Circle()
                        .fill(.white.opacity(hovering ? 0.13 : 0))
                        .scaleEffect(hovering ? 1 : 0.6)
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .scaleEffect(hovering ? 1.08 : 1)
        .onPointerHover(pointer: true) { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Artwork that opens the playing app when clicked; hints at that on hover.
struct OpenAppArtwork: View {
    let image: NSImage?
    let size: CGFloat
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        ArtworkView(image: image, size: size, cornerRadius: 12)
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.black.opacity(hovering ? 0.35 : 0))
                    Image(systemName: "arrow.up.forward.app.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .scaleEffect(hovering ? 1 : 0.6)
                        .opacity(hovering ? 1 : 0)
                }
            }
            .scaleEffect(hovering ? 1.05 : 1)
            .shadow(color: .black.opacity(hovering ? 0.5 : 0), radius: 8, y: 3)
            .onTapGesture(perform: action)
            .onPointerHover(pointer: true) { hovering = $0 }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
    }
}

/// A label followed directly by trailing content (e.g. buttons): the label
/// takes only the width it needs, shrinking (and truncating) only when the
/// trailing content would otherwise run out of room.
struct HuggingRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (label, trailing) = sizes(proposal: proposal, subviews: subviews)
        return CGSize(width: label.width + spacing + trailing.width, height: max(label.height, trailing.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (label, trailing) = sizes(proposal: proposal, subviews: subviews)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(label))
        subviews[1].place(at: CGPoint(x: bounds.minX + label.width + spacing, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(trailing))
    }

    private func sizes(proposal: ProposedViewSize, subviews: Subviews) -> (label: CGSize, trailing: CGSize) {
        precondition(subviews.count == 2, "HuggingRow takes a label and trailing content")
        let trailing = subviews[1].sizeThatFits(.unspecified)
        let room = max(0, (proposal.width ?? .infinity) - trailing.width - spacing)
        let label = subviews[0].sizeThatFits(ProposedViewSize(width: room, height: proposal.height))
        return (label, trailing)
    }
}

func formatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "--:--" }
    let total = Int(seconds)
    if total >= 3600 {
        return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
    return String(format: "%d:%02d", total / 60, total % 60)
}
