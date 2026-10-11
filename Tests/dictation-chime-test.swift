import Foundation

@main
@MainActor
struct DictationChimeTest {
    static func main() {
        testToggleOffNeverBuildsASound()
        testToggleOnCachesOneSoundPerKind()
        testMissingResourceIsSilent()
        print("ALL PASSED")
    }

    private static func testToggleOffNeverBuildsASound() {
        let made = Recorder()
        let player = DictationChimePlayer(isEnabled: { false }, url: { _ in made.url() })
        player.playStart()
        player.playStop()
        expect(made.resolves == 0, "A disabled toggle is checked before any URL is resolved")
        expect(made.count == 0, "A disabled toggle never constructs a sound")
    }

    private static func testToggleOnCachesOneSoundPerKind() {
        let made = Recorder()
        final class Box: @unchecked Sendable {
            var enabled = true
        }
        let state = Box()
        let player = DictationChimePlayer(
            isEnabled: { state.enabled }, url: { _ in made.url() },
            makeSound: { _ in made.make() })
        player.playStart()
        player.playStart()
        player.playStop()
        player.playStop()
        player.playStop()
        expect(made.count == 2, "One sound per kind, reused across plays")
        expect(made.plays == 5, "Every play reaches its sound while enabled")
        state.enabled = false
        player.playStart()
        expect(made.plays == 5, "A later toggle-off silences playback")
    }

    private static func testMissingResourceIsSilent() {
        let made = Recorder()
        let player = DictationChimePlayer(
            isEnabled: { true }, url: { _ in nil }, // a missing bundle resource
            makeSound: { _ in made.make() })
        player.playStart()
        player.playStop()
        expect(made.count == 0, "A missing resource constructs nothing and never crashes")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        print("PASS  \(message)")
    }

    @MainActor
    private final class Recorder {
        var count = 0
        var plays = 0
        var resolves = 0
        func url() -> URL? {
            resolves += 1
            return URL(fileURLWithPath: "/tmp/chime.wav")
        }
        func make() -> any DictationChimeSound {
            count += 1
            return Stub { [weak self] in self?.plays += 1 }
        }
    }

    private struct Stub: DictationChimeSound {
        let onPlay: () -> Void
        var currentTime: TimeInterval {
            get { 0 }
            set {}
        }
        func prepareToPlay() -> Bool { true }
        func play() -> Bool { onPlay(); return true }
    }
}
