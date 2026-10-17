import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/assistant.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Assistant deletable field migration', () {
    test('does not export deletable in assistant JSON', () {
      const assistant = Assistant(id: 'assistant-1', name: 'Assistant 1');

      expect(assistant.toJson(), isNot(contains('deletable')));
      expect(
        Assistant.encodeList(const [assistant]),
        isNot(contains('deletable')),
      );
    });
  });
}
