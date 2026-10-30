/// Public build configuration. Never put credentials in Dart defines.
abstract final class AppConfig {
  static const environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://chat.telvox.dev',
  );
  // Firebase app identifiers for push (from google-services.json). They are
  // public client identifiers, not secrets; the server's FCM key never ships.
  // Leave unset to build without push notifications.
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static bool get firebaseConfigured =>
      firebaseApiKey != '' &&
      firebaseAppId != '' &&
      firebaseSenderId != '' &&
      firebaseProjectId != '';
  static const preview = bool.fromEnvironment(
    'UI_PREVIEW',
    defaultValue: false,
  );
  static const displayTimezone = String.fromEnvironment(
    'DISPLAY_TIMEZONE',
    defaultValue: 'Asia/Kolkata',
  );
  // Plain database dates have no offset. Keep the assumption explicit and centralized.
  // Confirm this against the server before enabling live timestamp conversion.
  static const databaseUtcOffsetMinutes = int.fromEnvironment(
    'DATABASE_UTC_OFFSET_MINUTES',
    defaultValue: 330,
  );
}
