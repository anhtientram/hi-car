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
    configureSession()
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
      }
      return started
    } catch {
      NSLog("HiCar: AVAudioPlayer lỗi \(error.localizedDescription)")
      return false
    }
  }

  /// App Intent có thể chạy ngay trước khi CarPlay/Bluetooth hoàn tất route.
  /// Chờ route thật sự sẵn sàng rồi mới phát, thay vì phát nhầm ra loa iPhone và
  /// coi lần kích hoạt đó là đã thành công.
  func playWhenRouteReady(type: String) async -> Bool {
    let maxAttempts = 60 // tối đa khoảng 30 giây, đủ cho head unit/BT chậm
    for attempt in 0..<maxAttempts {
      configureSession()
      do {
        try AVAudioSession.sharedInstance().setActive(true, options: [])
      } catch {
        NSLog("HiCar: audio session chưa sẵn sàng (attempt \(attempt + 1)): \(error.localizedDescription)")
      }

      guard let path = resolvePath(for: type) else {
        NSLog("HiCar: chưa có file \(type), tiếp tục chờ đồng bộ")
        try? await Task.sleep(nanoseconds: 500_000_000)
        continue
      }

      if hasCarRoute() {
        return play(path: path, type: type)
      }

      if attempt == maxAttempts - 1 {
        NSLog("HiCar: hết thời gian chờ route xe cho \(type)")
        return false
      }
      try? await Task.sleep(nanoseconds: 500_000_000)
    }
    return false
  }

  private func hasCarRoute() -> Bool {
    let carPorts: Set<AVAudioSession.Port> = [
      .carAudio,
      .bluetoothA2DP,
      .bluetoothHFP,
    ]
    return !AVAudioSession.sharedInstance().currentRoute.outputs
      .filter { carPorts.contains($0.portType) }
      .isEmpty
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
    guard let stored = UserDefaults.standard.string(forKey: key), !stored.isEmpty else {
      return nil
    }
    if FileManager.default.fileExists(atPath: stored) { return stored }

    let name = (stored as NSString).lastPathComponent
    if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
      let candidate = docs.appendingPathComponent(name).path
      if FileManager.default.fileExists(atPath: candidate) { return candidate }
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
