import AVFoundation
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

/// Keeps torrent downloads (and casting) alive in the background with a
/// silent audio session, what sideloaded torrent clients rely on. (iOS 26's
/// continued processing tasks don't fit: iOS ends them when progress stalls,
/// as it does while a torrent finds peers, shows "Task failed", and can then
/// stop the app.) Best-effort; failures only log.
final class KinoraBackground {
  static let shared = KinoraBackground()

  private let engine = AVAudioEngine()
  private let node = AVAudioPlayerNode()
  private var audioRunning = false
  private var observers: [NSObjectProtocol] = []

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "kinora/background", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "start":
        self.startAudio()
        result(nil)
      case "update":
        result(nil)  // (the status shows in the app)
      case "stop":
        self.stopAudio()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
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
