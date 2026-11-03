# Share to Telvox Chat on iOS

Android needs nothing more: the intent filters in `AndroidManifest.xml` put
Telvox Chat in the share sheet. On iOS the share sheet only lists apps that
have a **Share Extension**: a second target in the Xcode project, signed
with the team's certificate, which cannot be added or checked without Xcode.
The Flutter side (`lib/mobile/share_intake.dart`, `share_sheet.dart`) is the
same on both platforms; the extension only hands the files over.

Done once, on a Mac with Xcode, by someone in the Apple developer team:

1. **App Group.** In the Apple Developer portal create
   `group.com.telvox.telvoxChatMobileApp`, and add it (Signing &
   Capabilities → App Groups) to the **Runner** target.
2. **Extension target.** File → New → Target → *Share Extension*, named
   `ShareExtension`, language Swift; do not activate its scheme. Set its
   deployment target to the Runner's. Add the same App Group to it.
3. **Extension code.** Replace `ShareViewController.swift` with:

   ```swift
   import receive_sharing_intent

   class ShareViewController: RSIShareViewController {
     // Hand the files to the app at once, as WhatsApp does.
     override func shouldAutoRedirect() -> Bool { true }
   }
   ```

   and remove the storyboard's `MainInterface` reference from its
   `Info.plist` if Xcode added one.
4. **Extension Info.plist.** Under `NSExtension` → `NSExtensionAttributes`
   set `NSExtensionActivationRule` to accept up to 10 images, 10 movies and
   10 files (`NSExtensionActivationSupportsImageWithMaxCount`,
   `…MovieWithMaxCount`, `…FileWithMaxCount` = 10), and add
   `AppGroupId` = `$(CUSTOM_GROUP_ID)`.
5. **Runner Info.plist.** Add the URL scheme the extension opens the app
   with: `CFBundleURLTypes` → `CFBundleURLSchemes` =
   `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)`, and `AppGroupId` =
   `$(CUSTOM_GROUP_ID)`.
6. **Build setting.** On both targets add the user-defined setting
   `CUSTOM_GROUP_ID` = `group.com.telvox.telvoxChatMobileApp`.
7. **Podfile.** Inside `target 'Runner'`, add
   `target 'ShareExtension' do inherit! :search_paths end`, then
   `pod install`.
8. Build, share a photo from Photos, and pick Telvox Chat: the app opens on
   *Send to…*.

The plugin's own guide, with screenshots of each Xcode step:
https://pub.dev/packages/receive_sharing_intent (section "iOS").
