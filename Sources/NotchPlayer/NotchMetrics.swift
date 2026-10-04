import AppKit

/// Size of the physical notch (or a stand-in on screens without one) and the
/// sizes the overlay grows into.
struct NotchMetrics: Equatable {
    var notchWidth: CGFloat = 185
    var notchHeight: CGFloat = 32
    var hasNotch = false

    /// Radius of the concave curves where the shape meets the top edge.
    let ear: CGFloat = 6

    /// Extra width on each side of the notch while something is playing.
    var wing: CGFloat { notchHeight + 8 }

    /// Wider wings for a volume, battery or speaker alert.
    func wing(for activity: NotchActivity) -> CGFloat {
        switch activity {
        case .audioOutput: notchHeight * 2 + 52
        default: notchHeight * 2 + 16
        }
    }

    func closedSize(wing: CGFloat) -> CGSize {
        CGSize(width: notchWidth + 2 * ear + 2 * wing, height: notchHeight)
    }

    /// The sidebar (weather, calendar) sits to the right of the player.
    func expandedSize(hasMedia: Bool, hasSidebar: Bool) -> CGSize {
        if hasSidebar {
            return CGSize(width: max(640, notchWidth + 2 * ear + 420), height: notchHeight + 112)
        }
        return CGSize(width: max(460, notchWidth + 2 * ear + 240),
                      height: notchHeight + (hasMedia ? 112 : 52))
    }

    init() {}

    init(screen: NSScreen) {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            notchWidth = screen.frame.width - left.width - right.width
            notchHeight = screen.safeAreaInsets.top
            hasNotch = true
        } else {
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            notchHeight = menuBar > 0 ? menuBar : 24
        }
    }

    /// The built-in display if it has a notch, otherwise the main display.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }
}
