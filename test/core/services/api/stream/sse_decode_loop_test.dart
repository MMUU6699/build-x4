import 'dart:async';

import 'package:Kelivo/core/services/api/stream/sse_decode_loop.dart';
import 'package:Kelivo/core/services/api/stream/sse_event.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDecoder implements StreamChunkDecoder {
  _FakeDecoder({this.eventChunks = const {}, this.closedChunks = const []});

  final Map<String, List<StreamChunk>> eventChunks;
  final List<StreamChunk> closedChunks;
  bool closedCalled = false;

  @override
  DecodeResult accept(SseEvent event) {
    final chunks = eventChunks[event.data] ?? const [];
    return DecodeResult(chunks: chunks, completed: event.data == '[DONE]');
  }

  @override
  List<StreamChunk> onClosed() {
    closedCalled = true;
    return closedChunks;
  }
}

void main() {
  test('[DONE] completes decodeSseEvents loop', () async {
    final decoder = _FakeDecoder(
      eventChunks: {
        'msg1': [const TextDelta(id: 't1', text: 'Hello ')],
        '[DONE]': [const ToolCallEnd('call_1')],
      },
    );

    final chunks = await decodeSseEvents(
      Stream<SseEvent>.fromIterable([
        const SseEvent(data: 'msg1'),
        const SseEvent(data: '[DONE]'),
      ]),
      decoder,
    ).toList();

    expect(chunks.whereType<TextDelta>().single.text, 'Hello ');
    expect(chunks.whereType<ToolCallEnd>().single.id, 'call_1');
    expect(decoder.closedCalled, isTrue);
  });

  test('onClosed yields chunks when the SSE stream omits [DONE]', () async {
    final decoder = _FakeDecoder(
      eventChunks: {
        'msg1': [const TextDelta(id: 't1', text: 'World')],
      },
      closedChunks: [const ToolCallEnd('call_1')],
    );

    final chunks = await decodeSseEvents(
      Stream<SseEvent>.fromIterable([const SseEvent(data: 'msg1')]),
      decoder,
    ).toList();

    expect(chunks.whereType<TextDelta>().single.text, 'World');
    expect(chunks.whereType<ToolCallEnd>().single.id, 'call_1');
    expect(decoder.closedCalled, isTrue);
  });

  test('stream error propagates through decodeSseEvents', () async {
    final decoder = _FakeDecoder();
    final controller = StreamController<SseEvent>();
    final errorSeen = Completer<Object>();

    decodeSseEvents(controller.stream, decoder).listen(
      (_) {},
      onError: (Object error) {
        errorSeen.complete(error);
      },
    );

    final err = StateError('network failed');
    controller.addError(err);
    await controller.close();

    final received = await errorSeen.future;
    expect(received, same(err));
  });
}
