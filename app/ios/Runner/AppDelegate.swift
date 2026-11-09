import AVFoundation
import BackgroundTasks
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KinoraBackground") {
      KinoraBackground.shared.attach(messenger: registrar.messenger())
    }
  }
}

/// Keeps torrent downloads alive in the background: a silent audio session
/// (what sideloaded torrent clients rely on) plus, on iOS 26+, a continued
/// processing task that shows system progress. Every step is best-effort;
/// failures only log.
final class KinoraBackground {
  static let shared = KinoraBackground()

  private let engine = AVAudioEngine()
  private let node = AVAudioPlayerNode()
  private var audioRunning = false
  private var channel: FlutterMethodChannel?
  private var task: AnyObject?  // BGContinuedProcessingTask on iOS 26+
  private var observers: [NSObjectProtocol] = []

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "kinora/background", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "start":
        self.startAudio()
        self.beginTask(title: args["title"] as? String ?? "Downloading",
                       text: args["text"] as? String ?? "")
        result(nil)
      case "update":
        self.updateTask(text: args["text"] as? String, progress: args["progress"] as? Double)
        result(nil)
      case "stop":
        self.endTask(success: args["success"] as? Bool ?? true)
        self.stopAudio()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
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

  // MARK: continued processing (iOS 26+)

  private func beginTask(title: String, text: String) {
    guard #available(iOS 26.0, *), task == nil else { return }
    // A handler per request: a single wildcard handler doesn't route
    // (developer forums), registering right before submit does.
    let id = "io.github.abdvlrqhman.kinora.downloads.\(UUID().uuidString)"
    let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { [weak self] t in
      guard let self = self, let t = t as? BGContinuedProcessingTask else { return }
      self.task = t
      t.progress.totalUnitCount = 1000
      t.expirationHandler = { [weak self] in
        self?.task = nil
        self?.channel?.invokeMethod("expired", arguments: nil)
      }
    }
    guard registered else { return }
    let request = BGContinuedProcessingTaskRequest(identifier: id, title: title, subtitle: text)
    request.strategy = .fail
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      NSLog("Kinora: continued processing unavailable: \(error)")
    }
  }

  private func updateTask(text: String?, progress: Double?) {
    guard #available(iOS 26.0, *), let t = task as? BGContinuedProcessingTask else { return }
    if let text = text { t.updateTitle(t.title, subtitle: text) }
    if let p = progress { t.progress.completedUnitCount = Int64(max(0, min(1, p)) * 1000) }
  }

  private func endTask(success: Bool) {
    guard #available(iOS 26.0, *), let t = task as? BGContinuedProcessingTask else { return }
    t.setTaskCompleted(success: success)
    task = nil
  }
}
