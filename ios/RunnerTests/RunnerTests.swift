import Flutter
import UIKit
import AVFoundation
import AppIntents
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  @MainActor
  private func makePlaybackHarness() -> (HiCarAudioPlayer, PlaybackHarness, UserDefaults) {
    let suite = "hicar-playback-test-\(UUID().uuidString)"
    let prefs = UserDefaults(suiteName: suite)!
    prefs.set("test-token", forKey: "flutter.auth_token")
    // The factory below supplies audio; use an existing path to exercise resolution.
    prefs.set(Bundle.main.bundlePath, forKey: "flutter.greeting_audio_path")
    let harness = PlaybackHarness()
    let controller = HiCarAudioPlayer(environment: harness.environment(), prefs: prefs,
                                      observeNotifications: false)
    addTeardownBlock { @MainActor in
      controller.stop()
      prefs.removePersistentDomain(forName: suite)
    }
    return (controller, harness, prefs)
  }

  @MainActor
  func testRefusedStartsEventuallyPlayWithoutExhaustingDecoderRetries() async {
    let (controller, harness, _) = makePlaybackHarness()
    harness.refusedStarts = 5
    let result = await controller.playWhenRouteReady(type: "greeting")
    XCTAssertEqual(result, .started)
    XCTAssertEqual(harness.created, 6)
    XCTAssertEqual(harness.waits, 5)
    XCTAssertEqual(harness.activations, 6)
    XCTAssertEqual(harness.releases, 6) // begin() + five refused starts
    XCTAssertEqual(controller.status()["state"] as? String, "playing")
    XCTAssertTrue(harness.players.dropLast().allSatisfy { $0.stopped })
  }

  @MainActor
  func testNewGreetingReplacesWaitingJobWithoutOldWaiterStoppingIt() async {
    let (controller, harness, prefs) = makePlaybackHarness()
    harness.refusedStarts = 1
    var replacement: IOSPlaybackOutcome?
    harness.onWait = {
      harness.onWait = nil
      controller.stop()
      replacement = await controller.playWhenRouteReady(type: "greeting")
    }
    let result = await controller.playWhenRouteReady(type: "greeting")
    XCTAssertEqual(result, .cancelled)
    XCTAssertEqual(replacement, .started)
    XCTAssertEqual(controller.status()["state"] as? String, "playing")
    XCTAssertNotNil(prefs.string(forKey: "hicar_ios_pending_playback"))
    XCTAssertFalse(harness.players.last!.stopped)
  }

  @MainActor
  func testPrepareRefusalsDoNotCallPlayOrExhaustRetries() async {
    let (controller, harness, _) = makePlaybackHarness()
    harness.refusedPrepares = 4
    let result = await controller.playWhenRouteReady(type: "greeting")
    XCTAssertEqual(result, .started)
    XCTAssertEqual(harness.created, 5)
    XCTAssertTrue(harness.players.dropLast().allSatisfy { $0.playCalls == 0 && $0.stopped })
  }

  @MainActor
  func testMissingRouteAndSessionWaitThenStart() async {
    let (controller, harness, _) = makePlaybackHarness()
    harness.activationFailures = 4
    harness.routeReady = false
    harness.onWait = {
      if harness.waits == 7 { harness.routeReady = true }
    }
    let result = await controller.playWhenRouteReady(type: "greeting")
    XCTAssertEqual(result, .started)
    XCTAssertEqual(harness.created, 1)
    XCTAssertEqual(harness.waits, 7)
  }

  @MainActor
  func testDuplicateShortcutIsPendingAndStopCancelsOriginal() async {
    let (controller, harness, _) = makePlaybackHarness()
    harness.refusedStarts = 100
    var duplicate: IOSPlaybackOutcome?
    harness.onWait = {
      duplicate = await controller.playWhenRouteReady(type: "greeting")
      controller.stop()
    }
    let result = await controller.playWhenRouteReady(type: "greeting")
    XCTAssertEqual(result, .cancelled)
    XCTAssertEqual(duplicate, .pending)
    XCTAssertEqual(harness.created, 1)
  }

  @MainActor
  func testCancelledShortcutStopsWaiting() async {
    let (controller, harness, _) = makePlaybackHarness()
    harness.refusedStarts = 100
    harness.onWait = { withUnsafeCurrentTask { $0?.cancel() } }
    let task = Task { await controller.playWhenRouteReady(type: "greeting") }
    let result = await task.value
    XCTAssertEqual(result, .cancelled)
    XCTAssertEqual(harness.created, 1)
  }

  @MainActor
  func testDecoderFailureIsBoundedAndDoesNotClaimMissingGreeting() async {
    let (controller, harness, _) = makePlaybackHarness()
    harness.decoderFailure = true
    let result = await controller.playWhenRouteReady(type: "greeting")
    XCTAssertEqual(result, .failed)
    XCTAssertEqual(harness.created, 3)
    XCTAssertFalse(result.message(type: "greeting").contains("Chưa cài"))
  }

  @MainActor
  func testMissingConfigurationAndDisabledAutomationAreDistinct() async {
    let (controller, harness, prefs) = makePlaybackHarness()
    prefs.removeObject(forKey: "flutter.greeting_audio_path")
    let missing = await controller.playWhenRouteReady(type: "greeting")
    XCTAssertEqual(missing, .notConfigured)
    prefs.set(false, forKey: "flutter.auto_play_enabled")
    let disabled = await controller.playWhenRouteReady(type: "greeting")
    XCTAssertEqual(disabled, .disabled)
    XCTAssertEqual(harness.created, 0)
  }

  @available(iOS 17.0, *)
  func testShortcutsDeclareAudioPlayback() {
    func acceptsPlayback<T: AudioPlaybackIntent>(_ intent: T) {}
    acceptsPlayback(PlayGreetingIntent())
    acceptsPlayback(PlayGoodbyeIntent())
    XCTAssertFalse(PlayGreetingIntent.openAppWhenRun)
    XCTAssertFalse(PlayGoodbyeIntent.openAppWhenRun)
  }

  func testOldShortcutCannotOwnNewManualPlayback() {
    var lease = IOSPlaybackLease()
    let old = lease.begin()
    let new = lease.begin()
    XCTAssertFalse(lease.owns(old))
    XCTAssertTrue(lease.owns(new))
  }

  func testReadinessWaitingDoesNotExhaustDecoderBudget() {
    var lease = IOSPlaybackLease()
    let token = lease.begin()
    for _ in 0..<34560 { XCTAssertTrue(lease.owns(token)) }
    XCTAssertEqual(lease.retries, 0)
    XCTAssertTrue(lease.retry(token))
    XCTAssertTrue(lease.retry(token))
    XCTAssertFalse(lease.retry(token))
  }

  func testStopInvalidatesPendingShortcutAndCallbacks() {
    var lease = IOSPlaybackLease()
    let token = lease.begin()
    lease.end()
    XCTAssertFalse(lease.owns(token))
    XCTAssertFalse(lease.retry(token))
  }

  @MainActor
  func testContainerPathFallbackUsesActualAudioDirectory() throws {
    let defaults = UserDefaults.standard
    let key = "flutter.greeting_audio_path"
    let previous = defaults.object(forKey: key)
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let dir = docs.appendingPathComponent("hicar_audio")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("test-\(UUID().uuidString).mp3")
    try Data([73, 68, 51]).write(to: file)
    defer {
      try? FileManager.default.removeItem(at: file)
      if let previous = previous { defaults.set(previous, forKey: key) }
      else { defaults.removeObject(forKey: key) }
    }
    defaults.set("/old-container/Documents/hicar_audio/\(file.lastPathComponent)", forKey: key)
    XCTAssertEqual(HiCarAudioPlayer.shared.resolvePath(for: "greeting"), file.path)
  }

  func testDiagnosticLogPersistsWithoutFlutterAndRedactsToken() {
    let before = UserDefaults.standard.object(forKey: "hicar_ios_diagnostics")
    defer {
      if let before = before { UserDefaults.standard.set(before, forKey: "hicar_ios_diagnostics") }
      else { HiCarIOSLog.clear() }
    }
    HiCarIOSLog.clear()
    HiCarIOSLog.write("E", "mode=ios_carplay Bearer secret-token")
    XCTAssertEqual(HiCarIOSLog.lines().count, 1)
    XCTAssertTrue(HiCarIOSLog.lines()[0].contains("E HiCarIOS"))
    XCTAssertFalse(HiCarIOSLog.lines()[0].contains("secret-token"))
  }

}

private final class FakeAudioPlayer: IOSAudioPlaying {
  weak var delegate: AVAudioPlayerDelegate?
  var currentTime: TimeInterval = 0
  var duration: TimeInterval = 80
  var volume: Float = 1
  var prepared = true
  var starts = true
  var stopped = false
  var playCalls = 0
  func prepareToPlay() -> Bool { prepared }
  func play() -> Bool { playCalls += 1; return starts }
  func pause() {}
  func stop() { stopped = true }
}

@MainActor
private final class PlaybackHarness {
  var refusedStarts = 0
  var refusedPrepares = 0
  var activationFailures = 0
  var routeReady = true
  var decoderFailure = false
  var created = 0
  var waits = 0
  var activations = 0
  var releases = 0
  var players: [FakeAudioPlayer] = []
  var onWait: (() async -> Void)?

  func environment() -> IOSPlaybackEnvironment {
    IOSPlaybackEnvironment(
      configure: {},
      activate: {
        self.activations += 1
        if self.activations <= self.activationFailures {
          throw NSError(domain: "TestSession", code: 1)
        }
      },
      deactivate: { self.releases += 1 },
      hasCarRoute: { self.routeReady },
      protectedDataAvailable: { true },
      makePlayer: { _ in
        self.created += 1
        if self.decoderFailure { throw NSError(domain: NSOSStatusErrorDomain, code: -1) }
        let player = FakeAudioPlayer()
        player.prepared = self.created > self.refusedPrepares
        player.starts = self.created > self.refusedStarts
        self.players.append(player)
        return player
      },
      wait: {
        self.waits += 1
        // Fail fast if a regression makes a supposedly bounded test wait forever.
        if self.waits > 20 { throw CancellationError() }
        await self.onWait?()
      })
  }
}
