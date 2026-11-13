import AVFoundation
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Before launch ends, so a tap that launched the app is delivered too.
    let center = UNUserNotificationCenter.current()
    KinoraBackground.shared.notices.next = center.delegate ?? self
    center.delegate = KinoraBackground.shared.notices
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KinoraBackground") {
      KinoraBackground.shared.attach(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KinoraFiles") {
      // Downloads are re-downloadable: keep them out of iCloud backups.
      FlutterMethodChannel(name: "kinora/files", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          guard call.method == "excludeFromBackup", let path = call.arguments as? String else {
            return result(FlutterMethodNotImplemented)
          }
          var url = URL(fileURLWithPath: path)
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          do {
            try url.setResourceValues(values)
            result(true)
          } catch {
            result(FlutterError(code: "exclude", message: error.localizedDescription, details: nil))
          }
        }
    }
  }
}

/// Kinora's own notices (download progress, "ready to watch") and what a
/// tap on one opens; any other notification goes on to Flutter's handler.
final class KinoraNotices: NSObject, UNUserNotificationCenterDelegate {
  weak var next: UNUserNotificationCenterDelegate?
  var onOpen: ((String) -> Void)?

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // In front, Kinora shows its own progress.
    if notification.request.content.userInfo["kinora"] != nil { return completionHandler([]) }
    if next?.userNotificationCenter?(center, willPresent: notification,
                                     withCompletionHandler: completionHandler) == nil {
      completionHandler([])
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if let open = response.notification.request.content.userInfo["kinora"] as? String {
      onOpen?(open)
      return completionHandler()
    }
    if next?.userNotificationCenter?(center, didReceive: response,
                                     withCompletionHandler: completionHandler) == nil {
      completionHandler()
    }
  }
}

/// Keeps torrent downloads (and casting) alive in the background with a
/// silent audio session, what sideloaded torrent clients rely on, and shows
/// how they're going in one quiet notification while Kinora is away. (iOS
/// 26's continued processing tasks don't fit: iOS ends them when progress
/// stalls, as it does while a torrent finds peers, shows "Task failed", and
/// can then stop the app.) Best-effort; failures only log.
final class KinoraBackground {
  static let shared = KinoraBackground()
  let notices = KinoraNotices()

  private static let statusId = "kinora.status"

  private let engine = AVAudioEngine()
  private let node = AVAudioPlayerNode()
  private var audioRunning = false
  private var observers: [NSObjectProtocol] = []
  private var channel: FlutterMethodChannel?

  /// The latest status line, and when and with what title it last showed.
  private var status: (title: String, text: String, open: String?)?
  private var shownAt = Date.distantPast
  private var shownTitle: String?

  /// A tap that came before Flutter could take it (it launched the app).
  private var pendingOpen: String?

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "kinora/background", binaryMessenger: messenger)
    self.channel = channel
    notices.onOpen = { [weak self] what in self?.open(what) }
    // A status left by a run that ended.
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.statusId])
    let app = NotificationCenter.default
    _ = app.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil,
                        queue: .main) { [weak self] _ in self?.showStatus(now: true) }
    _ = app.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil,
                        queue: .main) { [weak self] _ in self?.hideStatus() }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "start", "update":
        if call.method == "start" { self.startAudio() }
        self.status = (args["title"] as? String ?? "", args["text"] as? String ?? "",
                       args["open"] as? String)
        self.showStatus()
        result(nil)
      case "stop":
        self.stopAudio()
        self.status = nil
        self.hideStatus()
        result(nil)
      case "ready":
        self.notify(id: "kinora.ready.\(UUID().uuidString)", title: args["title"] as? String ?? "",
                    text: args["text"] as? String ?? "", open: "downloads", quiet: false)
        result(nil)
      case "notificationsUndecided":
        UNUserNotificationCenter.current().getNotificationSettings { settings in
          DispatchQueue.main.async { result(settings.authorizationStatus == .notDetermined) }
        }
      case "askNotifications":
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
          DispatchQueue.main.async { result(granted) }
          self.logSettings("asked about notifications: \(granted ? "allowed" : "not allowed")")
        }
      case "takeOpen":
        result(self.pendingOpen)
        self.pendingOpen = nil
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: notices

  /// The status, only while Kinora is in the background (in front it shows
  /// its own), replaced at most every 10 s unless its title changes.
  private func showStatus(now: Bool = false) {
    guard let s = status, UIApplication.shared.applicationState == .background else { return }
    guard now || s.title != shownTitle || Date().timeIntervalSince(shownAt) >= 10 else { return }
    shownAt = Date()
    shownTitle = s.title
    notify(id: Self.statusId, title: s.title, text: s.text, open: s.open, quiet: true)
    if now { logSettings("status shown in the background: \(s.title)") }
  }

  /// Into Kinora's diagnostics: what iPhone lets its notices do.
  private func logSettings(_ what: String) {
    UNUserNotificationCenter.current().getNotificationSettings { [weak self] n in
      let allowed = ["not asked", "denied", "allowed", "provisional", "ephemeral"]
      let on = ["n/a", "off", "on"]
      func word(_ list: [String], _ raw: Int) -> String { raw < list.count ? list[raw] : "\(raw)" }
      self?.log("\(what); notifications \(word(allowed, n.authorizationStatus.rawValue)), "
        + "lock screen \(word(on, n.lockScreenSetting.rawValue)), "
        + "list \(word(on, n.notificationCenterSetting.rawValue)), "
        + "banners \(word(on, n.alertSetting.rawValue))")
    }
  }

  private func log(_ message: String) {
    DispatchQueue.main.async { [weak self] in self?.channel?.invokeMethod("log", arguments: message) }
  }

  private func hideStatus() {
    shownTitle = nil
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.statusId])
  }

  /// Quiet: on the lock screen and in the list, no banner or sound (a
  /// status). Otherwise a silent banner ("ready to watch").
  private func notify(id: String, title: String, text: String, open: String?, quiet: Bool) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = text
    content.threadIdentifier = "kinora.downloads"
    content.userInfo = ["kinora": open ?? "app"]
    content.interruptionLevel = quiet ? .passive : .active
    content.relevanceScore = quiet ? 0.3 : 0.6
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: id, content: content, trigger: nil)
    ) { [weak self] error in
      if let error = error { self?.log("notice failed: \(error.localizedDescription)") }
    }
  }

  /// A tap on a download notice opens Downloads (kept until Flutter takes it).
  private func open(_ what: String) {
    guard what == "downloads" else { return }  // (opening the app is enough)
    pendingOpen = what
    channel?.invokeMethod("open", arguments: what) { [weak self] reply in
      if reply == nil { self?.pendingOpen = nil }  // taken
    }
  }

  // MARK: silent audio

  private func startAudio() {
    guard !audioRunning else { return }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try session.setActive(true)
      if node.engine == nil { engine.attach(node) }
      let format = engine.mainMixerNode.outputFormat(forBus: 0)
      engine.connect(node, to: engine.mainMixerNode, format: format)
      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate)) else { return }
      buffer.frameLength = buffer.frameCapacity  // zero-filled: silence
      node.scheduleBuffer(buffer, at: nil, options: .loops)
      try engine.start()
      node.play()
      audioRunning = true
      observe()
    } catch {
      NSLog("Kinora: background audio failed: \(error)")
    }
  }

  private func stopAudio() {
    guard audioRunning else { return }
    audioRunning = false
    node.stop()
    engine.stop()
    observers.forEach { NotificationCenter.default.removeObserver($0) }
    observers.removeAll()
  }

  private func observe() {
    guard observers.isEmpty else { return }
    observers.append(NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
    ) { [weak self] note in
      guard let self = self, self.audioRunning,
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
      try? AVAudioSession.sharedInstance().setActive(true)
      if !self.engine.isRunning { try? self.engine.start() }
      self.node.play()
    })
    observers.append(NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
    ) { [weak self] _ in
      guard let self = self, self.audioRunning else { return }
      self.audioRunning = false
      self.startAudio()
    })
  }
}
