import AVFoundation

/// The dictation start/stop chimes. One cached sound per kind; a missing
/// resource or a disabled toggle turns playback into a no-op, never an error.
@MainActor
protocol DictationChiming: Sendable {
    func playStart()
    func playStop()
}

/// The one AVAudioPlayer surface playback needs, so tests need not subclass it.
@MainActor
protocol DictationChimeSound {
    var currentTime: TimeInterval { get set }
    func prepareToPlay() -> Bool
    func play() -> Bool
}

private struct AVAudioChimeSound: DictationChimeSound {
    let player: AVAudioPlayer
    var currentTime: TimeInterval {
        get { player.currentTime }
        set { player.currentTime = newValue }
    }
    func prepareToPlay() -> Bool { player.prepareToPlay() }
    func play() -> Bool { player.play() }
}

@MainActor
final class DictationChimePlayer: DictationChiming {
    enum Kind: CaseIterable {
        case start, stop
    }

    private let isEnabled: @Sendable () -> Bool
    private let url: @MainActor (Kind) -> URL?
    private let makeSound: @MainActor (URL) -> (any DictationChimeSound)?
    private var sounds = [Kind: any DictationChimeSound]()

    init(
        isEnabled: @escaping @Sendable () -> Bool,
        url: @escaping @MainActor (Kind) -> URL? = { kind in
            let name = kind == .start ? "dictation-start" : "dictation-stop"
            return Bundle.main.url(forResource: name, withExtension: "wav")
        },
        makeSound: @escaping @MainActor (URL) -> (any DictationChimeSound)? = { url in
            guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
            return AVAudioChimeSound(player: player)
        }
    ) {
        self.isEnabled = isEnabled
        self.url = url
        self.makeSound = makeSound
    }

    func playStart() { play(.start) }
    func playStop() { play(.stop) }

    private func play(_ kind: Kind) {
        guard isEnabled(), let url = url(kind) else { return }
        var sound: any DictationChimeSound
        if let cached = sounds[kind] {
            sound = cached
        } else {
            guard let made = makeSound(url) else { return }
            made.prepareToPlay()
            sounds[kind] = made
            sound = made
        }
        sound.currentTime = 0
        _ = sound.play()
    }
}
