import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Kelivo/core/services/preferences/app_preferences.dart';

final class BusinessTestHarness {
  BusinessTestHarness._(this.preferences);

  final BusinessPreferences preferences;

  static Future<BusinessTestHarness> create({
    Map<String, Object?> initial = const <String, Object?>{},
    Map<String, Object> localInitial = const <String, Object>{},
  }) async {
    final mockValues = <String, Object>{...localInitial};
    initial.forEach((k, v) {
      if (v != null) {
        if (v is String ||
            v is bool ||
            v is int ||
            v is double ||
            v is List<String>) {
          mockValues[k] = v;
        }
      }
    });
    AppPreferences.resetForTesting();
    SharedPreferences.setMockInitialValues(mockValues);
    final preferences = BusinessPreferences();
    await preferences.load();
    return BusinessTestHarness._(preferences);
  }

  Future<void> close() async {
    AppPreferences.resetForTesting();
  }
}

Future<BusinessTestHarness> createBusinessTestHarness({
  Map<String, Object?> initial = const <String, Object?>{},
  Map<String, Object> localInitial = const <String, Object>{},
}) async {
  final harness = await BusinessTestHarness.create(
    initial: initial,
    localInitial: localInitial,
  );
  addTearDown(harness.close);
  return harness;
}

BusinessPreferences createBusinessTestPreferences({
  Map<String, Object> localInitial = const <String, Object>{},
}) {
  AppPreferences.resetForTesting();
  SharedPreferences.setMockInitialValues(localInitial);
  final preferences = BusinessPreferences();
  return preferences;
}
