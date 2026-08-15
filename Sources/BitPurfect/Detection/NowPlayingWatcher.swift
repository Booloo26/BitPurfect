import Foundation
import MediaRemoteAdapter

/// What currently owns the system's now-playing slot.
enum NowPlayingSource: Equatable {
    /// Apple Music is playing. The rate to match comes from the decoder log, not from here.
    case appleMusic(title: String?, artist: String?)
    /// Something else is playing — a browser, Spotify, a podcast, a video.
    case otherApp(name: String)
    /// Nothing is playing.
    case stopped

    var isPlaying: Bool { self != .stopped }
}

/// Reports which app is playing, via the MediaRemote bridge.
///
/// Only apps that publish now-playing information appear here, which is most media apps —
/// browsers included — but not system alert sounds or games. Those go undetected, so the rate
/// simply stays where it is for them.
final class NowPlayingWatcher {
    private let controller = MediaController()
    private var lastKey: String?

    /// Called on the main queue whenever the playing source changes.
    var onSourceChanged: ((NowPlayingSource) -> Void)?

    func start() {
        controller.onTrackInfoReceived = { [weak self] trackInfo in
            self?.handle(trackInfo)
        }
        controller.startListening()
    }

    func stop() {
        controller.stopListening()
    }

    private func handle(_ trackInfo: TrackInfo?) {
        let source = Self.classify(trackInfo)

        // Dedupe on a key rather than on the source itself: Apple Music re-sends the same track
        // repeatedly, and only a genuine change should reach the engine.
        let key: String
        switch source {
        case .appleMusic(let title, let artist): key = "music:\(title ?? "")-\(artist ?? "")"
        case .otherApp(let name): key = "other:\(name)"
        case .stopped: key = "stopped"
        }
        guard key != lastKey else { return }
        lastKey = key

        onSourceChanged?(source)
    }

    private static func classify(_ trackInfo: TrackInfo?) -> NowPlayingSource {
        guard let payload = trackInfo?.payload, payload.isPlaying == true else { return .stopped }

        if payload.bundleIdentifier == "com.apple.Music" {
            return .appleMusic(title: payload.title, artist: payload.artist)
        }

        let bundleID = payload.bundleIdentifier
        if let bundleID, let friendly = Self.friendlyNames[bundleID] {
            return .otherApp(name: friendly)
        }

        // Fall back through the fields most likely to carry something human-readable.
        let name = payload.applicationName
            ?? bundleID?.split(separator: ".").last.map(String.init)
            ?? "Another app"
        return .otherApp(name: name)
    }

    /// Some apps hand MediaRemote the name of an internal helper rather than their own. Safari
    /// is the notable one: play a video and now-playing reports `com.apple.WebKit.GPU`, whose
    /// application name is "Safari Graphics and Media" — accurate, and not what anyone calls it.
    private static let friendlyNames: [String: String] = [
        "com.apple.WebKit.GPU": "Safari",
        "com.apple.Safari": "Safari",
        "com.apple.WebKit.WebContent": "Safari"
    ]
}
