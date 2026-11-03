# Building Telvox Chat for iPhone

The app has never been built for iOS. Everything that can be prepared without
a Mac is already in the repo (see "Already done"). The steps below need a Mac
with Xcode, the Telvox Apple Developer account, or both, and are in the order
to do them.

Bundle ID: `com.telvox.telvoxChatMobileApp` · App Group:
`group.com.telvox.telvoxChatMobileApp` · minimum iOS 15.

## Already done (no Mac needed)

- **Firebase on iPhone** uses its own app: `FIREBASE_IOS_APP_ID` and
  `FIREBASE_IOS_API_KEY` in `config/development.json`
  (`lib/core/config/app_config.dart`). Android keeps `FIREBASE_APP_ID` /
  `FIREBASE_API_KEY`.
- **`ios/Runner/Info.plist`**: background modes `remote-notification` (pushes)
  and `audio` (a call keeps talking with the screen off); the share keys
  `AppGroupId` and the `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)` URL scheme;
  camera, photos, location and microphone texts.
- **`ios/Runner/Runner.entitlements`**: push notifications (`aps-environment`)
  and the App Group, referenced from the Runner target, which also defines
  `CUSTOM_GROUP_ID` (read by the share plugin).
- **`AppDelegate.swift`** sets the notification centre's delegate, so messages
  that arrive while the app is open are shown and their taps open the chat.
- **Notification sounds** (Tap, Pebble, Chime) are copied by the app into its
  `Library/Sounds` folder when push starts (`installIosSounds` in
  `lib/mobile/notification_sound.dart`), where iOS finds them for the server's
  pushes and the app's own. No Xcode step for them.

## 1. Mac, Xcode and the Apple account

1. Install the current Xcode and CocoaPods (`brew install cocoapods`), and the
   Flutter SDK the repo pins (see `dev.env`).
2. Join the Apple Developer Program as Telvox (organisation account) and note
   the Team ID.
3. In Xcode, open `ios/Runner.xcworkspace` → Runner target → *Signing &
   Capabilities*: pick the team, keep *Automatically manage signing* on. Xcode
   registers the App ID with Push Notifications and the App Group from the
   entitlements; confirm both capabilities show there.

## 2. Firebase for iPhone

1. Firebase console, project `telvox-3275c` → *Add app* → iOS, bundle ID
   `com.telvox.telvoxChatMobileApp`.
2. From the `GoogleService-Info.plist` it offers, copy `GOOGLE_APP_ID` into
   `FIREBASE_IOS_APP_ID` and `API_KEY` into `FIREBASE_IOS_API_KEY` in
   `config/development.json`. The plist itself is not added to the project
   (the app passes these values in code, as on Android).
3. Apple Developer → *Keys* → new key with **Apple Push Notifications
   service (APNs)**. Download the `.p8` once, note its Key ID. Upload it in
   Firebase → Project settings → *Cloud Messaging* → Apple app configuration,
   with the Team ID. Keep the `.p8` out of the repo.

## 3. First build

```bash
flutter pub get
cd ios && pod install && cd ..
flutter run --release --dart-define-from-file=config/development.json
```

`flutter run` against a connected iPhone creates `ios/Podfile` the first time.
Expect a round of native build fixes; the likeliest is SQLCipher
(`sqflite_sqlcipher`) clashing with another library's SQLite. Commit the
generated `ios/Podfile` and `ios/Podfile.lock`.

Google Maps on iPhone (optional): set the `GOOGLE_MAPS_API_KEY` build setting
on the Runner target to an iOS-restricted Maps key; without it locations show
as a card with "Open in Google Maps".

## 4. Check on a real iPhone

Sign in, open chats, send text, photo, video, document, voice note and
location, use the camera, search a chat, get a push with the app in the
background, change the notification sound, make and answer a call with the
app open. The iOS (Cupertino) screens exist in code but have never been seen
on a device, so expect polish fixes.

## 5. Share to Telvox Chat (share extension)

Follow `receive_sharing_intent` 1.8.1's iOS steps
(`~/.pub-cache/hosted/pub.dev/receive_sharing_intent-1.8.1/README.md`,
"iOS"). The Runner side (step 3 and the App Group) is done; on the Mac:

1. *File → New → Target → Share Extension*, named `Share Extension`, same
   deployment target as Runner (iOS 15).
2. Replace its `Info.plist` with the plugin's (text, URLs, images, video and
   files).
3. Add the App Groups capability to the extension with
   `group.com.telvox.telvoxChatMobileApp`, and a user-defined build setting
   `CUSTOM_GROUP_ID` with the same value.
4. In `ios/Podfile`, inside `target 'Runner'`, add
   `target 'Share Extension' do inherit! :search_paths end`; run `pod install`.
5. Runner → *Build Phases*: move *Embed Foundation Extensions* above
   *Thin Binary*.
6. `ShareViewController.swift`:

   ```swift
   import receive_sharing_intent

   class ShareViewController: RSIShareViewController {}
   ```

## 6. Incoming calls with the app closed (needs app and server work)

Android rings a closed app with an FCM data push (`backgroundCallPush`). iOS
does not let a closed app ring from an ordinary push: it needs Apple's VoIP
pushes (PushKit), sent straight to APNs, and each must show the call through
CallKit at once or iOS stops delivering them. Until this is built, calls on
iPhone ring only while the app is open.

- **App:** add the `voip` background mode to `Info.plist`; in `AppDelegate`,
  register a `PKPushRegistry`, pass the VoIP token to
  `SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP`,
  and on an incoming push call `showCallkitIncoming(…, fromPushKit: true)` and
  then `completion()` (see `flutter_callkit_incoming`'s `PUSHKIT.md`). The app
  sends `FlutterCallkitIncoming.getDevicePushTokenVoIP()` to the server with
  its push token.
- **Server** (`vnshah/telvox-chat`): store the VoIP token on the phone's
  `mobile_devices` row; for iPhones, `SendCallPushJob` sends an APNs push
  (token auth with the same `.p8`, topic `com.telvox.telvoxChatMobileApp.voip`,
  `apns-push-type: voip`, short expiry) with the call id and caller, instead of
  the FCM data push; a withdrawn call ends it the same way.

## 7. TestFlight and the App Store

1. App Store Connect → new app with the bundle ID; fill in the privacy
   details (contacts' messages and media, location when sent, microphone,
   camera, push token, device id).
2. Export compliance: the app uses HTTPS and an encrypted local database
   (SQLCipher). Decide with whoever handles compliance whether to set
   `ITSAppUsesNonExemptEncryption` in `Info.plist`; App Store Connect asks on
   every upload until it is set.
3. `flutter build ipa --release --dart-define-from-file=config/development.json`,
   then upload the `.ipa` (Xcode Organizer or Transporter) and add testers in
   TestFlight. Xcode signs release builds with the production push
   environment.
