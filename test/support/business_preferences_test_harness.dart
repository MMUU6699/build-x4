import 'package:Kelivo/core/services/preferences/app_preferences.dart';

final class BusinessPreferencesTestHarness {
  BusinessPreferencesTestHarness._();

  static Future<BusinessPreferencesTestHarness> create() async {
    return BusinessPreferencesTestHarness._();
  }

  Future<BusinessPreferencesTestSession> open() async {
    final preferences = BusinessPreferences();
    await preferences.load();
    return BusinessPreferencesTestSession._(preferences);
  }

  Future<void> dispose() async {}
}

final class BusinessPreferencesTestSession {
  BusinessPreferencesTestSession._(this.preferences);

  final BusinessPreferences preferences;

  Future<void> close() async {}
}
