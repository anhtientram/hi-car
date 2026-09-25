import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

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
