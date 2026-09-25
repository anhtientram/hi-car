import Flutter
import UIKit
import AVFoundation
import AppIntents

// MARK: - AppDelegate

@main
@objc class AppDelegate: FlutterAppDelegate {

  private let serviceChannelName = "com.hicar.ora.limited/service"
  private let bluetoothChannelName = "com.hicar.ora.limited/bluetooth"

  // Giữ tham chiếu mạnh để channel không bị giải phóng (mất handler).
  private var serviceChannel: FlutterMethodChannel?
  private var bluetoothChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Cấu hình phiên âm thanh ngay khi khởi động để sẵn sàng phát ra loa xe (CarPlay/Bluetooth).
    HiCarAudioPlayer.shared.configureSession()

    let didFinish = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if let controller = window?.rootViewController as? FlutterViewController {
      setupChannels(controller: controller)
    }

    return didFinish
  }

  /// Đăng ký các MethodChannel TRÙNG TÊN với Android để code Flutter (ServiceChannel /
  /// BluetoothChannel) chạy được trên iOS mà không cần đổi gì ở tầng Dart.
  private func setupChannels(controller: FlutterViewController) {
    let service = FlutterMethodChannel(
      name: serviceChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    serviceChannel = service
    HiCarAudioPlayer.shared.serviceChannel = service

    service.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "startService":
        HiCarAudioPlayer.shared.configureSession()
        result(true)
      case "stopService", "stopAudio":
        HiCarAudioPlayer.shared.stop()
        result(true)
      case "playGreeting":
        let path = (args?["audioPath"] as? String) ?? ""
        if path.isEmpty {
          result(HiCarAudioPlayer.shared.play(type: "greeting"))
        } else {
          result(HiCarAudioPlayer.shared.play(path: path, type: "greeting"))
        }
      case "retryGreeting":
        Task {
          result(await HiCarAudioPlayer.shared.playWhenRouteReady(type: "greeting"))
        }
      case "playGoodbye":
        let path = (args?["audioPath"] as? String) ?? ""
        if path.isEmpty {
          result(HiCarAudioPlayer.shared.play(type: "goodbye"))
        } else {
          result(HiCarAudioPlayer.shared.play(path: path, type: "goodbye"))
        }
      case "clearGreetingConfig":
        UserDefaults.standard.removeObject(forKey: "flutter.greeting_audio_path")
        result(true)
      case "clearGoodbyeConfig":
        UserDefaults.standard.removeObject(forKey: "flutter.goodbye_audio_path")
        result(true)
      // Các method chỉ có ý nghĩa trên Android → no-op để không ném MissingPluginException.
      case "getPlaybackStatus":
        result(HiCarAudioPlayer.shared.status())
      case "getDiagnosticLogFull":
        result(HiCarIOSLog.lines().joined(separator: "\n"))
      case "getDiagnosticLogErrors":
        result(HiCarIOSLog.lines().filter { $0.contains(" E HiCar") || $0.contains(" W HiCar") }.joined(separator: "\n"))
      case "hasDiagnosticErrors":
        result(HiCarIOSLog.lines().contains { $0.contains(" E HiCar") || $0.contains(" W HiCar") })
      case "clearDiagnosticLog":
        HiCarIOSLog.clear()
        result(true)
      case "clearAuthState":
        HiCarAudioPlayer.shared.stop()
        UserDefaults.standard.removeObject(forKey: "flutter.auth_token")
        result(true)
      case "syncPrefs", "minimizeApp", "openApp", "showAutostartSettings":
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Bluetooth là cơ chế của Android (quét/ghép nối thủ công). Trên iOS việc định tuyến
    // âm thanh ra xe do hệ thống lo, nên các method này chỉ trả về giá trị trung tính.
    let bluetooth = FlutterMethodChannel(
      name: bluetoothChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    bluetoothChannel = bluetooth
    bluetooth.setMethodCallHandler { call, result in
      switch call.method {
      case "getPairedDevices":
        result([])
      case "setConnectionMode", "setTargetDevice", "clearTargetDevice":
        result(true)
      case "startDiscovery", "stopDiscovery", "connectDevice", "disconnectDevice":
        result(false)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

// MARK: - Audio Player

/// Quản lý phát lời chào/tạm biệt trên iOS bằng AVAudioPlayer.
/// - Phiên `.playback` + Background Audio → âm thanh phát ra loa xe khi nối CarPlay/Bluetooth,
///   và vẫn phát được khi app chạy nền (do App Intent/Shortcut kích hoạt).
/// - Đọc đường dẫn từ UserDefaults `flutter.greeting_audio_path` / `flutter.goodbye_audio_path`
///   (shared_preferences của Flutter lưu kèm tiền tố `flutter.`).
/// Testable ownership/retry policy shared by manual playback and both Shortcuts triggers.
struct IOSPlaybackLease {
  private(set) var generation = 0
  private(set) var retries = 0
  private(set) var active = false
  mutating func begin() -> Int { generation += 1; retries = 0; active = true; return generation }
  func owns(_ token: Int) -> Bool { active && token == generation }
  mutating func end() { active = false; generation += 1 }
  mutating func retry(_ token: Int) -> Bool {
    guard owns(token), retries < 2 else { return false }
    retries += 1
    return true
  }
}

enum HiCarIOSLog {
  private static let key = "hicar_ios_diagnostics"
  private static let criticalKey = "hicar_ios_critical_diagnostics"
  static func lines() -> [String] {
    var seen = Set<String>()
    return ((UserDefaults.standard.stringArray(forKey: criticalKey) ?? []) +
      (UserDefaults.standard.stringArray(forKey: key) ?? [])).filter { seen.insert($0).inserted }
  }
  static func clear() {
    UserDefaults.standard.removeObject(forKey: key)
    UserDefaults.standard.removeObject(forKey: criticalKey)
  }
  static func write(_ level: String, _ message: String) {
    let safe = message.replacingOccurrences(of: "(?i)(bearer\\s+)[^\\s,]+", with: "$1[redacted]", options: .regularExpression)
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(level) HiCarIOS: \(safe) uptime=\(ProcessInfo.processInfo.systemUptime)"
    var entries = UserDefaults.standard.stringArray(forKey: key) ?? []
    entries.append(line)
    UserDefaults.standard.set(Array(entries.suffix(1000)), forKey: key)
    if level == "E" || message.contains("state=completed") || message.contains("state=cancelled") {
      var critical = UserDefaults.standard.stringArray(forKey: criticalKey) ?? []
      critical.append(line)
      UserDefaults.standard.set(Array(critical.suffix(200)), forKey: criticalKey)
    }
    NSLog("%@", line)
  }
}

@MainActor
final class HiCarAudioPlayer: NSObject, AVAudioPlayerDelegate {
  static let shared = HiCarAudioPlayer()
  var serviceChannel: FlutterMethodChannel?
  private var player: AVAudioPlayer?
  private var lease = IOSPlaybackLease()
  private var recoveryTask: Task<Void, Never>?
  private var loopID = 0
  private var progressTimer: Timer?
  private var jobID = ""
  private var type = "greeting"
  private var state = "idle"
  private var automatic = false
  private var jobPath: String?
  private var position: TimeInterval = 0
  private var duration: TimeInterval = 0
  private var interrupted = false
  private let pendingKey = "hicar_ios_pending_playback"

  private override init() {
    super.init()
    if let old = UserDefaults.standard.string(forKey: pendingKey) {
      HiCarIOSLog.write("E", "mode=ios_carplay job=\(old) state=failed PROCESS_INTERRUPTED before completion")
      UserDefaults.standard.removeObject(forKey: pendingKey)
    }
    NotificationCenter.default.addObserver(self, selector: #selector(onInterruption(_:)),
      name: AVAudioSession.interruptionNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(onMediaReset),
      name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(onRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification, object: nil)
  }

  private func log(_ level: String, _ text: String) {
    let session = AVAudioSession.sharedInstance()
    let routes = session.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")
    HiCarIOSLog.write(level, "job=\(jobID) mode=ios_carplay state=\(state) type=\(type) automatic=\(automatic) retry=\(lease.retries) position=\(position) routes=\(routes) os=\(UIDevice.current.systemVersion) \(text)")
  }

  func status() -> [String: Any] {
    ["jobId": jobID, "state": state, "type": type,
     "positionMs": Int((player?.currentTime ?? position) * 1000), "durationMs": Int(duration * 1000)]
  }

  func configureSession() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
    } catch { log("E", "SESSION_CATEGORY \(error as NSError)") }
  }

  private func begin(type: String, automatic: Bool, path: String?) -> Int {
    stop()
    let token = lease.begin()
    self.type = type
    self.automatic = automatic
    jobPath = path
    position = 0
    duration = 0
    jobID = UUID().uuidString
    state = "waiting_route"
    UserDefaults.standard.set(jobID, forKey: pendingKey)
    log("D", "trigger")
    notifyFlutter("onPlaybackPending", arguments: type)
    return token
  }

  private func valid(_ token: Int) -> Bool {
    let prefs = UserDefaults.standard
    return lease.owns(token) &&
      !(prefs.string(forKey: "flutter.auth_token") ?? "").isEmpty &&
      (!automatic || (prefs.object(forKey: "flutter.auto_play_enabled") as? Bool ?? true))
  }

  @discardableResult
  func play(type: String) -> Bool {
    guard let path = resolvePath(for: type) else {
      _ = begin(type: type, automatic: false, path: nil)
      fail("FILE_INVALID no configured \(type)")
      return false
    }
    return play(path: path, type: type)
  }

  @discardableResult
  func play(path: String, type: String) -> Bool {
    let token = begin(type: type, automatic: false, path: path)
    guard valid(token) else { stop(); return false }
    guard FileManager.default.fileExists(atPath: path) else {
      fail("FILE_INVALID path=\(path)")
      return false
    }
    launchRecovery(token)
    return true // Accepted, not yet proof of audible playback.
  }

  func playWhenRouteReady(type: String) async -> Bool {
    if automatic && self.type == type && lease.active { return true }
    let token = begin(type: type, automatic: true, path: nil)
    return await waitAndPlay(token)
  }

  /// No fixed route timeout. iOS still controls the lifetime of a Shortcuts/background task.
  private func waitAndPlay(_ token: Int) async -> Bool {
    loopID += 1
    let thisLoop = loopID
    var waitCount = 0
    configureSession()
    while valid(token) && thisLoop == loopID && !Task.isCancelled {
      if interrupted {
        state = "waiting_focus"
      } else {
          do {
            try AVAudioSession.sharedInstance().setActive(true)
          } catch {
            state = "waiting_focus"
            if waitCount % 4 == 0 { log("W", "SESSION_WAIT \(error as NSError)") }
            do { try await Task.sleep(nanoseconds: 2_500_000_000) } catch { break }
            waitCount += 1
            continue
          }
        let path = jobPath ?? resolvePath(for: type)
        if let path = path, !automatic || hasCarRoute() {
          guard valid(token) && thisLoop == loopID && !Task.isCancelled else { break }
          do {
            let next = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            next.delegate = self
            next.prepareToPlay()
            if position > 0 && position < next.duration { next.currentTime = position }
            next.volume = 1
            player = next
            guard next.play() else { throw NSError(domain: "HiCarPlayback", code: 1,
              userInfo: [NSLocalizedDescriptionKey: "AVAudioPlayer.play returned false"]) }
            duration = next.duration
            state = "playing"
            startProgressTimer(token)
            log("D", "started duration=\(duration)")
            notifyFlutter("onPlaybackStarted", arguments: type)
            return true
          } catch {
            player?.stop()
            player = nil
            guard lease.retry(token) else { fail("PLAYBACK_FAILED \(error as NSError)"); return false }
            state = "retrying"
            log("E", "DECODER_RETRY \(error as NSError)")
          }
        } else {
          state = "waiting_route"
          if waitCount % 4 == 0 { log("W", "route_or_file_pending pathAvailable=\(path != nil)") }
        }
      }
      waitCount += 1
      do { try await Task.sleep(nanoseconds: 2_500_000_000) } catch { break }
    }
    if lease.owns(token) && thisLoop == loopID {
      if Task.isCancelled { fail("SHORTCUT_CANCELLED while pending") }
      else { stop() }
    }
    return false
  }

  private func launchRecovery(_ token: Int) {
    loopID += 1 // A cancelled older waiter must not stop its replacement.
    recoveryTask?.cancel()
    recoveryTask = Task { [weak self] in
      _ = await self?.waitAndPlay(token)
    }
  }

  private func startProgressTimer(_ token: Int) {
    progressTimer?.invalidate()
    progressTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self = self, self.lease.owns(token), self.state == "playing" else { return }
        self.position = self.player?.currentTime ?? self.position
      }
    }
  }

  private func hasCarRoute() -> Bool {
    let ports: Set<AVAudioSession.Port> = [.carAudio, .bluetoothA2DP, .bluetoothHFP]
    return AVAudioSession.sharedInstance().currentRoute.outputs.contains { ports.contains($0.portType) }
  }

  func stop() {
    let wasActive = lease.active
    lease.end() // Invalidate callbacks/tasks before releasing the old player.
    loopID += 1
    progressTimer?.invalidate()
    progressTimer = nil
    recoveryTask?.cancel()
    recoveryTask = nil
    player?.stop()
    player = nil
    interrupted = false
    if wasActive {
      state = "cancelled"
      log("D", "explicit_stop_or_replaced")
      notifyFlutter("onPlaybackFailed", arguments: nil)
      notifyFlutter("onPlaybackResolved", arguments: jobID)
    }
    UserDefaults.standard.removeObject(forKey: pendingKey)
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
  }

  private func fail(_ reason: String) {
    state = "failed"
    log("E", reason)
    lease.end()
    progressTimer?.invalidate()
    progressTimer = nil
    player?.stop()
    player = nil
    UserDefaults.standard.removeObject(forKey: pendingKey)
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    notifyFlutter("onPlaybackFailed", arguments: nil)
    notifyFlutter("onNativeError", arguments: "PLAYBACK_FAILED job=\(jobID) mode=ios_carplay \(reason)")
  }

  /// Old absolute iOS container paths need a fallback in the actual hicar_audio directory.
  func resolvePath(for type: String) -> String? {
    let key = type == "greeting" ? "flutter.greeting_audio_path" : "flutter.goodbye_audio_path"
    guard let stored = UserDefaults.standard.string(forKey: key), !stored.isEmpty else { return nil }
    if FileManager.default.fileExists(atPath: stored) { return stored }
    let name = (stored as NSString).lastPathComponent
    if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
      for candidate in [docs.appendingPathComponent("hicar_audio").appendingPathComponent(name),
                        docs.appendingPathComponent(name)] {
        if FileManager.default.fileExists(atPath: candidate.path) { return candidate.path }
      }
    }
    return nil
  }

  private func notifyFlutter(_ method: String, arguments: Any?) {
    serviceChannel?.invokeMethod(method, arguments: arguments)
  }

  @objc private func onInterruption(_ note: Notification) {
    guard lease.active,
      let value = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      let event = AVAudioSession.InterruptionType(rawValue: value) else { return }
    if event == .began {
      position = player?.currentTime ?? position
      player?.pause()
      interrupted = true
      state = "waiting_focus"
      log("W", "INTERRUPTION_BEGAN")
    } else {
      interrupted = false
      let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
      log("D", "INTERRUPTION_ENDED shouldResume=\(options.contains(.shouldResume))")
      if options.contains(.shouldResume) {
        player = nil
        launchRecovery(lease.generation)
      } else { stop() }
    }
  }

  @objc private func onMediaReset() {
    guard lease.active else { configureSession(); return }
    player = nil // AV objects are invalid after mediaservices reset.
    state = "retrying"
    let token = lease.generation
    log("E", "MEDIA_SERVICES_RESET")
    if lease.retry(token) { launchRecovery(token) } else { fail("MEDIA_SERVICES_RESET retries exhausted") }
  }

  @objc private func onRouteChange(_ note: Notification) {
    guard lease.active else { return }
    log("D", "ROUTE_CHANGED")
    if automatic && state == "playing" && !hasCarRoute() {
      stop() // Never fall back onto the iPhone speaker after the car disconnects.
    }
  }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor [weak self] in self?.finishPlaying(player, successfully: flag) }
  }

  private func finishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    guard self.player === player && lease.active else { return }
    guard flag else { decodeError(player, error: nil); return }
    position = duration
    state = "completed"
    log("D", "onCompletion")
    lease.end()
    progressTimer?.invalidate()
    progressTimer = nil
    self.player = nil
    UserDefaults.standard.removeObject(forKey: pendingKey)
    notifyFlutter("onPlaybackResolved", arguments: jobID)
    notifyFlutter("onPlaybackComplete", arguments: nil)
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
  }

  nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    Task { @MainActor [weak self] in self?.decodeError(player, error: error) }
  }

  private func decodeError(_ player: AVAudioPlayer, error: Error?) {
    guard self.player === player && lease.active else { return }
    position = player.currentTime
    self.player = nil
    state = "retrying"
    let token = lease.generation
    log("E", "DECODE_ERROR \(String(describing: error))")
    if lease.retry(token) { launchRecovery(token) } else { fail("DECODE_ERROR retries exhausted") }
  }
}

// MARK: - App Intents (Shortcuts) — iOS 16+

/// Hành động "Phát lời chào" để người dùng gắn vào Tự động hóa cá nhân
/// (Shortcuts → Tự động hóa → "Khi CarPlay kết nối" → Phát lời chào HiCar).
@available(iOS 16.0, *)
struct PlayGreetingIntent: AppIntent {
  static var title: LocalizedStringResource = "Phát lời chào HiCar"
  static var description = IntentDescription("Phát đoạn lời chào đã cấu hình trong ứng dụng HiCar.")
  static var openAppWhenRun: Bool = false

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let ok = await HiCarAudioPlayer.shared.playWhenRouteReady(type: "greeting")
    let message = ok
      ? "Đang phát lời chào."
      : "CarPlay/Bluetooth chưa sẵn sàng hoặc chưa có nhạc chào."
    return .result(dialog: "\(message)")
  }
}

/// Hành động "Phát lời tạm biệt".
@available(iOS 16.0, *)
struct PlayGoodbyeIntent: AppIntent {
  static var title: LocalizedStringResource = "Phát lời tạm biệt HiCar"
  static var description = IntentDescription("Phát đoạn lời tạm biệt đã cấu hình trong ứng dụng HiCar.")
  static var openAppWhenRun: Bool = false

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let ok = await HiCarAudioPlayer.shared.playWhenRouteReady(type: "goodbye")
    let message = ok
      ? "Đang phát lời tạm biệt."
      : "CarPlay/Bluetooth chưa sẵn sàng hoặc chưa có nhạc tạm biệt."
    return .result(dialog: "\(message)")
  }
}

/// Hành động "Dừng phát".
@available(iOS 16.0, *)
struct StopAudioIntent: AppIntent {
  static var title: LocalizedStringResource = "Dừng phát HiCar"
  static var description = IntentDescription("Dừng âm thanh đang phát của ứng dụng HiCar.")
  static var openAppWhenRun: Bool = false

  func perform() async throws -> some IntentResult {
    await HiCarAudioPlayer.shared.stop()
    return .result()
  }
}

/// Khai báo Shortcut + cụm từ gọi Siri. Cho phép hành động xuất hiện sẵn trong app Phím tắt.
@available(iOS 16.0, *)
struct HiCarAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: PlayGreetingIntent(),
      phrases: ["Phát lời chào \(.applicationName)"],
      shortTitle: "Phát lời chào",
      systemImageName: "hand.wave.fill"
    )
    AppShortcut(
      intent: PlayGoodbyeIntent(),
      phrases: ["Phát lời tạm biệt \(.applicationName)"],
      shortTitle: "Phát lời tạm biệt",
      systemImageName: "car.fill"
    )
    AppShortcut(
      intent: StopAudioIntent(),
      phrases: ["Dừng phát \(.applicationName)"],
      shortTitle: "Dừng phát",
      systemImageName: "stop.fill"
    )
  }
}
