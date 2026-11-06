import AVFoundation
import Flutter
import GoogleMaps
import PushKit
import UIKit
import UserNotifications
import flutter_callkit_incoming
import flutter_webrtc
import WebRTC

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate {
  /// Apple's VoIP pushes: the only way a closed app may ring for a call.
  private var voipRegistry: PKPushRegistry?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // GMSApiKey comes from the GOOGLE_MAPS_API_KEY build setting; empty
    // builds show locations without a live map.
    if let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
      !key.isEmpty, !key.hasPrefix("$(")
    {
      GMSServices.provideAPIKey(key)
    }
    // flutter_local_notifications shows new messages that arrive while the
    // app is open, and reports taps on them, through this delegate.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // After Flutter and its plugins are up, so a push that launched the app
    // finds the call plugin ready.
    let registry = PKPushRegistry(queue: .main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "TelvoxCallRecording")?
      .messenger()
    {
      CallRecording.register(messenger: messenger)
    }
  }

  // MARK: VoIP pushes (PushKit)

  /// The token the server sends this phone's VoIP pushes to. The plugin keeps
  /// it and tells the Dart side, which hands it to the server.
  func pushRegistry(
    _ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType
  ) {
    let token = credentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  /// A customer's call. iOS requires every VoIP push to show a call at once
  /// (or it stops delivering them), so this reports it to CallKit before
  /// anything else; Accept and Decline then reach the app as they do on
  /// Android. The server sends the call's UUID, the same one the app derives
  /// from the call id, so a later cancel finds this ring.
  func pushRegistry(
    _ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType, completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    var extra: [String: Any] = [:]
    for (key, value) in payload.dictionaryPayload {
      if let key = key as? String, key != "aps" { extra[key] = value }
    }
    let name = (extra["contact_name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
    let phone = (extra["contact_phone"] as? String ?? "").trimmingCharacters(in: .whitespaces)
    let args: [String: Any?] = [
      "id": extra["uuid"] as? String ?? UUID().uuidString,
      "nameCaller": !name.isEmpty ? name : (!phone.isEmpty ? "+\(phone)" : "WhatsApp caller"),
      "appName": "Telvox Chat",
      "handle": phone.isEmpty ? "" : "+\(phone)",
      "type": 0,
      "duration": ringMilliseconds(until: extra["expires_at"] as? String),
      "extra": extra,
      // The server sends its own missed-call notification.
      "missedCallNotification": ["showNotification": false],
      "ios": ["handleType": "generic", "supportsVideo": false],
    ]
    guard let plugin = SwiftFlutterCallkitIncomingPlugin.sharedInstance else {
      completion()
      return
    }
    plugin.showCallkitIncoming(
      flutter_callkit_incoming.Data(args: args), fromPushKit: true, completion: completion)
  }

  /// How long to ring: until the call offer expires, within 5 to 60 seconds.
  private func ringMilliseconds(until expires: String?) -> Int {
    guard let expires = expires else { return 30000 }
    let plain = ISO8601DateFormatter()
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let at = plain.date(from: expires) ?? fractional.date(from: expires) else {
      return 30000
    }
    let left = Int(at.timeIntervalSinceNow * 1000)
    return min(max(left, 5000), 60000)
  }
}

// MARK: Recording a WhatsApp call

/// A call recorded on the phone, as the web inbox records it (custom capture):
/// this phone's microphone and the customer's voice, each written to its own
/// AAC file, then mixed into one. flutter_webrtc cannot record audio-only calls
/// on iOS, but its audio engine passes every 10 ms of both through
/// AudioManager: capture post-processing (the microphone, after echo
/// cancellation) and render pre-processing (the customer, before it plays).
/// The recorders listen there for as long as the call records.
final class CallRecording {
  private static var microphone: CallAudioFile?
  private static var customer: CallAudioFile?

  static func register(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "telvox/call_recording", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        switch call.method {
        case "start":
          let folder = (call.arguments as? [String: Any])?["folder"] as? String ?? NSTemporaryDirectory()
          result(start(folder: folder))
        case "stop":
          stop { paths in result(paths) }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    // The two sides mixed into one recording, as Android does it with Media3.
    FlutterMethodChannel(name: "telvox/video", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "mixAudio", let args = call.arguments as? [String: Any],
          let inputs = args["inputs"] as? [String], let out = args["out"] as? String
        else {
          result(FlutterMethodNotImplemented)
          return
        }
        mix(inputs: inputs, out: out) { path in result(path) }
      }
  }

  /// Starts both recorders; the two files' paths, or nil if already recording.
  private static func start(folder: String) -> [String]? {
    if microphone != nil { return nil }
    try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    let stamp = Int(Date().timeIntervalSince1970 * 1_000_000)
    let mic = CallAudioFile(path: "\(folder)/\(stamp)-microphone.m4a")
    let them = CallAudioFile(path: "\(folder)/\(stamp)-customer.m4a")
    let audio = AudioManager.sharedInstance()
    audio.capturePostProcessingAdapter.addAudioRenderer(mic)
    audio.renderPreProcessingAdapter.addAudioRenderer(them)
    microphone = mic
    customer = them
    return [mic.path, them.path]
  }

  /// Stops listening and closes both files, then hands back their paths.
  private static func stop(_ done: @escaping ([String]?) -> Void) {
    guard let mic = microphone, let them = customer else {
      done(nil)
      return
    }
    let audio = AudioManager.sharedInstance()
    audio.capturePostProcessingAdapter.removeAudioRenderer(mic)
    audio.renderPreProcessingAdapter.removeAudioRenderer(them)
    microphone = nil
    customer = nil
    mic.close {
      them.close {
        DispatchQueue.main.async { done([mic.path, them.path]) }
      }
    }
  }

  /// The recordings that hold sound, played side by side in one AAC file.
  private static func mix(inputs: [String], out: String, _ done: @escaping (String?) -> Void) {
    let composition = AVMutableComposition()
    for path in inputs where FileManager.default.fileExists(atPath: path) {
      let asset = AVURLAsset(url: URL(fileURLWithPath: path))
      guard let source = asset.tracks(withMediaType: .audio).first,
        let track = composition.addMutableTrack(
          withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
      else { continue }
      try? track.insertTimeRange(
        CMTimeRange(start: .zero, duration: asset.duration), of: source, at: .zero)
    }
    guard !composition.tracks.isEmpty,
      let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A)
    else {
      done(nil)
      return
    }
    try? FileManager.default.removeItem(atPath: out)
    export.outputURL = URL(fileURLWithPath: out)
    export.outputFileType = .m4a
    export.exportAsynchronously {
      DispatchQueue.main.async { done(export.status == .completed ? out : nil) }
    }
  }
}

/// One side of the call, written as it arrives. WebRTC hands over 10 ms of
/// 16-bit audio at a time on its audio thread; the writing happens on a queue
/// of its own so the call's audio never waits on the file.
final class CallAudioFile: NSObject, RTCAudioRenderer {
  let path: String
  private let queue = DispatchQueue(label: "telvox.call-recording")
  private var file: AVAudioFile?

  init(path: String) {
    self.path = path
  }

  func render(pcmBuffer: AVAudioPCMBuffer) {
    queue.async { [weak self] in self?.write(pcmBuffer) }
  }

  private func write(_ buffer: AVAudioPCMBuffer) {
    if file == nil {
      let format = buffer.format
      file = try? AVAudioFile(
        forWriting: URL(fileURLWithPath: path),
        settings: [
          AVFormatIDKey: kAudioFormatMPEG4AAC,
          AVSampleRateKey: format.sampleRate,
          AVNumberOfChannelsKey: format.channelCount,
          AVEncoderBitRateKey: 64000,
        ],
        commonFormat: .pcmFormatInt16,
        interleaved: false)
    }
    // A buffer in another format (the engine restarted mid-call) is skipped
    // rather than written as noise.
    guard let file = file, file.processingFormat.sampleRate == buffer.format.sampleRate,
      file.processingFormat.channelCount == buffer.format.channelCount
    else { return }
    try? file.write(from: buffer)
  }

  /// Finishes the file once everything queued is written.
  func close(_ done: @escaping () -> Void) {
    queue.async { [weak self] in
      self?.file = nil
      done()
    }
  }
}

