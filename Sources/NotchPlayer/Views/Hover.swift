import AppKit
import SwiftUI

/// Where the pointer is over the open panel.
///
/// SwiftUI's `onHover` (and AppKit tracking areas in general) never fire in
/// this panel because the app is never active, so hover is driven by the
/// controller's mouse monitors instead.
final class PointerState: ObservableObject {
    /// Pointer position in the panel's top-left coordinate space, or nil when
    /// it isn't over the open panel.
    @Published var location: CGPoint?
    /// Areas that show the pointing-hand cursor, reported by the views.
    var handFrames: [CGRect] = []
}

extension View {
    /// Calls `action` when the pointer enters or leaves this view.
    /// With `pointer: true` the pointing-hand cursor shows while inside.
    func onPointerHover(pointer: Bool = false, perform action: @escaping (Bool) -> Void) -> some View {
        modifier(PointerHoverModifier(showsHand: pointer, action: action))
    }
}

private struct PointerHoverModifier: ViewModifier {
    let showsHand: Bool
    let action: (Bool) -> Void

    @EnvironmentObject private var pointer: PointerState
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        let inside = pointer.location.map { frame.contains($0) } ?? false
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(PanelSpace.name)) } action: { frame = $0 }
            .preference(key: HandFramesKey.self, value: showsHand && frame != .zero ? [frame] : [])
            .onChange(of: inside) { _, isInside in action(isInside) }
    }
}

enum PanelSpace {
    static let name = "panel"
}

struct HandFramesKey: PreferenceKey {
    static let defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

/// Lets the app change the cursor while another app is active. Uses a private
/// WindowServer connection property; if it's unavailable the cursor simply
/// stays an arrow.
enum BackgroundCursor {
    static func enable() {
        typealias DefaultConnection = @convention(c) () -> Int32
        typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

        guard let handle = dlopen(nil, RTLD_LAZY),
              let connectionSymbol = dlsym(handle, "_CGSDefaultConnection"),
              let setSymbol = dlsym(handle, "CGSSetConnectionProperty") else {
            NSLog("NotchPlayer: background cursor API unavailable")
            return
        }
        let connection = unsafeBitCast(connectionSymbol, to: DefaultConnection.self)()
        let setProperty = unsafeBitCast(setSymbol, to: SetProperty.self)
        let error = setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        if error != 0 {
            NSLog("NotchPlayer: could not enable background cursor (%d)", error)
        }
    }
}
