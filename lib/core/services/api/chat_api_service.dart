import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../../config/supabase_config.dart';
import '../../models/auto_retry_options.dart';
import '../../models/model_spec.dart';
import '../../models/reasoning_request.dart';
import '../../models/token_usage.dart';
import '../../utils/multimodal_input_utils.dart';
import '../../../utils/unicode_sanitizer.dart';
import 'chat_api_helpers.dart';
import 'generation/text_generation_result.dart';
import 'stream/stream_chunk.dart';
import 'stream/stream_chunk_handler.dart';

export 'chat_api_helpers.dart' show ToolCallHandler;
export 'generation/text_generation_result.dart';
export 'generation/tool_loop_runner.dart';

class ChatApiService {
  static final Map<String, CancelToken> _activeCancelTokens =
      <String, CancelToken>{};

  static const String fixedModel = 'mistral-medium-latest';

  static bool supportsOpenAIImagesApiRouting(dynamic config, String modelId) {
    return false;
  }

  static bool isImageGenerationModel(String modelId) {
    final normalized = modelId.toLowerCase();
    return normalized.contains('image') ||
        normalized.startsWith('imagen-') ||
        normalized.startsWith('chatgpt-image-') ||
        normalized == 'dall-e-2' ||
        normalized == 'dall-e-3';
  }

  static Future<List<Map<String, dynamic>>> stripUnsupportedMediaFromMessages(
    List<Map<String, dynamic>> messages,
    ModelSpec? spec,
  ) async {
    final supportsImage = spec?.input.contains(Modality.image) ?? true;
    final result = <Map<String, dynamic>>[];
    for (final m in messages) {
      final copy = Map<String, dynamic>.from(m);
      if (!supportsImage) {
        copy.remove(multimodalInternalMediaPathsKey);
      }
      result.add(copy);
    }
    return result;
  }

  static void cancelRequest(String requestId) {
    final key = requestId.trim();
    if (key.isEmpty) return;
    final token = _activeCancelTokens.remove(key);
    if (token == null) return;
    try {
      if (!token.isCancelled) token.cancel('cancelled');
    } catch (_) {}
  }

  static Stream<StreamChunk> sendMessageStream({
    dynamic config,
    String? modelId,
    required List<Map<String, dynamic>> messages,
    List<String>? userImagePaths,
    ReasoningRequest reasoning = ReasoningRequest.auto,
    double? temperature,
    double? topP,
    int? maxTokens,
    List<Map<String, dynamic>>? tools,
    ToolCallHandler? onToolCall,
    Map<String, String>? extraHeaders,
    Map<String, dynamic>? extraBody,
    bool stream = true,
    String? requestId,
    String? conversationId,
    bool allowImagesApiRouting = true,
    bool ocrActive = false,
    bool builtInSearchOnly = false,
    bool skipImageParsing = false,
    bool parseMarkdownImageLinks = true,
    bool textOnly = false,
    AutoRetryOptions? retryOverride,
  }) async* {
    final sessionToken = CancelToken();
    final rid = (requestId ?? '').trim();
    if (rid.isNotEmpty) {
      final prev = _activeCancelTokens.remove(rid);
      try {
        prev?.cancel('replaced');
      } catch (_) {}
      _activeCancelTokens[rid] = sessionToken;
    }

    try {
      if (sessionToken.isCancelled) return;

      // Extract system instructions and format inputs for Mistral
      String instructions = '';
      final inputs = <Map<String, dynamic>>[];

      for (final msg in messages) {
        final role = msg['role']?.toString() ?? 'user';
        final rawContent = msg['content'];
        String contentStr = '';
        if (rawContent is String) {
          contentStr = UnicodeSanitizer.sanitize(rawContent);
        } else if (rawContent is List) {
          contentStr = rawContent
              .map((p) => p is Map ? (p['text'] ?? '') : p.toString())
              .join(' ');
        }
        if (role == 'system') {
          instructions = instructions.isEmpty
              ? contentStr
              : '$instructions\n$contentStr';
        } else {
          inputs.add({'role': role, 'content': contentStr});
        }
      }

      if (inputs.isEmpty) {
        inputs.add({'role': 'user', 'content': 'Hello'});
      }

      // Local/offline provider path. Production Build X uses the Supabase chat
      // function; an explicit loopback/private provider config still talks to a
      // real local OpenAI-compatible server.
      if (config != null &&
          (SupabaseConfig.isUnconfigured || _isLocalProvider(config))) {
        yield* _sendLocalProvider(
          config: config,
          modelId: modelId,
          messages: messages,
          temperature: temperature,
          topP: topP,
          maxTokens: maxTokens,
          tools: tools,
          extraHeaders: extraHeaders,
          extraBody: extraBody,
          onToolCall: onToolCall,
          parseMarkdownImageLinks: parseMarkdownImageLinks,
          skipImageParsing: skipImageParsing,
          textOnly: textOnly,
          allowImagesApiRouting: allowImagesApiRouting,
        );
        return;
      }

      if (SupabaseConfig.isUnconfigured) {
        throw StateError(
          'Chat backend is not configured. Set SUPABASE_URL and '
          'SUPABASE_ANON_KEY, or deploy the chat function.',
        );
      }

      final client = SupabaseConfig.client;
      await SupabaseConfig.ensureValidToken();
      final accessToken = client.auth.currentSession?.accessToken;
      final body = <String, dynamic>{
        'model': fixedModel,
        'messages': inputs,
        'instructions': instructions,
        'tools': tools ?? const <Map<String, dynamic>>[],
        'tool_choice': 'auto',
        'stream': stream,
        'temperature': temperature ?? 0.7,
        'max_tokens': maxTokens ?? 2048,
        'top_p': topP ?? 1.0,
      };

      if (stream) {
        yield* _streamEdgeCompletion(
          body: body,
          accessToken: accessToken,
          sessionToken: sessionToken,
          onToolCall: onToolCall,
        );
        return;
      }

      final res = await client.functions.invoke(
        'chat',
        body: body,
        headers: {
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
      );
      if (res.status >= 400 || res.data == null) {
        throw StateError(
          'Chat backend returned HTTP ${res.status}: ${res.data}',
        );
      }
      final data = res.data is String
          ? jsonDecode(res.data as String)
          : res.data;
      if (data is! Map<String, dynamic>) {
        throw StateError('Chat backend returned an unexpected response.');
      }
      yield* _parseEdgeCompletion(data, onToolCall: onToolCall);
    } finally {
      if (rid.isNotEmpty) {
        _activeCancelTokens.remove(rid);
      }
    }
  }

  static bool _isLocalProvider(dynamic config) {
    final uri = Uri.tryParse(config.baseUrl?.toString().trim() ?? '');
    final host = uri?.host.toLowerCase() ?? '';
    if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
      return true;
    }
    if (host == '10.0.2.2') return true;
    if (host.startsWith('10.') || host.startsWith('192.168.')) return true;
    if (host.startsWith('172.')) {
      final parts = host.split('.');
      if (parts.length == 4) {
        final second = int.tryParse(parts[1]) ?? 0;
        return second >= 16 && second <= 31;
      }
    }
    return false;
  }

  static Future<List<Map<String, dynamic>>> _prepareLocalProviderMessages(
    List<Map<String, dynamic>> messages, {
    required bool parseMarkdownImageLinks,
    required bool skipImageParsing,
    required bool textOnly,
    required bool allowImagesApiRouting,
  }) async {
    final prepared = <Map<String, dynamic>>[];
    final parseImages =
        parseMarkdownImageLinks &&
        !skipImageParsing &&
        !textOnly &&
        allowImagesApiRouting;

    for (final message in messages) {
      final role = message['role']?.toString() ?? 'user';
      final rawContent = message['content'];

      if (rawContent is String) {
        final text = UnicodeSanitizer.sanitize(rawContent);
        if (!parseImages ||
            !shouldParseMarkdownImages(
              text,
              skipImageParsing: skipImageParsing,
            )) {
          prepared.add({'role': role, 'content': text});
          continue;
        }
        final parsed = await parseTextAndImages(
          text,
          allowRemoteImages: true,
          allowLocalImages: true,
          skipImageParsing: false,
        );
        if (parsed.images.isEmpty) {
          prepared.add({'role': role, 'content': parsed.text});
          continue;
        }
        final parts = <Map<String, dynamic>>[];
        if (parsed.text.isNotEmpty) {
          parts.add({'type': 'text', 'text': parsed.text});
        }
        for (final image in parsed.images) {
          final url = switch (image.kind) {
            'url' || 'data' => image.src,
            'path' => await tryEncodeBase64File(image.src, withPrefix: true),
            _ => null,
          };
          if (url != null && url.isNotEmpty) {
            parts.add({
              'type': 'image_url',
              'image_url': {'url': url},
            });
          }
        }
        prepared.add({
          'role': role,
          'content': parts.isEmpty ? parsed.text : parts,
        });
        continue;
      }

      if (rawContent is List) {
        final parts = <Map<String, dynamic>>[];
        for (final part in rawContent) {
          if (part is! Map) continue;
          final type = part['type']?.toString();
          if (type == 'text') {
            parts.add({
              'type': 'text',
              'text': UnicodeSanitizer.sanitize(part['text']?.toString() ?? ''),
            });
          } else if (type == 'image_url' && parseImages) {
            parts.add(Map<String, dynamic>.from(part));
          }
        }
        prepared.add({'role': role, 'content': parts.isEmpty ? '' : parts});
        continue;
      }

      prepared.add({'role': role, 'content': rawContent?.toString() ?? ''});
    }
    return prepared;
  }

  static Stream<StreamChunk> _sendLocalProvider({
    required dynamic config,
    required String? modelId,
    required List<Map<String, dynamic>> messages,
    required double? temperature,
    required double? topP,
    required int? maxTokens,
    required List<Map<String, dynamic>>? tools,
    required Map<String, String>? extraHeaders,
    required Map<String, dynamic>? extraBody,
    required ToolCallHandler? onToolCall,
    required bool parseMarkdownImageLinks,
    required bool skipImageParsing,
    required bool textOnly,
    required bool allowImagesApiRouting,
  }) async* {
    final baseUrl = config.baseUrl?.toString().trim() ?? '';
    if (baseUrl.isEmpty) {
      throw StateError('The selected provider has no base URL.');
    }
    final apiKey = config.apiKey?.toString() ?? '';
    final localMessages = await _prepareLocalProviderMessages(
      messages,
      parseMarkdownImageLinks: parseMarkdownImageLinks,
      skipImageParsing: skipImageParsing,
      textOnly: textOnly,
      allowImagesApiRouting: allowImagesApiRouting,
    );
    final body = <String, dynamic>{
      'model': modelId ?? fixedModel,
      'messages': localMessages,
      'stream': false,
      if (temperature != null) 'temperature': temperature,
      if (topP != null) 'top_p': topP,
      if (maxTokens != null) 'max_tokens': maxTokens,
      if (tools != null && tools.isNotEmpty) 'tools': tools,
      ...?extraBody,
    };
    final res = await Dio().post(
      '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/chat/completions',
      data: body,
      options: Options(
        responseType: ResponseType.json,
        validateStatus: (_) => true,
        headers: {
          'Content-Type': 'application/json',
          if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
          ...?extraHeaders,
        },
      ),
    );
    final status = res.statusCode ?? 500;
    if (status >= 400) {
      throw StateError('Provider returned HTTP $status: ${res.data}');
    }
    final raw = res.data;
    final data = raw is String ? jsonDecode(raw) : raw;
    if (data is! Map) {
      throw StateError('Provider returned an unexpected response.');
    }
    yield* _parseEdgeCompletion(
      Map<String, dynamic>.from(data),
      onToolCall: onToolCall,
    );
  }

  static Stream<StreamChunk> _parseEdgeCompletion(
    Map<String, dynamic> data, {
    ToolCallHandler? onToolCall,
  }) async* {
    var finishReason = 'stop';
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty) {
      for (var i = 0; i < choices.length; i++) {
        final choice = choices[i];
        if (choice is! Map) continue;
        final message = choice['message'] ?? choice['delta'];
        if (message is! Map) continue;
        final content = _contentText(message['content']);
        if (content.isNotEmpty) {
          yield TextStart('text-$i');
          yield TextDelta(id: 'text-$i', text: content);
          yield TextEnd('text-$i');
        }
        final toolCalls = message['tool_calls'] ?? message['toolCalls'];
        if (toolCalls is List) {
          for (var j = 0; j < toolCalls.length; j++) {
            final raw = toolCalls[j];
            if (raw is! Map) continue;
            final tc = Map<String, dynamic>.from(raw);
            final fn = tc['function'] is Map
                ? Map<String, dynamic>.from(tc['function'] as Map)
                : tc;
            final id = tc['id']?.toString().trim().isNotEmpty == true
                ? tc['id'].toString()
                : 'call_$j';
            final name = fn['name']?.toString() ?? '';
            final args = fn['arguments'];
            yield* _emitToolCall(
              id: id,
              name: name,
              rawArgs: args,
              onToolCall: onToolCall,
            );
          }
        }
        final reason = choice['finish_reason'] ?? choice['finishReason'];
        if (reason != null) finishReason = reason.toString();
      }
    } else {
      final outputs = data['outputs'];
      if (outputs is List) {
        for (var i = 0; i < outputs.length; i++) {
          final output = outputs[i];
          if (output is! Map) continue;
          final content = _contentText(output['content'] ?? output['text']);
          if (content.isNotEmpty) {
            yield TextStart('text-$i');
            yield TextDelta(id: 'text-$i', text: content);
            yield TextEnd('text-$i');
          }
          final toolCalls = output['tool_calls'] ?? output['toolCalls'];
          if (toolCalls is List) {
            for (var j = 0; j < toolCalls.length; j++) {
              final raw = toolCalls[j];
              if (raw is! Map) continue;
              final tc = Map<String, dynamic>.from(raw);
              final fn = tc['function'] is Map
                  ? Map<String, dynamic>.from(tc['function'] as Map)
                  : tc;
              final id = tc['id']?.toString().trim().isNotEmpty == true
                  ? tc['id'].toString()
                  : 'call_$j';
              yield* _emitToolCall(
                id: id,
                name: fn['name']?.toString() ?? '',
                rawArgs: fn['arguments'],
                onToolCall: onToolCall,
              );
            }
          }
        }
      }
    }

    final usage = _tokenUsage(data['usage']);
    if (usage != null) yield Usage(usage);
    yield Finish(finishReason: finishReason, model: fixedModel);
  }

  static Stream<StreamChunk> _streamEdgeCompletion({
    required Map<String, dynamic> body,
    required String? accessToken,
    required CancelToken sessionToken,
    ToolCallHandler? onToolCall,
  }) async* {
    final dio = Dio();
    final res = await dio.post(
      '${SupabaseConfig.supabaseUrl}/functions/v1/chat',
      data: body,
      options: Options(
        responseType: ResponseType.stream,
        validateStatus: (_) => true,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
          'apikey': SupabaseConfig.supabaseAnonKey,
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
      ),
      cancelToken: sessionToken,
    );

    final responseBody = res.data;
    if (responseBody is! ResponseBody) {
      throw StateError('Chat backend returned an unexpected response.');
    }
    if ((res.statusCode ?? 500) >= 400) {
      final raw = await utf8.decoder.bind(responseBody.stream).join();
      throw StateError('Chat backend returned HTTP ${res.statusCode}: $raw');
    }

    var textOpen = false;
    var finishReason = 'stop';
    final toolCalls = <int, Map<String, String>>{};
    Map<String, dynamic>? usage;

    await for (final line
        in responseBody.stream
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (sessionToken.isCancelled) return;
      final trimmed = line.trim();
      if (!trimmed.startsWith('data:')) continue;
      final payload = trimmed.substring(5).trim();
      if (payload.isEmpty) continue;
      if (payload == '[DONE]') break;

      dynamic decoded;
      try {
        decoded = jsonDecode(payload);
      } catch (_) {
        continue;
      }
      if (decoded is! Map) continue;

      final error = decoded['error'];
      if (error != null) {
        final message = error is Map
            ? (error['message'] ?? error['error'] ?? error)
            : error;
        throw StateError('Chat backend error: $message');
      }

      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty && choices.first is Map) {
        final choice = choices.first as Map;
        final rawDelta = choice['delta'] ?? choice['message'];
        if (rawDelta is Map) {
          final delta = Map<String, dynamic>.from(rawDelta);
          final content = _contentText(delta['content']);
          if (content.isNotEmpty) {
            if (!textOpen) {
              yield const TextStart('text-0');
              textOpen = true;
            }
            yield TextDelta(id: 'text-0', text: content);
          }

          final deltas = delta['tool_calls'] ?? delta['toolCalls'];
          if (deltas is List) {
            for (var i = 0; i < deltas.length; i++) {
              final raw = deltas[i];
              if (raw is! Map) continue;
              final tc = Map<String, dynamic>.from(raw);
              final index = int.tryParse(tc['index']?.toString() ?? '') ?? i;
              final acc = toolCalls.putIfAbsent(
                index,
                () => <String, String>{},
              );
              final id = tc['id']?.toString();
              if (id != null && id.isNotEmpty) acc['id'] = id;
              final fn = tc['function'] is Map
                  ? Map<String, dynamic>.from(tc['function'] as Map)
                  : tc;
              final name = fn['name']?.toString();
              if (name != null && name.isNotEmpty) {
                acc['name'] = '${acc['name'] ?? ''}$name';
              }
              final args = fn['arguments'];
              if (args is String) {
                acc['arguments'] = '${acc['arguments'] ?? ''}$args';
              } else if (args != null) {
                acc['arguments'] =
                    '${acc['arguments'] ?? ''}${jsonEncode(args)}';
              }
            }
          }
        }
        final reason = choice['finishReason'] ?? choice['finish_reason'];
        if (reason != null) finishReason = reason.toString();
      }

      final rawUsage = decoded['usage'];
      if (rawUsage is Map) {
        usage = Map<String, dynamic>.from(rawUsage);
      }
    }

    if (textOpen) yield const TextEnd('text-0');

    final indices = toolCalls.keys.toList()..sort();
    for (final index in indices) {
      final acc = toolCalls[index]!;
      final id = acc['id']?.trim().isNotEmpty == true
          ? acc['id']!
          : 'call_$index';
      yield* _emitToolCall(
        id: id,
        name: acc['name'] ?? '',
        rawArgs: acc['arguments'] ?? '{}',
        onToolCall: onToolCall,
      );
    }

    final tokenUsage = _tokenUsage(usage);
    if (tokenUsage != null) yield Usage(tokenUsage);
    yield Finish(finishReason: finishReason, model: fixedModel);
  }

  static Stream<StreamChunk> _emitToolCall({
    required String id,
    required String name,
    required dynamic rawArgs,
    ToolCallHandler? onToolCall,
  }) async* {
    final argsString = rawArgs is String
        ? rawArgs
        : jsonEncode(rawArgs ?? const <String, dynamic>{});
    yield ToolCallStart(id: id, toolName: name);
    yield ToolCallDelta(id: id, inputDelta: argsString);
    yield ToolCallEnd(id);

    if (onToolCall == null) return;
    var parsed = <String, dynamic>{};
    try {
      if (rawArgs is Map) {
        parsed = Map<String, dynamic>.from(rawArgs);
      } else if (rawArgs is String && rawArgs.trim().isNotEmpty) {
        final decoded = jsonDecode(rawArgs);
        if (decoded is Map) parsed = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    await onToolCall(name, parsed, toolCallId: id);
  }

  static String _contentText(dynamic content) {
    if (content is String) return content;
    if (content is List) {
      return content.map((part) {
        if (part is Map) {
          return part['text']?.toString() ?? '';
        }
        return '';
      }).join();
    }
    return '';
  }

  static TokenUsage? _tokenUsage(dynamic raw) {
    if (raw is! Map) return null;
    return TokenUsage(
      promptTokens: _intValue(raw['prompt_tokens'] ?? raw['promptTokens']),
      completionTokens: _intValue(
        raw['completion_tokens'] ?? raw['completionTokens'],
      ),
      totalTokens: _intValue(raw['total_tokens'] ?? raw['totalTokens']),
    );
  }

  static int _intValue(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  /// Non-stream generation folded through [StreamChunkHandler].
  static Future<TextGenerationResult> generateMessage({
    dynamic config,
    String? modelId,
    required List<Map<String, dynamic>> messages,
    List<String>? userImagePaths,
    ReasoningRequest reasoning = ReasoningRequest.auto,
    double? temperature,
    double? topP,
    int? maxTokens,
    List<Map<String, dynamic>>? tools,
    ToolCallHandler? onToolCall,
    Map<String, String>? extraHeaders,
    Map<String, dynamic>? extraBody,
    String? conversationId,
    String? requestId,
    bool allowImagesApiRouting = true,
    bool ocrActive = false,
    bool builtInSearchOnly = false,
    bool skipImageParsing = false,
    bool parseMarkdownImageLinks = true,
    bool textOnly = false,
    AutoRetryOptions? retryOverride,
    void Function(RetryPending? pending)? onRetry,
    void Function(Usage update)? onUsage,
  }) async {
    final handler = StreamChunkHandler();
    await for (final chunk in sendMessageStream(
      config: config,
      modelId: modelId,
      messages: messages,
      userImagePaths: userImagePaths,
      reasoning: reasoning,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
      tools: tools,
      onToolCall: onToolCall,
      extraHeaders: extraHeaders,
      extraBody: extraBody,
      conversationId: conversationId,
      requestId: requestId,
      allowImagesApiRouting: allowImagesApiRouting,
      ocrActive: ocrActive,
      builtInSearchOnly: builtInSearchOnly,
      skipImageParsing: skipImageParsing,
      parseMarkdownImageLinks: parseMarkdownImageLinks,
      textOnly: textOnly,
      retryOverride: retryOverride,
    )) {
      handler.handle(chunk);
      if (chunk is Usage) onUsage?.call(chunk);
    }
    return handler.toResult();
  }

  // Non-streaming text generation for utilities like title summarization
  static Future<String> generateText({
    dynamic config,
    String? modelId,
    required String prompt,
    String? conversationId,
    String? requestId,
    Map<String, String>? extraHeaders,
    Map<String, dynamic>? extraBody,
    ReasoningRequest reasoning = ReasoningRequest.auto,
    bool skipImageParsing = true,
  }) async {
    final result = await generateMessage(
      config: config,
      modelId: modelId,
      messages: [
        {'role': 'user', 'content': prompt},
      ],
      conversationId: conversationId,
      requestId: requestId,
      extraHeaders: extraHeaders,
      extraBody: extraBody,
      reasoning: reasoning,
      builtInSearchOnly: true,
      skipImageParsing: skipImageParsing,
      allowImagesApiRouting: !skipImageParsing,
    );
    return result.text;
  }
}
