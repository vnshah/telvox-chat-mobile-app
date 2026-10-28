/// Public build configuration. Credentials must never be supplied as defines.
abstract final class AppConfig {
  static const environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  /// Empty until a mobile API endpoint is agreed with the Laravel backend.
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
}
