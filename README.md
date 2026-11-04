# Telvox Chat mobile app

Flutter mobile application with Android Material 3 and iOS Cupertino-style
appearances, both using Telvox branding.

## Project handoff

Read [HANDOFF.md](HANDOFF.md) for the complete architecture, scope, Git state,
verification evidence, known blockers and continuation instructions. A sanitized
[Postman package](postman/mobile-api/README.md) is included locally.

## API integration

Startup uses the development API with no sample accounts or messages.

Implemented:

- Secure session restore, existing-account login and second-factor verification,
  business/number selection, paged inbox and contacts, and contact creation.
- Conversation history and catch-up, text sends with stable retry keys, quoted
  replies, reactions, and quick-reply selection.
- Image, video and document picking/sending, upload progress, size/type validation,
  and retries with a fresh multipart stream and the original idempotency key.
- Image viewing, video/audio playback and external document opening; shared media
  galleries for contacts and tickets. Remote media receives no API bearer token.
- Existing-template sending with body variables, text/media/location headers,
  authentication codes, dynamic URL/coupon buttons, carousel cards and offer expiry.
  Uncertain sends retain the original payload and key for manual retry.
- Contact name editing, assignment, favourites, close/reopen, block/DND,
  notes, tags and custom-field values.
- Ticket creation (existing/new contact), detail/history, subject, status, priority,
  assignment, disposition, notes and tags.

The live navigator excludes administration/reporting/billing screens and does not
provide template or quick-reply management. Voice recording/sending still needs
backend audio support; incoming audio can be played. Push, complete realtime and
call history remain deferred. Visible chats poll every 5 seconds and lists every
30 seconds; polling pauses in the background. Pending sends currently live in
memory, not a persistent offline outbox.

The single API origin setting is `AppConfig.apiBaseUrl` in
`lib/core/config/app_config.dart`, defaulting to `https://chat.telvox.dev`.
Every endpoint uses `MobileApi`; no screen hardcodes the host. An optional
`API_BASE_URL` build define overrides the default for the whole app. Example:

```bash
flutter build apk --debug --dart-define=API_BASE_URL=https://dev.themessenger.app  # older dev backend
```

Display timezone defaults to `Asia/Kolkata` in that same configuration and uses
IANA timezone data. `DATABASE_UTC_OFFSET_MINUTES` separately controls how unlabelled
server timestamps are interpreted (currently assumes India; confirm with backend).
Session credentials are encrypted in platform secure storage and scoped by API host.

Integration checks include `test/mobile_api_test.dart`, `test/mobile_ui_test.dart`,
`test/mobile_actions_test.dart`, `test/mobile_conversation_test.dart` and
`test/mobile_screens_test.dart`. On 29 October 2026, pinned Flutter 3.47.8 / Dart
3.13.7 passed static analysis and all 60 regression tests on Forge. Nine live
screen areas were additionally rendered from captured development API responses
on both Android and iOS styles, without layout errors. Private captures remain
outside source control. The debug APK builds with non-blocking plugin Kotlin
migration and Android SDK metadata warnings.

Conversation rendering decodes templates, interactive messages and form responses,
uses actual media, and strips activity-log HTML. It never substitutes the JSON
transport payload for a chat bubble. The inbox uses the same readable summaries.
Messages are built lazily; session-only caches retain lists/history when returning
to a page. Text sends appear immediately with a brief fade, independently of the
network response; background refreshes do not flash a loading indicator.

Free-form sends require an open service/referral window, a manageable assignee,
and an open, human-owned conversation/ticket. Blocked contacts cannot be sent to.
Templates bypass only the messaging-window restriction. DND blocks marketing
rather than legitimate service replies or utility/authentication templates,
matching the backend. Permissions are checked again when sending a template;
server-side checks remain authoritative.

Live checks: login, configuration, inbox/history, contact details, template listing
and details, quick replies, custom fields, ticket listing/create metadata, contact
search and all shared-media tabs succeeded. A temporary internal contact note was
created, edited and removed successfully. Measured reads took approximately
0.24–0.43 seconds; the attempted template send returned in 1.04 seconds.

The approved contact still has an expired service window in the API. The approved
list includes `test_by_ravin`, but Meta rejected the test send with error 132001:
the template does not exist in English. Its failed row is displayed with the
provider's reason. No successful test delivery is claimed. This account also has
no tickets and no configured ticket departments/statuses, so ticket mutation UI
is covered by contract tests rather than a successful live ticket lifecycle.

No physical Android device was attached for native file-picker/codec validation.
Credentials and test tokens are not stored in source or embedded in the APK.

## Environment

- Build server: `forge@122.179.143.220` (Ubuntu 24.04, x86_64)
- Project: `/home/forge/telvox-chat-mobile-app`
- Flutter 3.47.8; Dart 3.13.7
- Java 17; Android SDK in `~/Android/Sdk`
- SDK: `~/.local/flutter-sdk/flutter`
- Android identifier: `com.telvox.telvox_chat_mobile_app`
- Android Gradle Plugin 9.1.0, Gradle 9.3.1, Kotlin plugin 2.4.0

The machine-specific `dev.env` file is ignored by Git. It supplies tool paths.
For a new terminal in this checkout:

```sh
source ./dev.env
flutter --version
flutter doctor -v
```

The `.fvmrc` pins the intended Flutter version for users of FVM. FVM is optional;
this machine uses its directly installed Flutter SDK.

## Run checks and build

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --reporter expanded
flutter build apk --debug
```

The debug APK is `build/app/outputs/flutter-apk/app-debug.apk`.
For an optimized internal-review APK, use `flutter build apk --release`; its
output is `build/app/outputs/flutter-apk/app-release.apk`. Both currently use
the same debug signing key, so these are internal previews. Production signing
and store publication are separate tasks.

## Appearance

Android uses Material 3 navigation bars and rails, tonal action buttons, search
bars, chips, forms, dialogs, date pickers, switches, and Roboto typography. iOS
uses Cupertino navigation and tabs, segmented filters, buttons, search and text
fields, pickers, action sheets, dialogs, and switches. The iPhone appearance uses
the system font; appearance previews on other devices use bundled Geist.

Both appearances retain Telvox green, the text-only wordmark, and compact
business lists. Chat bubbles fit their content, with inline timestamps and
receipts, larger emoji-only messages, and tight spacing within a sender's group.
Changing sender or a gap of more than five minutes starts a new group and tail.
The launcher uses the supplied Telvox speech-bubble and double-check mark in
theme green (`#176B46`) and light mint (`#F4F7F3`). The canonical artwork is
`assets/brand/telvox-chat-mark.svg`; `assets/brand/mark.png` is its 1024 px master.
Android includes legacy density icons, a vector adaptive foreground, and a
monochrome layer for themed launchers. The symbol stays inside the adaptive
safe area; the launcher supplies its circular or rounded mask.
Geist's license is in `assets/fonts/OFL.txt`; Roboto's is in
`assets/fonts/Roboto-OFL.txt`. Both are registered in Flutter's license registry.

Screens, state and requests live in `lib/mobile/`, starting from
`lib/mobile/app.dart`. `lib/ui/` holds what they share: `theme.dart` (the two
visual configurations), `platform.dart` (platform-aware controls),
`chat_message.dart` (message bubbles, receipt layout and the anchored menu),
`conversation.dart` (swipe to reply) and `page_slide.dart` (page transitions
and the swipe back from the left edge). Review screenshots generated by tests
are written to `build/review/`.

Sign-in is for existing accounts only; there is no account-creation screen.
An iOS runner/Xcode project exists; an iPhone build needs a Mac with Xcode,
signing and device testing.

## Public configuration

`lib/core/config/app_config.dart` reads `APP_ENV` and `API_BASE_URL` from Dart
defines. The default API origin is `https://chat.telvox.dev`.

```sh
cp config/development.example.json config/development.json
flutter build apk --debug --dart-define-from-file=config/development.json
```

The copied configuration is ignored by Git. Defines are embedded in the app;
Meta tokens, Firebase service-account credentials, and Laravel secrets belong
on the backend. Confirm the app identifier before Firebase registration.

Keep `pubspec.lock` in version control. The integration status and remaining work
are listed above.

## Verified on this Linux checkout

The Forge setup passed formatting, static analysis, all twenty-four original UI
tests, and an Android debug APK build with Flutter 3.47.8 and Dart 3.13.7.
The chat refinement passed all thirty UI tests, static analysis, and an optimized
internal-review APK build on the Forge server. The six new tests cover compact sizing, receipt/text
separation at increased text scales, grouping, joined emoji, reactions, and
keyboard-open message menus on both platforms. Review images are generated in
`build/ui-previews/chat-behavior/`; validation/build logs are in
`build/chat-refinement/`. The SDK includes Android platforms 34, 35 and 36,
build tools 36.0.0, NDK 28.2.13676358, and CMake 3.22.1.

The current Firebase plugin emits a Kotlin Gradle Plugin migration warning
about future Flutter versions. The pinned setup builds successfully; review
plugin compatibility before upgrading Flutter. Native phone installation and iPhone runtime behaviour have not
been tested in this setup session.
