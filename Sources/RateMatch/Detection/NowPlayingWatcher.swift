import Foundation
import MediaRemoteAdapter

/// Signals when the Apple Music track changes. Used only as a trigger to know when to
/// re-check the sample rate — the rate itself comes from AppleMusicSampleRateDetector.
final class NowPlayingWatcher {
    private let controller = MediaController()
    private var lastIdentifier: String?

    /// Called with the new track's payload (for its title) when a new Apple Music track starts,
    /// or `nil` when Music stops being the active now-playing app.
    var onTrackChanged: ((TrackInfo.Payload?) -> Void)?

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
        guard let payload = trackInfo?.payload,
              payload.bundleIdentifier == "com.apple.Music",
              payload.isPlaying == true else {
            if lastIdentifier != nil {
                lastIdentifier = nil
                onTrackChanged?(nil)
            }
            return
        }

        let identifier = payload.uniqueIdentifier
        guard identifier != lastIdentifier else { return }
        lastIdentifier = identifier
        onTrackChanged?(payload)
    }
}
