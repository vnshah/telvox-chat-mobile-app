/// Public build configuration. Never put credentials in Dart defines.
abstract final class AppConfig {
  static const environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://dev.themessenger.app',
  );
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
