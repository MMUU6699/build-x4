import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FunctionsHttpException;

import '../../../core/config/supabase_config.dart';
import '../../../core/services/workspace/daytona_workspace_runtime.dart';
import '../../../core/services/workspace/work_event_persistence_service.dart';
import '../models/work_task_result.dart';
import '../models/work_tool_event.dart';

abstract class ManusAgentEvent {
  const ManusAgentEvent();
}

class ManusStartingEvent extends ManusAgentEvent {
  const ManusStartingEvent();
}

class ManusThinkingEvent extends ManusAgentEvent {
  final String text;
  const ManusThinkingEvent(this.text);
}

class ManusToolStartedEvent extends ManusAgentEvent {
  final WorkToolEvent toolEvent;
  const ManusToolStartedEvent(this.toolEvent);
}

class ManusToolFinishedEvent extends ManusAgentEvent {
  final WorkToolEvent toolEvent;
  const ManusToolFinishedEvent(this.toolEvent);
}

class ManusMessageNotifyEvent extends ManusAgentEvent {
  final String message;
  const ManusMessageNotifyEvent(this.message);
}

class ManusMessageAskEvent extends ManusAgentEvent {
  final String question;
  final String toolCallId;
  final List<Map<String, dynamic>> messages;
  const ManusMessageAskEvent(
    this.question,
    this.toolCallId, [
    this.messages = const [],
  ]);
}

class ManusTaskCompletedEvent extends ManusAgentEvent {
  final WorkTaskResult result;
  const ManusTaskCompletedEvent(this.result);
}

class ManusErrorEvent extends ManusAgentEvent {
  final String error;
  const ManusErrorEvent(this.error);
}

class ManusAgentLoopService {
  ManusAgentLoopService({
    DaytonaWorkspaceRuntime? runtime,
    WorkEventPersistenceService? persistenceService,
    this.chatInvoker,
  }) : _runtime = runtime ?? DaytonaWorkspaceRuntime(),
       _persistence = persistenceService ?? const WorkEventPersistenceService();

  final DaytonaWorkspaceRuntime _runtime;
  final WorkEventPersistenceService _persistence;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> body)?
  chatInvoker;

  static const int maxToolResultChars = 8000;

  /// Character budget for the conversation window sent to the model. Whole
  /// prompt turns are dropped oldest-first so an assistant `tool_calls`
  /// message never loses the `tool` results that answer it.
  static const int maxRequestHistoryChars = 120000;
  static const int defaultMaxIterations = 60;

  /// Real health probe for the deterministic computer endpoint.
  Future<Map<String, dynamic>> checkComputerHealth() {
    return _runtime.checkHealth();
  }

  static String buildSystemPrompt(List<Map<String, dynamic>> tools) {
    final toolDescriptions = tools
        .map((t) {
          final fn = t['function'] as Map<String, dynamic>;
          final name = fn['name'] as String;
          final desc = fn['description'] as String;
          return '- `$name`: $desc';
        })
        .join('\n');

    return '''
You are Build X, a general-purpose agent operating a real Linux computer (a Daytona sandbox) for the user.

<role>
You are not a chatbot describing actions. You are the operator of the computer. Use the tools to do the work.
</role>

<core_rules>
- Do exactly what the user asked and nothing else. Do not create unrelated files, projects, demos or scaffolding.
- The user's language is the working language. Thinking, `brief` values and user-facing messages must use it. Arabic input means Arabic output.
- Never claim success without evidence from a tool result. If a tool failed, say what failed.
- Never invent page contents, command output, file contents or screenshots. Quote only what a tool returned.
- If a site blocks the browser, describe what you actually see. Try at most one alternative, or ask one question with `message_ask_user` and stop.
- Keep `brief` short, human and in the user's language. Never put raw paths, JSON or shell commands in `brief`.
- Do not call `message_*` tools in a loop. One opening notification is enough.
</core_rules>

<workflow>
1. Call `message_notify_user` exactly once at the start with a short acknowledgement.
2. Perform the task with the appropriate tools.
3. After every browser action, read the returned page text and interactive element list before choosing the next action. Do not guess what the page contains.
4. Use `browser_get_text` when the element list is not enough to read the page.
5. Use `file_read` before editing an existing file. Use `file_write` for a new file.
6. Finish with `deliver_result` containing the real final answer and the real output file paths. A plain text answer does not finish the task.
</workflow>

<language>
If the user writes Arabic, all `brief` values, notifications and the final answer must be Arabic.
</language>

<available_tools>
$toolDescriptions
</available_tools>
''';
  }

  List<Map<String, dynamic>> _getToolSchemas() {
    Map<String, dynamic> fn(
      String name,
      String description,
      Map<String, dynamic> properties,
      List<String> required,
    ) {
      return {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': {
            'type': 'object',
            'properties': properties,
            'required': required,
          },
        },
      };
    }

    Map<String, dynamic> brief() => {
      'type': 'string',
      'description':
          'Short user-facing description in the user\'s language (never a raw command or path)',
    };

    return [
      fn(
        'message_notify_user',
        'Send one short status update to the user.',
        {
          'message': {
            'type': 'string',
            'description': 'Acknowledgment in the user\'s language',
          },
        },
        ['message'],
      ),
      fn(
        'message_ask_user',
        'Ask one clarification question when genuinely blocked.',
        {
          'question': {
            'type': 'string',
            'description': 'The question in the user\'s language',
          },
        },
        ['question'],
      ),
      fn(
        'deliver_result',
        'Deliver the final answer and completed files. Required to finish.',
        {
          'message': {
            'type': 'string',
            'description': 'Final user-facing answer in the user\'s language',
          },
          'attachments': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Real output file paths inside the sandbox',
          },
        },
        ['message'],
      ),
      fn(
        'shell_exec',
        'Execute a bash command inside the Linux sandbox.',
        {
          'command': {'type': 'string', 'description': 'Bash command'},
          'cwd': {'type': 'string', 'description': 'Working directory'},
          'brief': brief(),
        },
        ['command', 'brief'],
      ),
      fn(
        'file_read',
        'Read a file from the sandbox.',
        {
          'file_path': {'type': 'string', 'description': 'File path'},
          'offset': {
            'type': 'integer',
            'description': 'Starting line (1-based)',
          },
          'limit': {'type': 'integer', 'description': 'Maximum lines'},
          'brief': brief(),
        },
        ['file_path', 'brief'],
      ),
      fn(
        'file_write',
        'Create or overwrite a file in the sandbox.',
        {
          'file_path': {'type': 'string', 'description': 'File path'},
          'content': {'type': 'string', 'description': 'Full file content'},
          'append': {'type': 'boolean'},
          'brief': brief(),
        },
        ['file_path', 'content', 'brief'],
      ),
      fn(
        'file_str_replace',
        'Replace one unique exact string in a file.',
        {
          'file_path': {'type': 'string', 'description': 'File path'},
          'old_str': {
            'type': 'string',
            'description': 'Exact unique text to replace',
          },
          'new_str': {'type': 'string', 'description': 'Replacement text'},
          'brief': brief(),
        },
        ['file_path', 'old_str', 'new_str', 'brief'],
      ),
      fn(
        'file_find_by_name',
        'Find files by name or glob inside the sandbox.',
        {
          'pattern': {'type': 'string', 'description': 'Glob or filename'},
          'dir_path': {'type': 'string', 'description': 'Directory to search'},
          'brief': brief(),
        },
        ['pattern', 'brief'],
      ),
      fn(
        'file_find_in_content',
        'Search text/regex across files.',
        {
          'regex': {'type': 'string', 'description': 'Regex or keyword'},
          'file_path': {'type': 'string', 'description': 'Directory or file'},
          'brief': brief(),
        },
        ['regex', 'brief'],
      ),
      fn(
        'info_search_web',
        'Search the web for current information.',
        {
          'query': {'type': 'string'},
          'brief': brief(),
        },
        ['query', 'brief'],
      ),
      fn(
        'browser_navigate',
        'Open a URL in the real Chrome browser.',
        {
          'url': {'type': 'string'},
          'brief': brief(),
        },
        ['url', 'brief'],
      ),
      fn(
        'browser_view',
        'Capture the live page, its text and elements.',
        {'brief': brief()},
        ['brief'],
      ),
      fn(
        'browser_get_text',
        'Read the visible text of the current page.',
        {'brief': brief()},
        ['brief'],
      ),
      fn(
        'browser_click',
        'Click an element by index, or click coordinates.',
        {
          'index': {'type': 'integer'},
          'coordinate_x': {'type': 'integer'},
          'coordinate_y': {'type': 'integer'},
          'brief': brief(),
        },
        ['brief'],
      ),
      fn(
        'browser_input',
        'Type text into an input by element index.',
        {
          'index': {'type': 'integer'},
          'text': {'type': 'string'},
          'press_enter': {'type': 'boolean'},
          'brief': brief(),
        },
        ['index', 'text', 'brief'],
      ),
      fn(
        'browser_scroll',
        'Scroll the viewport up or down.',
        {
          'direction': {
            'type': 'string',
            'enum': ['up', 'down'],
          },
          'brief': brief(),
        },
        ['direction', 'brief'],
      ),
      fn(
        'browser_press_key',
        'Press a key in the browser.',
        {
          'key': {'type': 'string'},
          'brief': brief(),
        },
        ['key', 'brief'],
      ),
      fn(
        'browser_restart',
        'Restart the browser, optionally at a URL.',
        {
          'url': {'type': 'string'},
          'brief': brief(),
        },
        ['brief'],
      ),
    ];
  }

  static const Map<String, List<String>> _requiredArgs = {
    'message_notify_user': ['message'],
    'message_ask_user': ['question'],
    'deliver_result': ['message'],
    'shell_exec': ['command', 'brief'],
    'file_read': ['file_path', 'brief'],
    'file_write': ['file_path', 'content', 'brief'],
    'file_str_replace': ['file_path', 'old_str', 'new_str', 'brief'],
    'file_find_by_name': ['pattern', 'brief'],
    'file_find_in_content': ['regex', 'brief'],
    'info_search_web': ['query', 'brief'],
    'browser_navigate': ['url', 'brief'],
    'browser_view': ['brief'],
    'browser_get_text': ['brief'],
    'browser_click': ['brief'],
    'browser_input': ['index', 'text', 'brief'],
    'browser_scroll': ['direction', 'brief'],
    'browser_press_key': ['key', 'brief'],
    'browser_restart': ['brief'],
  };

  String? _validateArguments(String toolName, Map<String, dynamic> args) {
    final required = _requiredArgs[toolName];
    if (required == null) {
      return 'Unknown tool "$toolName". Use only the tools listed.';
    }
    for (final key in required) {
      // `brief` is a cosmetic UI label. A missing brief falls back to a
      // generated label instead of failing the whole tool call.
      if (key == 'brief') continue;
      final value = args[key];
      if (value == null) return 'Missing required argument "$key".';
      if (value is String && value.trim().isEmpty) {
        return 'Argument "$key" must not be empty.';
      }
    }
    if (toolName == 'browser_click') {
      final hasIndex = args['index'] != null;
      final hasCoords =
          args['coordinate_x'] != null && args['coordinate_y'] != null;
      if (!hasIndex && !hasCoords) {
        return 'browser_click requires "index" or both "coordinate_x" and "coordinate_y".';
      }
    }
    return null;
  }

  String _genericBrief(String category) {
    final arabic = PlatformDispatcher.instance.locale.languageCode == 'ar';
    return switch (category) {
      'browser' => arabic ? 'استخدام المتصفح' : 'Using browser',
      'shell' => arabic ? 'استخدام الطرفية' : 'Using terminal',
      'file' => arabic ? 'تعديل ملف' : 'Editing a file',
      'search' => arabic ? 'البحث في الويب' : 'Searching the web',
      _ => arabic ? 'تنفيذ خطوة' : 'Running a step',
    };
  }

  String _categoryFor(String toolName) {
    if (toolName.startsWith('shell_')) return 'shell';
    if (toolName.startsWith('file_')) return 'file';
    if (toolName.startsWith('browser_')) return 'browser';
    if (toolName.contains('search')) return 'search';
    if (toolName.startsWith('message_')) return 'message';
    return 'tool';
  }

  List<String> _elementLines(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();
  }

  String _browserContext(Map<String, dynamic> res, String prefix) {
    final url = res['url']?.toString() ?? '';
    final title = res['title']?.toString() ?? '';
    final pageText = res['page_text']?.toString() ?? '';
    final path = res['screenshot_path']?.toString() ?? '';
    final screenshotError = res['screenshot_error']?.toString() ?? '';
    final elements = _elementLines(res['interactive_elements']);
    final buffer = StringBuffer()
      ..writeln(prefix)
      ..writeln('URL: $url')
      ..writeln('Title: $title');
    if (path.isNotEmpty) buffer.writeln('Screenshot saved at: $path');
    if (screenshotError.isNotEmpty) {
      buffer.writeln('Screenshot error: $screenshotError');
    }
    if (pageText.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Visible page text (truncated):')
        ..writeln(pageText);
    }
    if (elements.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Interactive elements (click by index):')
        ..writeln(elements.join('\n'));
    }
    return buffer.toString().trim();
  }

  String _cap(String text) {
    if (text.length <= maxToolResultChars) return text;
    final removed = text.length - maxToolResultChars;
    return '${text.substring(0, maxToolResultChars)}\n'
        '...[truncated $removed characters]';
  }

  /// Drops the oldest prompt turns until the conversation fits inside
  /// [maxRequestHistoryChars]. The system prompt and the newest turn are always
  /// kept, and trimming only happens on user-message boundaries so tool results
  /// stay attached to the assistant call that produced them.
  List<Map<String, dynamic>> _boundedHistory(
    List<Map<String, dynamic>> messages,
  ) {
    if (messages.length <= 1) return messages;

    final hasSystem = messages.first['role'] == 'system';
    final system = hasSystem ? messages.first : null;
    final conversation = hasSystem ? messages.sublist(1) : messages;
    if (conversation.isEmpty) return messages;

    final turnStarts = <int>[];
    for (var i = 0; i < conversation.length; i++) {
      if (conversation[i]['role'] == 'user') turnStarts.add(i);
    }
    if (turnStarts.isEmpty || turnStarts.first != 0) turnStarts.insert(0, 0);

    int costOf(int from, int to) {
      var total = 0;
      for (var i = from; i < to; i++) {
        total += jsonEncode(conversation[i]).length;
      }
      return total;
    }

    var keep = turnStarts.length - 1;
    var total = costOf(turnStarts[keep], conversation.length);
    while (keep > 0) {
      final candidate = costOf(turnStarts[keep - 1], turnStarts[keep]);
      if (total + candidate > maxRequestHistoryChars) break;
      total += candidate;
      keep--;
    }
    if (keep == 0) return messages;

    return [
      if (system != null) system,
      ...conversation.sublist(turnStarts[keep]),
    ];
  }

  Future<void> _saveHistory(
    String conversationId,
    List<Map<String, dynamic>> messages,
  ) async {
    final bounded = _boundedHistory(messages);
    if (!identical(bounded, messages)) {
      messages
        ..clear()
        ..addAll(bounded);
    }
    await _persistence.saveAgentHistory(conversationId, messages);
  }

  Future<Map<String, dynamic>> _invokeChat(Map<String, dynamic> body) async {
    if (chatInvoker != null) {
      return await chatInvoker!(body);
    }
    if (SupabaseConfig.isUnconfigured) {
      throw StateError('Supabase is not configured on this build.');
    }
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await SupabaseConfig.ensureValidToken();
        final client = SupabaseConfig.client;
        final token = client.auth.currentSession?.accessToken;
        final res = await client.functions.invoke(
          'chat',
          body: body,
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        );
        if (res.data == null) {
          throw const _ChatInvocationException(502, 'Empty response body');
        }
        return res.data is String
            ? jsonDecode(res.data as String) as Map<String, dynamic>
            : res.data as Map<String, dynamic>;
      } on FunctionsHttpException catch (e) {
        final status = e.status;
        final data = e.details;
        final message = data is Map ? data['error']?.toString() : '$data';
        final error = _ChatInvocationException(
          status,
          message ?? 'HTTP $status',
        );
        lastError = error;
        final retryable = status == 502 || status == 503 || status == 504;
        if (!retryable || attempt == 3) throw error;
      } catch (e) {
        lastError = e;
        if (attempt == 3) rethrow;
      }
      await Future.delayed(Duration(milliseconds: 400 * attempt));
    }
    throw lastError ?? StateError('Chat invocation failed');
  }

  Stream<ManusAgentEvent> runAgentLoop({
    required String conversationId,
    required String userRequest,
    int maxIterations = defaultMaxIterations,
    CancelToken? cancelToken,
    List<Map<String, dynamic>>? existingMessages,
    String? pendingToolCallId,
  }) async* {
    debugPrint(
      '[ManusAgentLoopService] start conversation=$conversationId '
      'maxIterations=$maxIterations',
    );

    final toolSchemas = _getToolSchemas();
    final systemPrompt = buildSystemPrompt(toolSchemas);
    final messages = <Map<String, dynamic>>[];

    if (existingMessages != null && existingMessages.isNotEmpty) {
      messages.addAll(
        existingMessages.where((m) => m['role']?.toString() != 'system'),
      );
    } else {
      final history = await _persistence.loadAgentHistory(conversationId);
      messages.addAll(history.where((m) => m['role']?.toString() != 'system'));
    }
    messages.insert(0, {'role': 'system', 'content': systemPrompt});

    if (pendingToolCallId != null && pendingToolCallId.isNotEmpty) {
      // The waiting turn already persisted a placeholder result for this call.
      // Replace it with the user's real answer instead of adding a duplicate.
      messages.removeWhere((message) {
        if (message['role'] != 'tool') return false;
        final id = (message['tool_call_id'] ?? message['toolCallId'] ?? '')
            .toString();
        return id == pendingToolCallId;
      });
      messages.add({
        'role': 'tool',
        'tool_call_id': pendingToolCallId,
        'toolCallId': pendingToolCallId,
        'name': 'message_ask_user',
        'content': userRequest,
      });
    } else {
      messages.add({'role': 'user', 'content': userRequest});
    }

    _runtime.currentConversationId = conversationId;

    // Real runs bootstrap the user's own sandbox. Injected chatInvoker runs are
    // unit tests and must not touch the network.
    if (chatInvoker == null) {
      yield const ManusStartingEvent();
      try {
        final health = await _runtime.checkHealth();
        if (health['status']?.toString() != 'connected') {
          throw StateError(
            'Daytona health check failed: ${health['details'] ?? health['status']}',
          );
        }
        await _runtime.ensureSandbox();
      } catch (e) {
        yield ManusErrorEvent('Could not start the computer: $e');
        return;
      }
    }

    var iteration = 0;
    var isDone = false;
    var notified = false;
    var consecutiveInvalidArgs = 0;

    while (iteration < maxIterations && !isDone) {
      if (cancelToken?.isCancelled ?? false) {
        yield const ManusErrorEvent('Task cancelled by user.');
        break;
      }
      iteration++;

      messages[0] = {'role': 'system', 'content': systemPrompt};

      Map<String, dynamic> completionData;
      try {
        completionData = await _invokeChat({
          'messages': List<Map<String, dynamic>>.from(
            _boundedHistory(messages),
          ),
          'tools': toolSchemas,
          'tool_choice': notified ? 'auto' : 'any',
          'stream': false,
        });
      } catch (e) {
        final message = e is _ChatInvocationException
            ? '${e.message} (HTTP ${e.status})'
            : e.toString();
        yield ManusErrorEvent('Failed to communicate with AI model: $message');
        break;
      }

      final choices = completionData['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        yield const ManusErrorEvent('Empty response received from the model.');
        break;
      }

      final choice = choices.first as Map<String, dynamic>;
      final messageObj = choice['message'] as Map<String, dynamic>;
      final content = messageObj['content']?.toString() ?? '';
      final toolCalls =
          (messageObj['tool_calls'] ?? messageObj['toolCalls'])
              as List<dynamic>?;

      if (toolCalls == null || toolCalls.isEmpty) {
        messages.add({'role': 'assistant', 'content': content});
        if (content.isNotEmpty) yield ManusThinkingEvent(content);
        messages.add({
          'role': 'user',
          'content':
              'You must use the computer tools and finish with deliver_result. '
              'Do not answer in plain text.',
        });
        await _saveHistory(conversationId, messages);
        continue;
      }

      for (final rawCall in toolCalls) {
        if (rawCall is! Map<String, dynamic>) {
          yield const ManusErrorEvent('Invalid tool call structure returned.');
          return;
        }
        final callId = rawCall['id']?.toString().trim();
        if (callId == null || callId.isEmpty) {
          yield const ManusErrorEvent(
            'Model returned a tool call without an ID. Aborting request.',
          );
          return;
        }
      }

      messages.add({
        'role': 'assistant',
        'content': content,
        'tool_calls': toolCalls,
        'toolCalls': toolCalls,
      });

      final handledCallIds = <String>{};
      for (final rawToolCall in toolCalls) {
        if (cancelToken?.isCancelled ?? false) break;

        final toolCall = rawToolCall as Map<String, dynamic>;
        final toolCallId = toolCall['id']!.toString().trim();
        final functionObj = toolCall['function'] as Map<String, dynamic>;
        final toolName = functionObj['name']?.toString() ?? '';
        final rawArgs = functionObj['arguments'];

        Map<String, dynamic> args = {};
        String? argumentError;
        if (rawArgs is String) {
          try {
            final decoded = jsonDecode(rawArgs);
            if (decoded is Map) {
              args = Map<String, dynamic>.from(decoded);
            } else {
              argumentError = 'arguments must be a JSON object';
            }
          } catch (e) {
            argumentError = 'arguments are not valid JSON ($e)';
          }
        } else if (rawArgs is Map) {
          args = Map<String, dynamic>.from(rawArgs);
        } else {
          argumentError = 'arguments must be a JSON object string';
        }
        argumentError ??= _validateArguments(toolName, args);

        final category = _categoryFor(toolName);
        if (argumentError != null) {
          consecutiveInvalidArgs++;
          final resultText =
              'Invalid tool arguments: $argumentError. '
              'Call the tool again with valid JSON.';
          debugPrint(
            '[ManusAgentLoopService] invalid $toolName args '
            '($consecutiveInvalidArgs/3): $argumentError',
          );
          final failedEvent = WorkToolEvent(
            id: toolCallId,
            stepId: 'step_$iteration',
            toolName: toolName,
            toolCategory: category,
            brief: _genericBrief(category),
            arguments: args,
            result: resultText,
            status: 'failed',
            timestamp: DateTime.now(),
          );
          if (!toolName.startsWith('message_') &&
              toolName != 'deliver_result') {
            yield ManusToolStartedEvent(failedEvent);
            yield ManusToolFinishedEvent(failedEvent);
          }
          messages.add({
            'role': 'tool',
            'tool_call_id': toolCallId,
            'toolCallId': toolCallId,
            'name': toolName,
            'content': resultText,
          });
          handledCallIds.add(toolCallId);
          await _saveHistory(conversationId, messages);
          if (consecutiveInvalidArgs >= 3) {
            yield const ManusErrorEvent(
              'The model produced invalid tool arguments 3 times in a row. '
              'Stopped instead of running tools with empty arguments.',
            );
            return;
          }
          continue;
        }
        consecutiveInvalidArgs = 0;

        final briefRaw = args['brief']?.toString().trim() ?? '';
        final brief = briefRaw.isEmpty ? _genericBrief(category) : briefRaw;
        if (briefRaw.isEmpty && !toolName.startsWith('message_')) {
          debugPrint(
            '[ManusAgentLoopService] model omitted brief for $toolName; '
            'using generic label',
          );
        }

        final isMetaTool =
            toolName.startsWith('message_') || toolName == 'deliver_result';
        final toolEvent = WorkToolEvent(
          id: toolCallId,
          stepId: 'step_$iteration',
          toolName: toolName,
          toolCategory: category,
          brief: brief,
          arguments: args,
          status: 'running',
          timestamp: DateTime.now(),
        );

        if (!isMetaTool) yield ManusToolStartedEvent(toolEvent);
        if (!notified && toolName == 'message_notify_user') notified = true;

        dynamic executionResult;
        String? originalContent;
        String? modifiedContent;
        String? browserUrl;
        String? screenshotUrl;
        String? screenshotPath;
        var toolSuccess = true;

        _runtime.currentEventId = toolCallId;

        try {
          if (toolName == 'message_notify_user') {
            final msg = args['message']!.toString();
            notified = true;
            yield ManusMessageNotifyEvent(msg);
            executionResult = {'status': 'ok'};
          } else if (toolName == 'message_ask_user') {
            final question = args['question']!.toString();
            yield ManusMessageAskEvent(
              question,
              toolCallId,
              List<Map<String, dynamic>>.from(messages),
            );
            isDone = true;
            executionResult = {'status': 'waiting_for_user_response'};
          } else if (toolName == 'deliver_result') {
            final summary = args['message']!.toString();
            final rawAttachments = args['attachments'];
            final attachments = <WorkAttachment>[];
            if (rawAttachments is List) {
              for (final item in rawAttachments) {
                final path = item.toString();
                if (path.trim().isEmpty) continue;
                final name = path.split('/').last;
                final ext = name.contains('.') ? name.split('.').last : 'txt';
                var size = 0;
                String? preview;
                try {
                  final fileRes = await _runtime.invokeDaytona(
                    action: 'read_file',
                    params: {'path': path, 'limit': 60},
                  );
                  preview = fileRes['content']?.toString();
                  size =
                      (fileRes['byteSize'] as num?)?.toInt() ??
                      (preview?.length ?? 0);
                } catch (e) {
                  debugPrint(
                    '[ManusAgentLoopService] attachment preview failed for '
                    '$path: $e',
                  );
                }
                attachments.add(
                  WorkAttachment(
                    name: name,
                    path: path,
                    sizeInBytes: size,
                    fileType: ext,
                    previewContent: preview,
                  ),
                );
              }
            }
            final result = WorkTaskResult(
              summary: summary,
              attachments: attachments,
              completedAt: DateTime.now(),
            );
            yield ManusTaskCompletedEvent(result);
            isDone = true;
            executionResult = {'status': 'ok'};
          } else if (toolName == 'shell_exec') {
            final res = await _runtime.invokeDaytona(
              action: 'exec_command',
              params: {'command': args['command'], 'cwd': args['cwd']},
            );
            final stdout = res['stdout']?.toString() ?? '';
            final stderr = res['stderr']?.toString() ?? '';
            final exitCode = res['exitCode'] ?? 0;
            executionResult =
                'exitCode: $exitCode\nstdout:\n$stdout\nstderr:\n$stderr';
          } else if (toolName == 'file_read') {
            final path = args['file_path'].toString();
            final res = await _runtime.invokeDaytona(
              action: 'read_file',
              params: {
                'path': path,
                if (args['offset'] != null) 'offset': args['offset'],
                if (args['limit'] != null) 'limit': args['limit'],
              },
            );
            originalContent = res['content']?.toString() ?? '';
            executionResult = originalContent;
          } else if (toolName == 'file_write') {
            final path = args['file_path'].toString();
            final content = args['content'].toString();
            final append = args['append'] == true;
            try {
              final prev = await _runtime.invokeDaytona(
                action: 'read_file',
                params: {'path': path},
              );
              originalContent = prev['content']?.toString();
            } catch (_) {
              originalContent = null;
            }
            final res = await _runtime.invokeDaytona(
              action: 'write_file',
              params: {'path': path, 'content': content, 'append': append},
            );
            modifiedContent = res['modifiedContent']?.toString() ?? content;
            executionResult =
                'Wrote $path (${res['byteSize'] ?? modifiedContent.length} bytes)';
          } else if (toolName == 'file_str_replace') {
            final path = args['file_path'].toString();
            final oldStr = args['old_str'].toString();
            final newStr = args['new_str'].toString();
            final res = await _runtime.invokeDaytona(
              action: 'edit_file',
              params: {'path': path, 'old_str': oldStr, 'new_str': newStr},
            );
            originalContent = res['originalContent']?.toString();
            modifiedContent = res['modifiedContent']?.toString();
            executionResult =
                'Replaced text in $path (${res['byteSize'] ?? 0} bytes)';
          } else if (toolName == 'file_find_by_name') {
            final res = await _runtime.glob(
              args['pattern'].toString(),
              path: args['dir_path']?.toString(),
            );
            executionResult = jsonEncode({'matches': res});
          } else if (toolName == 'file_find_in_content') {
            final res = await _runtime.grep(
              args['regex'].toString(),
              path: args['file_path']?.toString(),
            );
            executionResult = jsonEncode({'matches': res});
          } else if (toolName == 'info_search_web') {
            final results = await _runtime.searchWeb(args['query'].toString());
            executionResult = jsonEncode({'results': results});
          } else if (toolName == 'browser_navigate') {
            final res = await _runtime.navigateBrowser(args['url'].toString());
            browserUrl = res['url']?.toString();
            screenshotUrl = res['screenshot_url']?.toString();
            screenshotPath = res['screenshot_path']?.toString();
            executionResult = _browserContext(res, 'Navigated in the browser.');
          } else if (toolName == 'browser_view') {
            final res = await _runtime.browserView();
            browserUrl = res['url']?.toString();
            screenshotUrl = res['screenshot_url']?.toString();
            screenshotPath = res['screenshot_path']?.toString();
            executionResult = _browserContext(res, 'Current browser page.');
          } else if (toolName == 'browser_get_text') {
            final res = await _runtime.browserGetText();
            browserUrl = res['url']?.toString();
            executionResult = _browserContext(res, 'Current page text.');
          } else if (toolName == 'browser_click') {
            final rawIndex = args['index'];
            final index = rawIndex is int
                ? rawIndex
                : int.tryParse(rawIndex?.toString() ?? '');
            final rawX = args['coordinate_x'];
            final rawY = args['coordinate_y'];
            final x = rawX is int ? rawX : int.tryParse(rawX?.toString() ?? '');
            final y = rawY is int ? rawY : int.tryParse(rawY?.toString() ?? '');
            final res = await _runtime.browserClick(index: index, x: x, y: y);
            browserUrl = res['url']?.toString();
            screenshotUrl = res['screenshot_url']?.toString();
            screenshotPath = res['screenshot_path']?.toString();
            executionResult = _browserContext(res, 'Clicked.');
          } else if (toolName == 'browser_input') {
            final rawIndex = args['index'];
            final index = rawIndex is int
                ? rawIndex
                : int.tryParse(rawIndex?.toString() ?? '');
            final res = await _runtime.browserInput(
              index: index,
              text: args['text'].toString(),
              pressEnter: args['press_enter'] == true,
            );
            browserUrl = res['url']?.toString();
            screenshotUrl = res['screenshot_url']?.toString();
            screenshotPath = res['screenshot_path']?.toString();
            executionResult = _browserContext(res, 'Typed into the field.');
          } else if (toolName == 'browser_scroll') {
            final res = await _runtime.browserScroll(
              direction: args['direction'].toString(),
            );
            browserUrl = res['url']?.toString();
            screenshotUrl = res['screenshot_url']?.toString();
            screenshotPath = res['screenshot_path']?.toString();
            executionResult = _browserContext(res, 'Scrolled.');
          } else if (toolName == 'browser_press_key') {
            final res = await _runtime.browserPressKey(
              key: args['key'].toString(),
            );
            browserUrl = res['url']?.toString();
            screenshotUrl = res['screenshot_url']?.toString();
            screenshotPath = res['screenshot_path']?.toString();
            executionResult = _browserContext(res, 'Pressed a key.');
          } else if (toolName == 'browser_restart') {
            final res = await _runtime.browserRestart(
              url: (args['url']?.toString().trim().isEmpty ?? true)
                  ? null
                  : args['url'].toString().trim(),
            );
            browserUrl = res['url']?.toString();
            screenshotUrl = res['screenshot_url']?.toString();
            screenshotPath = res['screenshot_path']?.toString();
            executionResult = _browserContext(res, 'Browser restarted.');
          } else {
            executionResult = 'Unknown tool "$toolName". It was not executed.';
            toolSuccess = false;
          }
        } catch (err) {
          toolSuccess = false;
          executionResult = 'Tool execution failed: $err';
        }

        final resultText = _cap(
          executionResult is String
              ? executionResult
              : jsonEncode(executionResult),
        );

        final finishedEvent = toolEvent.copyWith(
          result: resultText,
          originalFileContent: originalContent,
          modifiedFileContent: modifiedContent,
          browserUrl: browserUrl,
          screenshotUrl: screenshotUrl,
          screenshotPath: screenshotPath,
          status: toolSuccess ? 'completed' : 'failed',
        );

        if (!isMetaTool) {
          yield ManusToolFinishedEvent(finishedEvent);
        }

        messages.add({
          'role': 'tool',
          'tool_call_id': toolCallId,
          'toolCallId': toolCallId,
          'name': toolName,
          'content': resultText,
        });
        handledCallIds.add(toolCallId);
        await _saveHistory(conversationId, messages);

        if (isDone) break;
      }

      // Every tool call in the assistant message needs exactly one tool result,
      // including calls skipped after message_ask_user/deliver_result or a
      // cancellation. Otherwise the next model request is rejected.
      for (final rawCall in toolCalls) {
        final call = rawCall as Map<String, dynamic>;
        final id = call['id']!.toString().trim();
        if (handledCallIds.contains(id)) continue;
        final function = call['function'] as Map<String, dynamic>?;
        messages.add({
          'role': 'tool',
          'tool_call_id': id,
          'toolCallId': id,
          'name': function?['name']?.toString() ?? 'unknown',
          'content': isDone
              ? 'Not executed: the task stopped after a terminal tool call.'
              : 'Not executed: the run was cancelled.',
        });
      }
      await _saveHistory(conversationId, messages);
    }

    if (!isDone && iteration >= maxIterations) {
      await _saveHistory(conversationId, messages);
      yield ManusErrorEvent(
        'The agent reached the $maxIterations-step limit before finishing. '
        'The task was not reported as completed. Send another message to '
        'continue, or configure a higher limit.',
      );
    }
    _runtime.currentEventId = null;
  }
}

class _ChatInvocationException implements Exception {
  const _ChatInvocationException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => message;
}
