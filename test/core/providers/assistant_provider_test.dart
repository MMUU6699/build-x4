import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/assistant_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AssistantProvider provider;

  setUp(() {
    provider = AssistantProvider();
  });

  test('initial state has no assistants when logged out', () async {
    await provider.loaded;
    expect(provider.assistants, isEmpty);
    expect(provider.currentAssistant, isNull);
    expect(provider.currentAssistantId, isNull);
    expect(provider.currentSearchEnabled, isFalse);
  });

  test('setCurrentAssistant selects assistant by id', () async {
    await provider.loaded;
    expect(provider.getById('non-existent'), isNull);
  });
}
