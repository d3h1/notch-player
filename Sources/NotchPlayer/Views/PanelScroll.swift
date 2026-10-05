import SwiftUI

/// Vertical scrolling driven by the panel's own scroll events.
///
/// Not a ScrollView: AppKit's scroll view ignores the first click while the
/// panel isn't focused, and focusing the panel would take typing away from
/// the app being used.
struct PanelScroll<Content: View>: View {
    /// Extra width on each side for rows that pad themselves for a hover
    /// highlight, so the clip doesn't cut the highlight off.
    var bleed: CGFloat = 0
    /// Center the content vertically while it all fits.
    var centersWhenFits = false
    @ViewBuilder let content: Content

    @EnvironmentObject private var pointer: PointerState
    @State private var offset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var visibleFrame: CGRect = .zero

    private var maxOffset: CGFloat { max(0, contentHeight - visibleFrame.height) }

    var body: some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            .offset(y: -offset)
            // minHeight 0: take the space offered, not the content's height.
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity,
                   alignment: centersWhenFits && maxOffset == 0 ? .leading : .topLeading)
            .clipped()
            // Fade the edges where there's more to scroll to.
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: offset > 0.5 ? 12 : 0)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: offset < maxOffset - 0.5 ? 14 : 0)
                }
            }
            .environment(\.hoverClip, visibleFrame)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(PanelSpace.name)) } action: { visibleFrame = $0 }
            .padding(.horizontal, -bleed)
            .onReceive(pointer.scrolled) { delta in
                guard let location = pointer.location, visibleFrame.contains(location) else { return }
                offset = min(max(offset - delta, 0), maxOffset)
            }
            .onChange(of: contentHeight) { offset = min(offset, maxOffset) }
    }
}
