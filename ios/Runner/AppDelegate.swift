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
      case "playGoodbye":
        let path = (args?["audioPath"] as? String) ?? ""
        if path.isEmpty {
          result(HiCarAudioPlayer.shared.play(type: "goodbye"))
        } else {
          result(HiCarAudioPlayer.shared.play(path: path, type: "goodbye"))
        }
      case "clearGreetingConfig":
        UserDefaults.standard.removeObject(forKey: "flutter.greeting_audio_path")
        UserDefaults.standard.synchronize()
        result(true)
      case "clearGoodbyeConfig":
        UserDefaults.standard.removeObject(forKey: "flutter.goodbye_audio_path")
        UserDefaults.standard.synchronize()
        result(true)
      // flush UserDefaults để App Intent/Shortcut đọc được path vừa ghi.
      case "syncPrefs":
        UserDefaults.standard.synchronize()
        result(true)
      // Các method chỉ có ý nghĩa trên Android → no-op để không ném MissingPluginException.
      case "minimizeApp", "openApp", "showAutostartSettings":
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
final class HiCarAudioPlayer: NSObject, AVAudioPlayerDelegate {

  static let shared = HiCarAudioPlayer()

  // Singleton sống suốt vòng đời app nên giữ strong ref an toàn (channel cũng được
  // AppDelegate giữ song song). Dùng để gọi ngược trạng thái phát về Flutter.
  var serviceChannel: FlutterMethodChannel?
  private var player: AVAudioPlayer?

  private override init() { super.init() }

  func configureSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .default, options: [.duckOthers])
    } catch {
      NSLog("HiCar: setCategory error \(error.localizedDescription)")
    }
  }

  /// Phát theo loại, tự đọc đường dẫn đã cấu hình. Trả về false nếu CHƯA CẤU HÌNH.
  @discardableResult
  func play(type: String) -> Bool {
    guard let path = resolvePath(for: type) else {
      NSLog("HiCar: chưa cấu hình audio cho \(type)")
      return false
    }
    return play(path: path, type: type)
  }

  @discardableResult
  func play(path: String, type: String) -> Bool {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
      NSLog("HiCar: không tìm thấy file \(path)")
      return false
    }

    let session = AVAudioSession.sharedInstance()
    // Cho phép route ra Bluetooth / CarPlay khi Intent chạy nền.
    do {
      try session.setCategory(
        .playback,
        mode: .default,
        options: [.duckOthers, .allowBluetoothA2DP]
      )
    } catch {
      NSLog("HiCar: setCategory error \(error.localizedDescription)")
      configureSession()
    }
    do {
      try session.setActive(true, options: [])
    } catch {
      NSLog("HiCar: kích hoạt session lỗi \(error.localizedDescription)")
    }

    do {
      player?.stop()
      let newPlayer = try AVAudioPlayer(contentsOf: url)
      newPlayer.delegate = self
      newPlayer.prepareToPlay()
      newPlayer.volume = 1.0
      let started = newPlayer.play()
      player = newPlayer
      if started {
        notifyFlutter("onPlaybackStarted", arguments: type)
      } else {
        NSLog("HiCar: AVAudioPlayer.play() trả về false (route/focus chưa sẵn?)")
      }
      return started
    } catch {
      NSLog("HiCar: AVAudioPlayer lỗi \(error.localizedDescription)")
      return false
    }
  }

  /// Phát kèm retry — dùng cho Shortcut lúc vừa connect BT/CarPlay (route chưa ổn định).
  func playWithRetry(type: String, attempts: Int = 3, delayMs: UInt64 = 1500) async -> Bool {
    for attempt in 1...attempts {
      if attempt > 1 {
        try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
      }
      configureSession()
      let ok = play(type: type)
      NSLog("HiCar: playWithRetry type=\(type) attempt=\(attempt)/\(attempts) ok=\(ok)")
      if ok { return true }
    }
    return false
  }

  func stop() {
    player?.stop()
    player = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
  }

  /// Tìm đường dẫn file audio đã cấu hình. Có fallback theo tên file trong Documents
  /// phòng khi đường dẫn tuyệt đối cũ không còn hợp lệ (container đổi sau khi cập nhật app).
  func resolvePath(for type: String) -> String? {
    let key = (type == "greeting") ? "flutter.greeting_audio_path" : "flutter.goodbye_audio_path"
    let pinnedName = (type == "greeting") ? "active_greeting.mp3" : "active_goodbye.mp3"
    let fm = FileManager.default

    if let stored = UserDefaults.standard.string(forKey: key), !stored.isEmpty {
      if fm.fileExists(atPath: stored) { return stored }

      let name = (stored as NSString).lastPathComponent
      if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
        let inRoot = docs.appendingPathComponent(name).path
        if fm.fileExists(atPath: inRoot) { return inRoot }
        let inAudio = docs.appendingPathComponent("hicar_audio").appendingPathComponent(name).path
        if fm.fileExists(atPath: inAudio) { return inAudio }
      }
    }

    // Fallback: file pin cố định sau khi user setup lời chào trong app.
    if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
      let pinned = docs.appendingPathComponent("hicar_audio").appendingPathComponent(pinnedName).path
      if fm.fileExists(atPath: pinned) { return pinned }
    }

    return nil
  }

  private func notifyFlutter(_ method: String, arguments: Any?) {
    DispatchQueue.main.async { [weak self] in
      self?.serviceChannel?.invokeMethod(method, arguments: arguments)
    }
  }

  // MARK: AVAudioPlayerDelegate

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    self.player = nil
    notifyFlutter("onPlaybackComplete", arguments: nil)
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    self.player = nil
    notifyFlutter("onPlaybackComplete", arguments: nil)
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
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
    // Chờ route Bluetooth/CarPlay ổn định rồi mới phát (retry nếu lần đầu fail).
    try? await Task.sleep(nanoseconds: 1_200_000_000)
    if HiCarAudioPlayer.shared.resolvePath(for: "greeting") == nil {
      return .result(dialog: "Chưa cấu hình lời chào trong ứng dụng HiCar. Hãy mở app và đặt lời chào.")
    }
    let ok = await HiCarAudioPlayer.shared.playWithRetry(type: "greeting")
    let message = ok
      ? "Đang phát lời chào."
      : "Không phát được lời chào. Hãy mở app HiCar một lần, kiểm tra lời chào đã đặt, rồi kết nối Bluetooth/CarPlay lại."
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
    try? await Task.sleep(nanoseconds: 1_200_000_000)
    if HiCarAudioPlayer.shared.resolvePath(for: "goodbye") == nil {
      return .result(dialog: "Chưa cấu hình lời tạm biệt trong ứng dụng HiCar. Hãy mở app và đặt lời tạm biệt.")
    }
    let ok = await HiCarAudioPlayer.shared.playWithRetry(type: "goodbye")
    let message = ok
      ? "Đang phát lời tạm biệt."
      : "Không phát được lời tạm biệt. Hãy mở app HiCar một lần rồi kết nối Bluetooth/CarPlay lại."
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
    HiCarAudioPlayer.shared.stop()
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
