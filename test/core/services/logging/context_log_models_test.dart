import 'package:Kelivo/core/services/logging/context_log_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('snapshot json roundtrip', () {
    final snapshot = ContextLogSnapshot(
      timestamp: DateTime.utc(2026, 8, 13, 12, 0, 0),
      conversationId: 'c1',
      assistantName: 'Build X',
      provider: 'supabase',
      model: 'mistral-medium-latest',
      messages: [
        ContextLogMessage(
          role: 'system',
          segments: [
            ContextSegment(
              source: ContextSource.systemPrompt,
              text: 'You are helpful.',
              tokens: 5,
            ),
          ],
        ),
      ],
      totalTokens: 5,
    );

    final decoded = ContextLogSnapshot.fromJson(snapshot.toJson());
    expect(decoded.conversationId, 'c1');
    expect(decoded.assistantName, 'Build X');
    expect(decoded.model, 'mistral-medium-latest');
    expect(decoded.totalTokens, 5);
    expect(decoded.messages, hasLength(1));
    expect(decoded.messages.first.segments, hasLength(1));
  });

  test('last tagged segment absorbs content that grew after tagging', () {
    final message = <String, dynamic>{
      'role': 'user',
      'content': 'PREFIX user text with data:image/png;base64,QUJDREVGR0g=',
      kelivoContextSegmentsKey: [
        ContextSegmentTags.item(
          source: ContextSource.systemPrompt,
          length: 6,
          meta: {'kind': 'full'},
        ),
        ContextSegmentTags.item(source: ContextSource.chatHistory, length: 9),
      ],
    };

    final segments = segmentsFromTaggedMessage(message);
    expect(segments, hasLength(2));
    expect(segments.first.source, ContextSource.systemPrompt);
    expect(segments.first.text, 'PREFIX');
    expect(segments.last.source, ContextSource.chatHistory);
    expect(segments.last.text, contains('<omitted'));
    expect(segments.last.text, isNot(contains('QUJDREVGR0g=')));
  });
}
