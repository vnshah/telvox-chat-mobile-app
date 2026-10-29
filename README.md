# Telvox Chat mobile app

Flutter mobile UI preview with Android Material 3 and iOS Cupertino-style
appearances, both using Telvox branding.

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

## UI preview

The app opens the sign-in preview with sample values already filled in. Tap
**Sign in**, select **Studio North**, and explore the inbox. These screens do
not authenticate against a server or send WhatsApp messages.

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

Screen areas:

- Access: existing-account sign-in, recovery, code verification, password reset,
  and workspace selection.
- Conversations: filtered inbox, chat, contextual replies and reactions,
  attachments, contacts, editing, assignments, tags, notes, custom fields,
  media, and customer preferences.
- Messaging tools: templates, variables and preview, template creation,
  quick replies, and AI-assist screens.
- Commerce: catalogue, products, sharing, orders, and order details.
- Support: ticket list, creation, details, status and disposition controls;
  call history, incoming-call and active-call layouts.
- Business: campaigns, audience/message/review flow, automation journeys,
  chatbots, WhatsApp flows, reports, billing, and business configuration.
- Management: reusable list/details/create/edit screens for organization,
  integrations, ticket configuration, and system modules.
- Account: profile, business profile, notification preferences, security,
  devices, help, about, legal placeholders, and notification permission preview.
- States: empty, loading, offline, and connection-error layouts.

**More > View screens** opens the screen library. Under **Preview appearance**,
choose **Android**, **iOS**, or **Device**. Device follows the actual operating
system. The preview selection applies to all routes and resets when the app
restarts. Search text is retained when the appearance changes.

The project is still Android-first: Cupertino UI is implemented and covered by
widget tests, and can be reviewed in the Android APK. There is no iOS runner or
signed iPhone binary in this repository yet; an actual iOS build needs an iOS
host project, a supported Mac/Xcode setup, and device testing.

Sign-in is for existing accounts only; there is no account-creation screen or route.
Workspace rows and inbox, contact, and ticket lists stay compact. Chat retains
contextual replies, forwarding, starring, message info, and local deletion.
Long-press a message (or right-click in a desktop preview) to keep it visible
between a floating reaction picker and action menu. The menu fits above an open
keyboard; long selections and action lists scroll independently. Selecting the
same reaction removes it. Tap a reaction badge to view/remove it, or use **+**
in the picker for more emoji. Badges sit against the bubble's lower edge and
reserve space below its text. Swipe right to reply; quotes show the sender.
Quick replies, AI assist, templates, and product sharing remain under **Attach**.
The main tabs put search directly below the header. New messages use a short
140 ms transition in place; reduced motion shows them immediately. Reactions
and swipe return transitions also respect reduced motion.

Search, filters, draft replies, customer notes, tags, assignments, and some
forms update in-memory preview state. State resets when the app restarts.
AI outputs, media, calls, payments, reports, policy copy, and device permissions
are illustrative UI. No real audio recording, call, payment, network request,
Firebase initialization, or Laravel integration is performed.

`lib/ui/` contains the theme, fixtures, shared controls, and screens.
`lib/ui/platform.dart` provides platform-aware controls; `theme.dart` contains
the two visual configurations and shared screen layouts. `chat_message.dart`
contains message bubbles, receipt layout, reactions, and the anchored menu.
`lib/app/app.dart` holds the routes. The UI tests cover all review routes on both appearances, compact/tablet
layouts, larger text, input and filter state, validation, tabs, pickers, sheets,
confirmation dialogs, and key preview journeys.
`build/ui-previews/` contains rendered review screenshots generated by tests.

## Public configuration

`lib/core/config/app_config.dart` reads `APP_ENV` and `API_BASE_URL` from Dart
defines. No backend URL is set by default.

```sh
cp config/development.example.json config/development.json
flutter build apk --debug --dart-define-from-file=config/development.json
```

The copied configuration is ignored by Git. Defines are embedded in the app;
Meta tokens, Firebase service-account credentials, and Laravel secrets belong
on the backend. Confirm the app identifier before Firebase registration.

Keep `pubspec.lock` in version control. The next stage is the Laravel mobile
authentication/API contract, followed by the first app flow.

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
