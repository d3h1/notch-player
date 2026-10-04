import AppKit

/// Streams system-wide Now Playing info through mediaremote-adapter.
///
/// Since macOS 15.4 only Apple-signed processes may read MediaRemote, so the
/// adapter runs inside /usr/bin/perl and prints JSON lines we parse here.
final class NowPlayingService: ObservableObject {
    enum Command: Int {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accentColor = NSColor.white
    @Published private(set) var sourceName: String?
    @Published private(set) var sourceIcon: NSImage?

    // Players report elapsed time as a snapshot: `elapsedAtTimestamp` seconds
    // in, measured at `timestamp`. The current position is extrapolated.
    @Published private var elapsedAtTimestamp: TimeInterval = 0
    @Published private var timestamp = Date()
    private var playbackRate: Double = 1

    private var sourceBundleID: String?
    private var sourceAppURL: URL?

    var hasMedia: Bool { !title.isEmpty }

    private let perl = URL(fileURLWithPath: "/usr/bin/perl")
    private let scriptPath: String
    private let frameworkPath: String
    private var process: Process?
    private var isStopping = false
    private var buffer = Data()
    private var state: [String: Any] = [:]

    init(bundle: Bundle = .main) {
        scriptPath = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl")?.path ?? ""
        frameworkPath = bundle.privateFrameworksURL?
            .appendingPathComponent("MediaRemoteAdapter.framework").path ?? ""
    }

    // MARK: - Stream

    func start() {
        guard process == nil else { return }
        guard FileManager.default.fileExists(atPath: scriptPath),
              FileManager.default.fileExists(atPath: frameworkPath) else {
            NSLog("NotchPlayer: mediaremote-adapter is missing from the app bundle")
            return
        }

        let process = Process()
        process.executableURL = perl
        process.arguments = [scriptPath, frameworkPath, "stream", "--micros", "--debounce=50"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                self?.consume(data)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                NSLog("NotchPlayer adapter: %@", String(decoding: data, as: UTF8.self))
            }
        }
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async { self?.adapterExited(finished) }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            NSLog("NotchPlayer: could not start adapter: %@", error.localizedDescription)
        }
    }

    func stop() {
        isStopping = true
        process?.terminate()
        process = nil
    }

    private func adapterExited(_ finished: Process) {
        guard finished === process else { return }
        process = nil
        NSLog("NotchPlayer: adapter exited with status %d", finished.terminationStatus)
        // A non-zero exit means the adapter is broken on this macOS version;
        // retrying won't help. Anything else (e.g. killed) is worth a restart.
        guard !isStopping,
              finished.terminationReason == .uncaughtSignal || finished.terminationStatus == 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.start() }
    }

    /// Runs on the pipe's background queue: splits stdout into JSON lines and
    /// decodes artwork before handing updates to the main thread.
    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = message["payload"] as? [String: Any] else { continue }
            let isDiff = message["diff"] as? Bool ?? false
            let artwork = ArtworkUpdate(payload: payload, isDiff: isDiff)
            DispatchQueue.main.async { self.apply(payload, isDiff: isDiff, artwork: artwork) }
        }
    }

    private func apply(_ payload: [String: Any], isDiff: Bool, artwork update: ArtworkUpdate) {
        if isDiff {
            for (key, value) in payload {
                state[key] = value is NSNull ? nil : value
            }
        } else {
            state = payload
        }
        state["artworkData"] = nil

        title = state["title"] as? String ?? ""
        artist = state["artist"] as? String ?? ""
        album = state["album"] as? String ?? ""
        isPlaying = state["playing"] as? Bool ?? false
        duration = Self.seconds(state["durationMicros"])
        elapsedAtTimestamp = Self.seconds(state["elapsedTimeMicros"])
        timestamp = (state["timestampEpochMicros"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue / 1_000_000) } ?? Date()
        playbackRate = (state["playbackRate"] as? NSNumber)?.doubleValue ?? 1
        updateSource(state["parentApplicationBundleIdentifier"] as? String
                     ?? state["bundleIdentifier"] as? String)

        switch update {
        case .unchanged:
            break
        case .cleared:
            artwork = nil
            accentColor = .white
        case let .image(image, color):
            artwork = image
            accentColor = color
        }
    }

    private static func seconds(_ micros: Any?) -> TimeInterval {
        ((micros as? NSNumber)?.doubleValue ?? 0) / 1_000_000
    }

    private func updateSource(_ bundleID: String?) {
        guard bundleID != sourceBundleID else { return }
        sourceBundleID = bundleID
        sourceAppURL = bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        sourceIcon = sourceAppURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
        sourceName = sourceAppURL.map {
            let name = FileManager.default.displayName(atPath: $0.path)
            return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        }
    }

    // MARK: - Playback

    func elapsed(at date: Date = Date()) -> TimeInterval {
        var value = elapsedAtTimestamp
        if isPlaying {
            value += date.timeIntervalSince(timestamp) * (playbackRate > 0 ? playbackRate : 1)
        }
        return duration > 0 ? min(max(value, 0), duration) : max(value, 0)
    }

    func togglePlayPause() {
        // Update right away; the stream confirms a moment later.
        let now = Date()
        elapsedAtTimestamp = elapsed(at: now)
        timestamp = now
        isPlaying.toggle()
        send(.togglePlayPause)
    }

    func seek(to seconds: TimeInterval) {
        elapsedAtTimestamp = seconds
        timestamp = Date()
        run(["seek", String(Int(seconds * 1_000_000))])
    }

    func send(_ command: Command) {
        run(["send", String(command.rawValue)])
    }

    func openSourceApp() {
        guard let url = sourceAppURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func run(_ arguments: [String]) {
        guard !scriptPath.isEmpty else { return }
        let process = Process()
        process.executableURL = perl
        process.arguments = [scriptPath, frameworkPath] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

private enum ArtworkUpdate {
    case unchanged
    case cleared
    case image(NSImage, NSColor)

    init(payload: [String: Any], isDiff: Bool) {
        if let base64 = payload["artworkData"] as? String,
           let data = Data(base64Encoded: base64),
           let image = NSImage(data: data) {
            self = .image(image, image.accentColor())
        } else if !isDiff || payload["artworkData"] is NSNull {
            self = .cleared
        } else {
            self = .unchanged
        }
    }
}

private extension NSImage {
    /// Average color of the image, brightened so it reads on black.
    func accentColor() -> NSColor {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .white }
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return .white }

        var red = 0, green = 0, blue = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            red += Int(pixels[i])
            green += Int(pixels[i + 1])
            blue += Int(pixels[i + 2])
        }
        let total = CGFloat(side * side * 255)
        let average = NSColor(srgbRed: CGFloat(red) / total, green: CGFloat(green) / total,
                              blue: CGFloat(blue) / total, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: min(saturation * 1.3, 0.75),
                       brightness: max(brightness, 0.85), alpha: 1)
    }
}

#if DEBUG
extension NowPlayingService {
    /// Fake track for `--sample-data`, so the layout can be worked on without
    /// anything playing.
    func loadSample(title: String, artist: String, artwork: NSImage?, bundleID: String,
                    duration: TimeInterval, elapsed: TimeInterval) {
        self.title = title
        self.artist = artist
        self.artwork = artwork
        accentColor = artwork?.accentColor() ?? .white
        self.duration = duration
        elapsedAtTimestamp = elapsed
        timestamp = Date()
        isPlaying = true
        updateSource(bundleID)
    }
}
#endif
