import Flutter
import GoogleMaps
import PushKit
import UIKit
import UserNotifications
import flutter_callkit_incoming

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
