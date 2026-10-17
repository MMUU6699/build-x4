import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
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

      dynamic data;

      // First try Supabase Edge Function if configured
      if (!SupabaseConfig.isUnconfigured) {
        try {
          final client = SupabaseConfig.client;
          final body = <String, dynamic>{
            'model': fixedModel,
            'inputs': inputs,
            'instructions': instructions,
            'completion_args': {
              'temperature': temperature ?? 0.7,
              'max_tokens': maxTokens ?? 2048,
              'top_p': topP ?? 1.0,
            },
          };
          final res = await client.functions.invoke(
            'chat',
            body: body,
            headers: {
              if (client.auth.currentSession?.accessToken != null)
                'Authorization':
                    'Bearer ${client.auth.currentSession!.accessToken}',
            },
          );
          if (res.status < 400 && res.data != null) {
            data = res.data is String
                ? jsonDecode(res.data as String)
                : res.data;
          }
        } catch (e) {
          debugPrint(
            'Supabase edge function failed: $e, falling back to direct Mistral API',
          );
        }
      }

      // If data is still null, call Mistral Conversations API directly
      if (data == null) {
        final dio = Dio();
        final mistralBody = <String, dynamic>{
          'model': fixedModel,
          'inputs': inputs,
          'instructions': instructions,
          'completion_args': {
            'temperature': temperature ?? 0.7,
            'max_tokens': maxTokens ?? 2048,
            'top_p': topP ?? 1.0,
          },
        };

        final response = await dio.post(
          'https://api.mistral.ai/v1/conversations',
          options: Options(
            headers: {
              'Authorization':
                  'Bearer mstrl_UwnnXZlz5CuwhsrKZaGOYrEUvANHBOdD_1KtT01',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          ),
          data: mistralBody,
          cancelToken: sessionToken,
        );

        data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
      }

      if (sessionToken.isCancelled) return;

      // Parse outputs according to Mistral conversations.start response
      if (data is Map<String, dynamic>) {
        final outputs = data['outputs'] as List<dynamic>?;
        if (outputs != null && outputs.isNotEmpty) {
          for (int i = 0; i < outputs.length; i++) {
            final output = outputs[i];
            if (output is Map<String, dynamic>) {
              final text =
                  output['content'] as String? ??
                  output['text'] as String? ??
                  '';

              if (text.isNotEmpty) {
                final textId = 'text-$i';
                yield TextStart(textId);
                // Yield text in readable chunks
                const chunkSize = 16;
                for (int c = 0; c < text.length; c += chunkSize) {
                  if (sessionToken.isCancelled) return;
                  final end = (c + chunkSize < text.length)
                      ? c + chunkSize
                      : text.length;
                  yield TextDelta(id: textId, text: text.substring(c, end));
                }
                yield TextEnd(textId);
              }

              // Check for tool call in output
              final toolCalls = output['tool_calls'] as List<dynamic>?;
              if (toolCalls != null) {
                for (final tc in toolCalls) {
                  if (tc is Map<String, dynamic>) {
                    final callId = tc['id']?.toString() ?? 'call_$i';
                    final fn = tc['function'] as Map<String, dynamic>? ?? tc;
                    final name = fn['name']?.toString() ?? '';
                    final argsRaw = fn['arguments'];
                    final argsStr = argsRaw is String
                        ? argsRaw
                        : jsonEncode(argsRaw ?? {});

                    yield ToolCallStart(id: callId, toolName: name);
                    yield ToolCallDelta(id: callId, inputDelta: argsStr);
                    yield ToolCallEnd(callId);

                    if (onToolCall != null) {
                      Map<String, dynamic> parsedArgs = {};
                      try {
                        if (argsRaw is Map<String, dynamic>) {
                          parsedArgs = argsRaw;
                        } else if (argsRaw is String) {
                          parsedArgs =
                              jsonDecode(argsRaw) as Map<String, dynamic>;
                        }
                      } catch (_) {}
                      await onToolCall(name, parsedArgs, toolCallId: callId);
                    }
                  }
                }
              }
            }
          }
        } else if (data['choices'] is List) {
          // Standard OpenAI/Mistral choices fallback
          final choices = data['choices'] as List<dynamic>;
          for (int i = 0; i < choices.length; i++) {
            final choice = choices[i];
            final message = choice['message'] as Map<String, dynamic>?;
            final text = message?['content']?.toString() ?? '';
            if (text.isNotEmpty) {
              final textId = 'text-$i';
              yield TextStart(textId);
              yield TextDelta(id: textId, text: text);
              yield TextEnd(textId);
            }
          }
        }

        // Token usage reporting
        final usageData = data['usage'] as Map<String, dynamic>?;
        if (usageData != null) {
          yield Usage(
            TokenUsage(
              promptTokens:
                  usageData['prompt_tokens'] as int? ??
                  usageData['promptTokens'] as int? ??
                  0,
              completionTokens:
                  usageData['completion_tokens'] as int? ??
                  usageData['completionTokens'] as int? ??
                  0,
              totalTokens:
                  usageData['total_tokens'] as int? ??
                  usageData['totalTokens'] as int? ??
                  0,
            ),
          );
        }

        yield const Finish(finishReason: 'stop', model: fixedModel);
      }
    } finally {
      if (rid.isNotEmpty) {
        _activeCancelTokens.remove(rid);
      }
    }
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
