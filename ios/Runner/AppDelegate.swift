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
    // Tự phát khi CarPlay nối/ngắt, không phụ thuộc hoàn toàn vào app Phím tắt.
    HiCarAudioPlayer.shared.startMonitoringRoute()

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
      // Lệnh từ UI trong app = phát thủ công → phát ngay, không qua bộ chống trùng.
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
        result(true)
      case "clearGoodbyeConfig":
        UserDefaults.standard.removeObject(forKey: "flutter.goodbye_audio_path")
        result(true)
      // flush UserDefaults để App Intent/Shortcut đọc được path vừa ghi.
      case "syncPrefs":
        UserDefaults.standard.synchronize()
        result(true)
      // Trạng thái đường ra âm thanh — dùng để chẩn đoán "sao xe không kêu".
      case "isVehicleConnected":
        result(HiCarAudioPlayer.shared.hasVehiclePlaybackRoute())
      case "getAudioRoute":
        result(HiCarAudioPlayer.shared.currentRouteDescription())
      // Các method chỉ có ý nghĩa trên Android → no-op để không ném MissingPluginException.
      case "minimizeApp", "openApp", "showAutostartSettings":
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Bluetooth cổ điển (quét/ghép nối thủ công) là cơ chế của Android. iOS không cho app
    // liệt kê hay chủ động nối thiết bị audio, hệ thống tự định tuyến — nên trả giá trị
    // trung tính, còn việc "đã nối xe chưa" đọc qua audio route ở serviceChannel.
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
///
/// Nguyên tắc để CarPlay/Bluetooth ổn định:
/// 1. Category được set MỘT LẦN và không đổi qua lại. Đổi category (hoặc gọi `setActive`)
///    trong lúc CarPlay đang bắt tay làm route nhảy liên tục → tiếng ra loa điện thoại
///    hoặc `play()` trả về true mà không có tiếng.
/// 2. Trong lúc CHỜ route xe chỉ ĐỌC `currentRoute`, không chạm vào session.
/// 3. Chỉ `setActive(true)` một lần, ngay trước khi phát.
/// 4. Sau khi `play()` trả về true còn kiểm tra `currentTime` có nhích lên thật không.
final class HiCarAudioPlayer: NSObject, AVAudioPlayerDelegate {

  static let shared = HiCarAudioPlayer()

  // Singleton sống suốt vòng đời app nên giữ strong ref an toàn (channel cũng được
  // AppDelegate giữ song song). Dùng để gọi ngược trạng thái phát về Flutter.
  var serviceChannel: FlutterMethodChannel?
  private var player: AVAudioPlayer?

  /// `duckOthers` làm `setActive` thất bại trên một số đầu CarPlay. Khi đã phải hạ xuống
  /// plain playback thì giữ nguyên, KHÔNG thử lại duckOthers ở lần sau.
  private var useDuckOthers = true
  private var isSessionActive = false

  /// Thời điểm mỗi loại được phát lần cuối do sự kiện kết nối. Shortcut và bộ theo dõi
  /// route có thể cùng bắn một lúc → chặn phát trùng/chồng tiếng.
  private var lastAutoPlayAt: [String: Date] = [:]
  private var inFlightAutoPlay: Set<String> = []
  private let autoPlayDedupWindow: TimeInterval = 45

  /// Trạng thái CarPlay lần cuối, để chỉ phản ứng ở đúng lúc CHUYỂN trạng thái.
  private var wasCarPlayConnected = false
  private var monitoringStartedAt = Date.distantPast

  /// Lần phát gần nhất kết thúc bất thường (decode lỗi / finish không thành công) — dùng để
  /// `playAndVerify` biết cần thử lại thay vì tưởng đã phát xong.
  private var lastPlaybackFailed = false

  private override init() { super.init() }

  // MARK: Session

  /// Cấu hình session một lần, giữ nguyên suốt vòng đời app.
  func configureSession() {
    let session = AVAudioSession.sharedInstance()
    let options: AVAudioSession.CategoryOptions = useDuckOthers ? [.duckOthers] : []
    do {
      try session.setCategory(.playback, mode: .default, options: options)
    } catch {
      NSLog("HiCar: setCategory lỗi (\(error.localizedDescription)) → plain playback")
      useDuckOthers = false
      try? session.setCategory(.playback, mode: .default)
    }
  }

  /// Kích hoạt session ngay trước khi phát. Nếu duckOthers làm activate fail thì hạ xuống
  /// plain playback VĨNH VIỄN để không còn đổi category qua lại.
  ///
  /// KHÔNG bao giờ `setActive(false)`: nhả session làm iOS bắn route change và đẩy đường ra
  /// về loa máy, dẫn tới hai hậu quả — bộ theo dõi route tưởng vừa rút CarPlay nên phát lời
  /// tạm biệt, và lần phát kế phải dựng lại route nên đầu xe kêu trễ vài giây.
  @discardableResult
  private func activateSession() -> Bool {
    let session = AVAudioSession.sharedInstance()

    // just_audio/audio_session có thể đã đổi category khi nghe thử trong app. Chỉ set lại
    // khi thực sự lệch, tránh đổi category vô cớ lúc route CarPlay đang ổn định.
    if session.category != .playback {
      configureSession()
    }

    if isSessionActive { return true }

    do {
      try session.setActive(true, options: [])
      isSessionActive = true
      return true
    } catch {
      NSLog("HiCar: setActive lỗi \(error.localizedDescription)")
      guard useDuckOthers else { return false }
      // duckOthers là nghi phạm số 1 → bỏ hẳn rồi thử lại.
      useDuckOthers = false
      do {
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true, options: [])
        isSessionActive = true
        NSLog("HiCar: setActive OK sau khi bỏ duckOthers")
        return true
      } catch {
        NSLog("HiCar: setActive retry lỗi \(error.localizedDescription)")
        return false
      }
    }
  }

  // MARK: Route

  /// Đường ra PHÁT ĐƯỢC của xe: CarPlay hoặc Bluetooth A2DP/LE.
  ///
  /// KHÔNG tính `bluetoothHFP` — đó là kênh thoại rảnh tay, category `.playback` không phát
  /// ra đó được. Trước đây HFP bị coi là "đã sẵn sàng" nên lời chào bắn ra khi A2DP chưa lên
  /// → tiếng ra loa điện thoại.
  func hasVehiclePlaybackRoute() -> Bool {
    AVAudioSession.sharedInstance().currentRoute.outputs.contains { out in
      out.portType == .carAudio || out.portType == .bluetoothA2DP || out.portType == .bluetoothLE
    }
  }

  func hasCarPlayRoute() -> Bool {
    AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .carAudio }
  }

  func currentRouteDescription() -> String {
    let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
    if outputs.isEmpty { return "none" }
    return outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",")
  }

  private enum RouteWaitResult {
    /// Route xe đã có sẵn từ trước → phát được ngay, không cần chờ ổn định.
    case alreadyReady
    /// Route vừa mới xuất hiện → đầu xe còn đang chuyển nguồn phát.
    case justAppeared
    case timedOut
  }

  /// Chờ route xe sẵn sàng. CHỈ ĐỌC route — không setCategory/setActive trong vòng lặp,
  /// vì mỗi lần activate lúc CarPlay đang bắt tay sẽ ép route về loa điện thoại.
  private func waitForVehicleRoute(timeoutMs: UInt64) async -> RouteWaitResult {
    if await MainActor.run(body: { self.hasVehiclePlaybackRoute() }) { return .alreadyReady }

    let stepMs: UInt64 = 250
    let steps = max(1, Int(timeoutMs / stepMs))
    for i in 0..<steps {
      try? await Task.sleep(nanoseconds: stepMs * 1_000_000)
      let ready = await MainActor.run { self.hasVehiclePlaybackRoute() }
      if ready {
        let route = await MainActor.run { self.currentRouteDescription() }
        NSLog("HiCar: route xe sẵn sàng sau \(Int(stepMs) * (i + 1))ms [\(route)]")
        return .justAppeared
      }
    }
    let route = await MainActor.run { self.currentRouteDescription() }
    NSLog("HiCar: hết \(timeoutMs)ms chưa có route xe [\(route)]")
    return .timedOut
  }

  // MARK: Monitoring

  /// Theo dõi thay đổi đường ra âm thanh + gián đoạn (cuộc gọi, Siri...).
  ///
  /// Đây là đường kích hoạt CHÍNH khi app còn sống: cắm CarPlay là phát lời chào ngay,
  /// không cần Phím tắt chạy đúng. Phím tắt vẫn giữ để lo trường hợp app đã bị hệ thống
  /// treo hẳn — hai nguồn trùng nhau đã có `lastAutoPlayAt` chặn.
  func startMonitoringRoute() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: nil
    )
    monitoringStartedAt = Date()
    wasCarPlayConnected = hasCarPlayRoute()
  }

  @objc private func handleRouteChange(_ note: Notification) {
    let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
    let reason = reasonRaw.flatMap { AVAudioSession.RouteChangeReason(rawValue: $0) }

    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      let isCarPlay = self.hasCarPlayRoute()
      guard isCarPlay != self.wasCarPlayConnected else { return }
      self.wasCarPlayConnected = isCarPlay

      NSLog("HiCar: CarPlay \(isCarPlay ? "kết nối" : "ngắt") reason=\(reasonRaw ?? 0) route=[\(self.currentRouteDescription())]")

      // `.categoryChange` là do CHÍNH app đổi/kích hoạt session, không phải người dùng cắm
      // xe. Các reason khác đều tính là cắm/rút thật — không lọc hẹp hơn (vd chỉ nhận
      // `.newDeviceAvailable`) vì mỗi đầu CarPlay báo một reason khác nhau.
      guard reason != .categoryChange else { return }

      // Mở app khi CarPlay đã nối sẵn: route "xuất hiện" ngay lúc session vừa dựng xong,
      // không phải vừa lên xe → bỏ qua để không phát lời chào oan.
      guard Date().timeIntervalSince(self.monitoringStartedAt) > 5 else {
        NSLog("HiCar: bỏ qua route đổi ngay sau khi khởi động")
        return
      }
      guard self.isAutoPlayEnabled() else { return }

      // Chỉ tự phát cho CarPlay. Bluetooth A2DP không phân biệt được xe với tai nghe,
      // nên để người dùng tự chọn thiết bị bằng Tự động hoá trong app Phím tắt.
      if isCarPlay {
        Task { _ = await self.playOnVehicleConnected(type: "greeting") }
      } else {
        Task { _ = await self.playGoodbyeIfReallyDisconnected() }
      }
    }
  }

  /// Route mất CarPlay có thể chỉ là nhiễu thoáng qua (đầu xe đổi nguồn phát, cuộc gọi
  /// chen ngang, session vừa bị plugin khác đụng vào). Chờ một nhịp rồi soi lại, tránh
  /// cảnh đang nghe lời chào tự dưng nhảy sang lời tạm biệt.
  private func playGoodbyeIfReallyDisconnected() async -> Bool {
    try? await Task.sleep(nanoseconds: 1_500_000_000)
    let stillGone = await MainActor.run { !self.hasCarPlayRoute() }
    guard stillGone else {
      NSLog("HiCar: CarPlay quay lại sau 1.5s → bỏ lời tạm biệt")
      await MainActor.run { self.wasCarPlayConnected = true }
      return false
    }
    return await playOnVehicleDisconnected(type: "goodbye")
  }

  @objc private func handleInterruption(_ note: Notification) {
    guard
      let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: raw)
    else { return }

    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }

      if type == .began {
        NSLog("HiCar: audio bị gián đoạn")
        self.isSessionActive = false
        return
      }

      // Gián đoạn kết thúc: chỉ tiếp tục nếu đang phát dở, tránh phát lại từ đầu.
      guard
        let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
        AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume),
        let current = self.player, current.currentTime > 0, !current.isPlaying
      else { return }

      if self.activateSession() {
        current.play()
        NSLog("HiCar: tiếp tục phát sau gián đoạn")
      }
    }
  }

  private func isAutoPlayEnabled() -> Bool {
    // shared_preferences lưu kèm tiền tố `flutter.`; chưa từng set thì mặc định bật.
    guard let value = UserDefaults.standard.object(forKey: "flutter.auto_play_enabled") else {
      return true
    }
    return (value as? NSNumber)?.boolValue ?? true
  }

  // MARK: Play

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
    // AVAudioSession / AVAudioPlayer cần main thread — Intent có thể gọi từ background.
    if !Thread.isMainThread {
      var ok = false
      DispatchQueue.main.sync {
        ok = self.play(path: path, type: type)
      }
      return ok
    }

    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
      NSLog("HiCar: không tìm thấy file \(path)")
      return false
    }

    guard activateSession() else {
      NSLog("HiCar: không kích hoạt được audio session → bỏ phát \(type)")
      return false
    }

    NSLog("HiCar: play type=\(type) route=[\(currentRouteDescription())]")

    do {
      player?.stop()
      lastPlaybackFailed = false
      let newPlayer = try AVAudioPlayer(contentsOf: url)
      newPlayer.delegate = self
      newPlayer.volume = 1.0
      // Giữ strong ref TRƯỚC khi play — tránh player bị giải phóng sớm.
      player = newPlayer
      newPlayer.prepareToPlay()
      let started = newPlayer.play()
      if started {
        notifyFlutter("onPlaybackStarted", arguments: type)
      } else {
        NSLog("HiCar: AVAudioPlayer.play() = false")
        player = nil
      }
      return started
    } catch {
      NSLog("HiCar: AVAudioPlayer lỗi \(error.localizedDescription)")
      player = nil
      return false
    }
  }

  /// `play()` trả về true không có nghĩa là loa xe đã kêu. Kiểm tra con trỏ thời gian có
  /// nhích lên thật để biết cần phát lại hay không.
  private func playAndVerify(type: String) async -> Bool {
    let started = await MainActor.run { self.play(type: type) }
    guard started else { return false }

    try? await Task.sleep(nanoseconds: 500_000_000)
    return await MainActor.run { () -> Bool in
      let ok: Bool
      if self.lastPlaybackFailed {
        ok = false
      } else if let player = self.player {
        ok = player.isPlaying && player.currentTime > 0
        if !ok {
          NSLog("HiCar: đã play nhưng currentTime=\(player.currentTime) isPlaying=\(player.isPlaying) → coi như thất bại")
        }
      } else {
        ok = true // player đã nil = clip rất ngắn, phát xong trong 500ms
      }
      // Chỉ ghi mốc chống trùng khi CHẮC CHẮN có tiếng, để lần kích hoạt sau (Phím tắt)
      // vẫn được thử lại nếu lần này thất bại.
      if ok { self.lastAutoPlayAt[type] = Date() }
      return ok
    }
  }

  /// Dùng khi vừa nối CarPlay/Bluetooth (Shortcut hoặc bộ theo dõi route).
  func playOnVehicleConnected(type: String) async -> Bool {
    guard await beginAutoPlay(type: type) else { return false }
    defer { Task { await endAutoPlay(type: type) } }

    return await withBackgroundTask(name: "HiCar.\(type)") {
      // CarPlay gắn route chậm hơn Bluetooth; chỉ ĐỌC route trong lúc chờ.
      let wait = await self.waitForVehicleRoute(timeoutMs: 10_000)

      // Chỉ chờ ổn định khi route VỪA xuất hiện — lúc đó đầu xe còn đang chuyển nguồn phát
      // nên phát ngay sẽ mất mấy chữ đầu. Nếu route đã có sẵn thì phát luôn, đừng bắt người
      // dùng đợi vô ích.
      switch wait {
      case .alreadyReady: break
      case .justAppeared: try? await Task.sleep(nanoseconds: 700_000_000)
      case .timedOut: try? await Task.sleep(nanoseconds: 300_000_000)
      }

      for attempt in 1...3 {
        if attempt > 1 { try? await Task.sleep(nanoseconds: 1_000_000_000) }
        let ok = await self.playAndVerify(type: type)
        NSLog("HiCar: connect-play type=\(type) lần \(attempt)/3 ok=\(ok) wait=\(wait)")
        if ok { return true }
      }
      return false
    }
  }

  /// Dùng khi vừa NGẮT xe. KHÔNG chờ route xe — route đó chắc chắn đã mất, chờ chỉ làm lời
  /// tạm biệt phát trễ cả chục giây (hoặc không phát).
  func playOnVehicleDisconnected(type: String) async -> Bool {
    guard await beginAutoPlay(type: type) else { return false }
    defer { Task { await endAutoPlay(type: type) } }

    return await withBackgroundTask(name: "HiCar.\(type)") {
      for attempt in 1...2 {
        if attempt > 1 { try? await Task.sleep(nanoseconds: 700_000_000) }
        let ok = await self.playAndVerify(type: type)
        NSLog("HiCar: disconnect-play type=\(type) lần \(attempt)/2 ok=\(ok)")
        if ok { return true }
      }
      return false
    }
  }

  /// Chặn hai nguồn kích hoạt (Phím tắt + theo dõi route) phát chồng lên nhau.
  @MainActor
  private func beginAutoPlay(type: String) -> Bool {
    if inFlightAutoPlay.contains(type) {
      NSLog("HiCar: bỏ qua \(type) — đang có yêu cầu phát chạy dở")
      return false
    }
    if let last = lastAutoPlayAt[type], Date().timeIntervalSince(last) < autoPlayDedupWindow {
      NSLog("HiCar: bỏ qua \(type) — vừa phát \(Int(Date().timeIntervalSince(last)))s trước")
      return false
    }
    inFlightAutoPlay.insert(type)
    return true
  }

  @MainActor
  private func endAutoPlay(type: String) {
    inFlightAutoPlay.remove(type)
  }

  private final class BackgroundTaskBox {
    var id: UIBackgroundTaskIdentifier = .invalid
  }

  /// Giữ tiến trình sống trong lúc chờ route. Khi Phím tắt đánh thức app ở chế độ nền,
  /// không có background task thì iOS treo tiến trình trước cả khi kịp phát.
  private func withBackgroundTask(name: String, _ work: @escaping () async -> Bool) async -> Bool {
    let box = BackgroundTaskBox()
    await MainActor.run {
      box.id = UIApplication.shared.beginBackgroundTask(withName: name) {
        guard box.id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(box.id)
        box.id = .invalid
      }
    }
    let result = await work()
    await MainActor.run {
      guard box.id != .invalid else { return }
      UIApplication.shared.endBackgroundTask(box.id)
      box.id = .invalid
    }
    return result
  }

  func stop() {
    let stopBlock = {
      self.player?.stop()
      self.player = nil
    }
    if Thread.isMainThread {
      stopBlock()
    } else {
      DispatchQueue.main.async(execute: stopBlock)
    }
  }

  // MARK: Paths

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
      NSLog("HiCar: resolvePath stored missing file=\(stored)")
    } else {
      NSLog("HiCar: resolvePath empty key=\(key)")
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
    lastPlaybackFailed = !flag
    self.player = nil
    notifyFlutter("onPlaybackComplete", arguments: nil)
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    NSLog("HiCar: decode error \(error?.localizedDescription ?? "?")")
    lastPlaybackFailed = true
    self.player = nil
    notifyFlutter("onPlaybackComplete", arguments: nil)
  }
}

// MARK: - App Intents (Shortcuts) — iOS 16+

/// Hành động "Phát lời chào" để người dùng gắn vào Tự động hóa cá nhân
/// (Shortcuts → Tự động hóa → "Khi CarPlay kết nối" / "Bluetooth" → Phát lời chào HiCar).
@available(iOS 16.0, *)
struct PlayGreetingIntent: AppIntent {
  static var title: LocalizedStringResource = "Phát lời chào HiCar"
  static var description = IntentDescription("Phát đoạn lời chào đã cấu hình trong ứng dụng HiCar.")
  static var openAppWhenRun: Bool = false

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let hasPath = await MainActor.run {
      HiCarAudioPlayer.shared.resolvePath(for: "greeting") != nil
    }
    if !hasPath {
      return .result(dialog: "Chưa cấu hình lời chào trong ứng dụng HiCar. Hãy mở app và đặt lời chào.")
    }
    // Chờ audio route xe (CarPlay chậm hơn Bluetooth) rồi mới phát.
    let ok = await HiCarAudioPlayer.shared.playOnVehicleConnected(type: "greeting")
    let message = ok
      ? "Đang phát lời chào."
      : "Không phát được lời chào qua CarPlay/Bluetooth. Hãy mở app HiCar bấm Phát lời chào thử, rồi kết nối lại."
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
    let hasPath = await MainActor.run {
      HiCarAudioPlayer.shared.resolvePath(for: "goodbye") != nil
    }
    if !hasPath {
      return .result(dialog: "Chưa cấu hình lời tạm biệt trong ứng dụng HiCar. Hãy mở app và đặt lời tạm biệt.")
    }
    // Tạm biệt chạy lúc vừa NGẮT xe → phát ngay, không chờ route.
    let ok = await HiCarAudioPlayer.shared.playOnVehicleDisconnected(type: "goodbye")
    let message = ok
      ? "Đang phát lời tạm biệt."
      : "Không phát được lời tạm biệt qua CarPlay/Bluetooth. Hãy mở app HiCar rồi kết nối lại."
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
