import SwiftUI
import AVKit
import Combine

class PlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isBuffering: Bool = false
    @Published var errorMessage: String?
    @Published var currentURL: URL?

    @Published var isDelayedMode: Bool = false {
        didSet {
            applyDelayMode()
        }
    }

    @Published var isLiveStream: Bool = true // On assume Live par défaut (IPTV)

    // Suivi de la progression (pour la timeline / scrubber des VOD)
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying: Bool = false
    @Published var isScrubbing: Bool = false // true pendant qu'on déplace la timeline


    // Quality Selection: 0 = Auto. Bitrate in bits per second.
    @Published var selectedBitrate: Double = 0 {
        didSet {
            player?.currentItem?.preferredPeakBitRate = selectedBitrate
        }
    }

    // Vitesse de lecture (0.5x – 2.0x). Valeur par défaut : 1.0 (vitesse normale).
    @Published var playbackSpeed: Float = 1.0 {
        didSet {
            player?.rate = playbackSpeed
        }
    }

    var currentItem: AVPlayerItem? {
        player?.currentItem
    }

    private var timeControlObserver: NSKeyValueObservation?
    private var failedObserver: NSObjectProtocol?
    private var durationObserver: NSKeyValueObservation?
    private var periodicTimeObserver: Any?

    func startPlaying(url: URL) {
        self.stop() // Clear existing
        self.currentURL = url

        let headers: [String: String] = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
            "Referer": "\(url.scheme ?? "https")://\(url.host ?? "")/",
            "Origin": "\(url.scheme ?? "https")://\(url.host ?? "")/"
        ]

        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)

        failedObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] notification in
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                print("AVPlayerItem Error: \(error.localizedDescription)")
                self?.errorMessage = "Erreur de flux : \(error.localizedDescription)"
            }
        }

        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = true

        self.player = newPlayer

        timeControlObserver = newPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] p, _ in
            DispatchQueue.main.async {
                self?.isBuffering = p.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self?.isPlaying = p.timeControlStatus == .playing
            }
        }

        // Observateur périodique : met à jour la position et la durée pour la timeline.
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        periodicTimeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            // On ne touche pas à currentTime pendant que l'utilisateur déplace la timeline.
            if !self.isScrubbing {
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
            }
            if let dur = self.player?.currentItem?.duration, dur.isNumeric {
                self.duration = dur.seconds
            }
        }

        durationObserver = item.observe(\.duration, options: [.initial, .new]) { [weak self] pItem, _ in
            DispatchQueue.main.async {
                // Si la durée est indéfinie, c'est du Live, sinon c'est de la VOD.
                self?.isLiveStream = pItem.duration.isIndefinite
            }
        }

        // On configure seulement le buffer selon le mode, SANS forcer de seek au démarrage.
        // Un flux Live HLS démarre naturellement au live edge, et une VOD démarre à 0.
        // (Forcer seekToLive ici poussait une VOD jusqu'à sa toute fin avant la détection Live/VOD.)
        item.preferredForwardBufferDuration = isDelayedMode ? 120.0 : 10.0
        item.preferredPeakBitRate = selectedBitrate

        newPlayer.play()

        // Appliquer la vitesse de lecture après le démarrage
        if playbackSpeed != 1.0 {
            newPlayer.rate = playbackSpeed
        }
    }

    func applyDelayMode() {
        guard let item = currentItem else { return }
        if isDelayedMode {
            item.preferredForwardBufferDuration = 120.0 // 2 minutes de buffer forcé
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

            // Véritable algo de Différé (Timeshift) :
            // Pour être sûr de ne plus avoir 0 saccade sur un stream live, il ne suffit pas de pauser.
            // Il faut reculer la tête de lecture de ~45 secondes en arrière par rapport au direct (Live Edge).
            // Le lecteur a ainsi un gigantesque "matelas" de segments de 45 secondes déjà stockés.
            if let seekableRange = item.seekableTimeRanges.last?.timeRangeValue {
                let liveEnd = CMTimeAdd(seekableRange.start, seekableRange.duration)
                let delayedTime = CMTimeSubtract(liveEnd, CMTime(seconds: 45.0, preferredTimescale: 1)) // -45 sec

                // On s'assure qu'on ne cherche pas avant le début
                let targetTime = CMTimeCompare(delayedTime, seekableRange.start) > 0 ? delayedTime : seekableRange.start

                player?.pause()
                player?.seek(to: targetTime) { [weak self] _ in
                    // On laisse 1.5s au lecteur pour télécharger goulûment le gros bloc
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self?.player?.play()
                    }
                }
            } else {
                // S'il n'y a pas de DVR Window on utilise juste la pause standard
                player?.pause()
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    self.player?.play()
                }
            }
        } else {
            item.preferredForwardBufferDuration = 10.0 // Mode classique
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
            seekToLive()
        }
    }

    /// Va à une position absolue (en secondes), bornée à [0, durée].
    func seek(toSeconds seconds: Double, completion: ((Bool) -> Void)? = nil) {
        guard let player = player else { completion?(false); return }
        var target = seconds
        if duration > 0 { target = min(max(0, target), duration) } else { target = max(0, target) }
        let t = CMTime(seconds: target, preferredTimescale: 600)
        // Tolérance nulle = positionnement précis (essentiel pour un scrubber).
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            completion?(finished)
        }
    }

    /// Avance (delta > 0) ou recule (delta < 0) de `delta` secondes par rapport à la position actuelle.
    func skip(bySeconds delta: Double) {
        guard let player = player else { return }
        let current = player.currentTime().seconds
        let base = current.isFinite ? current : currentTime
        seek(toSeconds: base + delta)
    }

    func seekToLive() {
        guard let item = currentItem else { return }
        // Ne jamais sauter au "live edge" sur une VOD : ça l'enverrait à la fin de la vidéo.
        guard isLiveStream else { return }

        if let seekableRange = item.seekableTimeRanges.last?.timeRangeValue {
            // Aller presque à la toute fin du live edge
            let livePosition = CMTimeAdd(seekableRange.start, seekableRange.duration)
            player?.seek(to: livePosition)
        } else {
            // Fallback pour certains formats iptv qui n'ont pas de timerange explicite
            player?.seek(to: CMTime.positiveInfinity)
        }

        if player?.timeControlStatus != .playing {
            player?.play()
        }
    }

    func stop() {
        if let obs = periodicTimeObserver {
            player?.removeTimeObserver(obs)
            periodicTimeObserver = nil
        }
        player?.pause()
        player = nil
        currentURL = nil
        errorMessage = nil
        currentTime = 0
        duration = 0
        isPlaying = false
        isScrubbing = false
        timeControlObserver?.invalidate()
        durationObserver?.invalidate()
        if let obs = failedObserver {
            NotificationCenter.default.removeObserver(obs)
            failedObserver = nil
        }
    }
}
