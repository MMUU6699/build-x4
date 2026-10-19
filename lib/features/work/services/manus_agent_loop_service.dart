import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/services/workspace/daytona_workspace_runtime.dart';
import '../../../core/services/workspace/work_event_persistence_service.dart';
import '../models/work_plan.dart';
import '../models/work_step.dart';
import '../models/work_task_result.dart';
import '../models/work_tool_event.dart';

abstract class ManusAgentEvent {
  const ManusAgentEvent();
}

class ManusThinkingEvent extends ManusAgentEvent {
  final String text;
  const ManusThinkingEvent(this.text);
}

class ManusPlanEvent extends ManusAgentEvent {
  final WorkPlan plan;
  const ManusPlanEvent(this.plan);
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

  static const String fixedModel = 'mistral-medium-latest';

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
You are the Build X agent. You have your own cloud computer (a Linux Daytona sandbox with internet access, a bash shell, a file system, and a real Chrome browser). You can open it and use it.

<capabilities>
- You operate a full Linux Daytona sandbox computer with internet access to complete user tasks end-to-end.
- You have a real Chrome browser. You can navigate web pages, view screenshots, and interact with web applications.
- Never say you cannot open a browser or run commands. Use your tools directly.
- If the user asks whether you can do something with your computer (open a browser, run a command, create a file), do not answer yes or no. Do it with your tools. Questions and commands are handled the same way.
</capabilities>

<language>
- Default working language: Match the user's language.
- If the user writes in Arabic (e.g. "افتح المتصفح" or "هل يمكنك فتح المتصفح؟"), all your thinking, natural-language messages, tool `brief` arguments, and final responses MUST be in Arabic.
</language>

<workflow_rules>
- Work in a single continuous tool loop and use the available tools to complete the user's request end-to-end.
- Opening sequence for any task requiring tools:
  1) Call `message_notify_user` ONCE with a short acknowledgment in the user's language (what you understood and what you will do).
  2) Then perform the work using the appropriate tools.
  3) Every work tool call (shell, file, browser, search, mcp) MUST include a `brief` parameter: a short human user-facing phrase in the user's language describing the action (e.g. "فتح المتصفح للبحث في Google", never a raw path or terminal command).
- Execute the task yourself; do not hand instructions back to the user.
- Pure greetings or tasks that need no tools may call `deliver_result` directly.
- Finish every completed task by calling `deliver_result` with the final user-facing answer and any output file paths.
</workflow_rules>

<available_tools>
$toolDescriptions
</available_tools>
''';
  }

  List<Map<String, dynamic>> _getToolSchemas() {
    return [
      {
        'type': 'function',
        'function': {
          'name': 'message_notify_user',
          'description':
              'Send a natural language status update or opening acknowledgment to the user in their language.',
          'parameters': {
            'type': 'object',
            'properties': {
              'message': {
                'type': 'string',
                'description':
                    'Short user-facing acknowledgment message in the user\'s language',
              },
            },
            'required': ['message'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'message_ask_user',
          'description':
              'Ask the user a clarification question when blocked and unable to proceed.',
          'parameters': {
            'type': 'object',
            'properties': {
              'question': {
                'type': 'string',
                'description': 'The question to ask the user in their language',
              },
            },
            'required': ['question'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'plan_report',
          'description':
              'Initialize or update the execution plan steps and status.',
          'parameters': {
            'type': 'object',
            'properties': {
              'title': {
                'type': 'string',
                'description': 'Short descriptive title of the task',
              },
              'goal': {
                'type': 'string',
                'description': 'The high-level goal of this plan',
              },
              'steps': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'id': {'type': 'string'},
                    'description': {'type': 'string'},
                    'status': {
                      'type': 'string',
                      'enum': ['pending', 'running', 'completed', 'failed'],
                    },
                  },
                  'required': ['id', 'description', 'status'],
                },
              },
            },
            'required': ['title', 'goal', 'steps'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'replan',
          'description':
              'Replan remaining steps when assumptions change or unexpected errors occur.',
          'parameters': {
            'type': 'object',
            'properties': {
              'reason': {
                'type': 'string',
                'description': 'Why the plan needs to be revised',
              },
              'remaining_steps': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'id': {'type': 'string'},
                    'description': {'type': 'string'},
                  },
                  'required': ['id', 'description'],
                },
              },
            },
            'required': ['reason', 'remaining_steps'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'deliver_result',
          'description':
              'Deliver the final task result and completed files to the user.',
          'parameters': {
            'type': 'object',
            'properties': {
              'message': {
                'type': 'string',
                'description':
                    'Final comprehensive user-facing summary of what was accomplished in the user\'s language',
              },
              'attachments': {
                'type': 'array',
                'items': {'type': 'string'},
                'description':
                    'List of generated output file paths (e.g. ["report.md", "index.html"])',
              },
            },
            'required': ['message', 'attachments'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'shell_exec',
          'description': 'Execute a shell command inside the Linux sandbox.',
          'parameters': {
            'type': 'object',
            'properties': {
              'command': {
                'type': 'string',
                'description': 'Bash command to execute',
              },
              'brief': {
                'type': 'string',
                'description':
                    'Short natural language description of what this command does in the user\'s language (e.g. "تثبيت حزم npm")',
              },
              'cwd': {
                'type': 'string',
                'description': 'Working directory for the command',
              },
            },
            'required': ['command', 'brief'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'shell_view',
          'description':
              'View standard output/error of a running or completed shell command.',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {
                'type': 'string',
                'description': 'Process ID or identifier',
              },
              'brief': {
                'type': 'string',
                'description': 'Short natural language description',
              },
            },
            'required': ['brief'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'shell_wait',
          'description': 'Wait for a background shell command to finish.',
          'parameters': {
            'type': 'object',
            'properties': {
              'seconds': {'type': 'integer', 'description': 'Seconds to wait'},
              'brief': {
                'type': 'string',
                'description': 'Short natural language description',
              },
            },
            'required': ['seconds', 'brief'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'shell_kill_process',
          'description': 'Kill a running background process.',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string', 'description': 'Process ID'},
              'brief': {
                'type': 'string',
                'description': 'Short natural language description',
              },
            },
            'required': ['id', 'brief'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'file_read',
          'description': 'Read the contents of a file in the sandbox.',
          'parameters': {
            'type': 'object',
            'properties': {
              'file_path': {
                'type': 'string',
                'description': 'Path to the file',
              },
              'brief': {
                'type': 'string',
                'description':
                    'Short natural language description in the user\'s language (e.g. "قراءة ملف package.json")',
              },
              'offset': {
                'type': 'integer',
                'description': 'Starting line number',
              },
              'limit': {'type': 'integer', 'description': 'Max lines to read'},
            },
            'required': ['file_path', 'brief'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'file_write',
          'description': 'Write or overwrite a file in the sandbox.',
          'parameters': {
            'type': 'object',
            'properties': {
              'file_path': {
                'type': 'string',
                'description': 'Target file path',
              },
              'content': {
                'type': 'string',
                'description': 'Full file content to write',
              },
              'brief': {
                'type': 'string',
                'description':
                    'Short natural language description in the user\'s language (e.g. "إنشاء ملف index.html")',
              },
              'append': {
                'type': 'boolean',
                'description':
                    'Whether to append to the file rather than overwrite',
              },
            },
            'required': ['file_path', 'content', 'brief'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'file_str_replace',
          'description': 'Replace unique substring inside an existing file.',
          'parameters': {
            'type': 'object',
            'properties': {
              'file_path': {'type': 'string', 'description': 'Path to file'},
              'old_str': {
                'type': 'string',
                'description': 'Exact string to find',
              },
              'new_str': {
                'type': 'string',
                'description': 'Replacement string',
              },
              'brief': {
                'type': 'string',
                'description':
                    'Short natural language description in the user\'s language (e.g. "تعديل التنسيقات")',
              },
            },
            'required': ['file_path', 'old_str', 'new_str', 'brief'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'file_find_by_name',
          'description': 'Search for files matching a pattern.',
          'parameters': {
            'type': 'object',
            'properties': {
              'pattern': {
                'type': 'string',
                'description': 'Glob pattern or filename',
              },
              'dir_path': {
                'type': 'string',
                'description': 'Directory to search in',
              },
              'brief': {
                'type': 'string',
                'description':
                    'Short natural language description in the user\'s language (e.g. "البحث عن ملفات بايثون")',
              },
            },
            'required': ['pattern', 'brief'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'file_find_in_content',
          'description':
              'Search for text or regex across files in a directory.',
          'parameters': {
            'type': 'object',
            'properties': {
              'regex': {
                'type': 'string',
                'description': 'Regular expression or keyword',
              },
              'file_path': {
                'type': 'string',
                'description': 'Directory or file to search',
              },
              'brief': {
                'type': 'string',
                'description': 'Short natural language description',
              },
            },
            'required': ['regex', 'brief'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'info_search_web',
          'description':
              'Search the web for up-to-date documentation and real-time information.',
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {'type': 'string', 'description': 'Search query string'},
              'brief': {
                'type': 'string',
                'description':
                    'Short natural language description in the user\'s language (e.g. "البحث عن توثيق Flutter")',
              },
            },
            'required': ['query', 'brief'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'search_web',
          'description':
              'Alias for info_search_web: search the web for information.',
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {'type': 'string', 'description': 'Search query string'},
              'brief': {
                'type': 'string',
                'description':
                    'Short natural language description in the user\'s language',
              },
            },
            'required': ['query', 'brief'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'browser_navigate',
          'description':
              'Navigate the Chrome browser to a URL and capture the real screenshot and page text.',
          'parameters': {
            'type': 'object',
            'properties': {
              'url': {
                'type': 'string',
                'description': 'Web URL to load in Chrome',
              },
              'brief': {
                'type': 'string',
                'description':
                    'Short natural language description in the user\'s language (e.g. "فتح صفحة Google في المتصفح")',
              },
            },
            'required': ['url', 'brief'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'browser_view',
          'description':
              'Capture the current live browser viewport screenshot and HTML snapshot.',
          'parameters': {
            'type': 'object',
            'properties': {
              'brief': {
                'type': 'string',
                'description': 'Short natural language description',
              },
            },
            'required': ['brief'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'browser_click',
          'description':
              'Click an interactive element by its index from the interactive_elements tree, or by coordinates.',
          'parameters': {
            'type': 'object',
            'properties': {
              'index': {
                'type': 'integer',
                'description':
                    'Index of the interactive element to click (e.g. 4 for [4] <a href="/login"> "Sign in")',
              },
              'coordinate_x': {
                'type': 'integer',
                'description': 'Optional X coordinate',
              },
              'coordinate_y': {
                'type': 'integer',
                'description': 'Optional Y coordinate',
              },
              'brief': {
                'type': 'string',
                'description':
                    'Short natural language description in the user\'s language (e.g. "النقر على زر تسجيل الدخول")',
              },
            },
            'required': ['brief'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'browser_input',
          'description':
              'Type text into an input field by its index from the interactive_elements tree.',
          'parameters': {
            'type': 'object',
            'properties': {
              'index': {
                'type': 'integer',
                'description':
                    'Index of the input field (e.g. 1 for [1] <input type="text">)',
              },
              'text': {
                'type': 'string',
                'description': 'Text to enter into the input field',
              },
              'press_enter': {
                'type': 'boolean',
                'description': 'Whether to press Enter key after typing',
              },
              'brief': {
                'type': 'string',
                'description':
                    'Short natural language description in the user\'s language (e.g. "كتابة اسم المستخدم")',
              },
            },
            'required': ['text', 'brief'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'browser_scroll',
          'description': 'Scroll the browser viewport up or down.',
          'parameters': {
            'type': 'object',
            'properties': {
              'direction': {
                'type': 'string',
                'enum': ['up', 'down'],
                'description': 'Direction to scroll',
              },
              'brief': {
                'type': 'string',
                'description':
                    'Short natural language description in the user\'s language (e.g. "التمرير لأسفل الصفحة")',
              },
            },
            'required': ['brief'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'browser_press_key',
          'description': 'Press a keyboard key in the browser.',
          'parameters': {
            'type': 'object',
            'properties': {
              'key': {
                'type': 'string',
                'description':
                    'Key name to press (e.g. "Enter", "Escape", "Tab", "Backspace")',
              },
              'brief': {
                'type': 'string',
                'description': 'Short natural language description',
              },
            },
            'required': ['key', 'brief'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'browser_restart',
          'description': 'Restart the browser session.',
          'parameters': {
            'type': 'object',
            'properties': {
              'url': {'type': 'string', 'description': 'Optional initial URL'},
              'brief': {
                'type': 'string',
                'description': 'Short natural language description',
              },
            },
            'required': ['brief'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'mcp_call_tool',
          'description': 'Call an external MCP server tool.',
          'parameters': {
            'type': 'object',
            'properties': {
              'server_name': {'type': 'string'},
              'tool_name': {'type': 'string'},
              'arguments': {'type': 'object'},
              'brief': {
                'type': 'string',
                'description':
                    'Short natural language description (e.g. "Querying MCP tool")',
              },
            },
            'required': ['server_name', 'tool_name', 'arguments', 'brief'],
          },
        },
      },
    ];
  }

  Stream<ManusAgentEvent> runAgentLoop({
    required String conversationId,
    required String userRequest,
    WorkPlan? initialPlan,
    int maxIterations = 25,
    CancelToken? cancelToken,
    List<Map<String, dynamic>>? existingMessages,
    String? pendingToolCallId,
  }) async* {
    debugPrint(
      '[ManusAgentLoopService] Route: Work Loop initiated for conversation $conversationId',
    );
    debugPrint('[ManusAgentLoopService] User Request: "$userRequest"');

    // 0. Verify Daytona readiness
    try {
      final integration = await _persistence.fetchIntegrationStatus('daytona');
      if (integration != null && integration['status'] != null) {
        final status = integration['status'].toString();
        debugPrint(
          '[ManusAgentLoopService] Daytona integration status in DB: $status',
        );
      }
    } catch (e) {
      debugPrint(
        '[ManusAgentLoopService] Error checking Daytona integration: $e',
      );
    }

    WorkPlan currentPlan = initialPlan ?? const WorkPlan();
    final List<Map<String, dynamic>> messages = [];
    final toolSchemas = _getToolSchemas();
    final toolNames = toolSchemas
        .map((t) => (t['function'] as Map<String, dynamic>)['name'] as String)
        .toList();
    debugPrint(
      '[ManusAgentLoopService] Request tool names (${toolNames.length}): ${toolNames.join(', ')}',
    );

    // Dynamically composed system prompt
    final systemPrompt = buildSystemPrompt(toolSchemas);
    if (existingMessages != null && existingMessages.isNotEmpty) {
      messages.addAll(existingMessages);
      if (pendingToolCallId != null && pendingToolCallId.isNotEmpty) {
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
    } else {
      messages.add({'role': 'system', 'content': systemPrompt});
      messages.add({'role': 'user', 'content': userRequest});
    }

    int iteration = 0;
    bool isDone = false;

    while (iteration < maxIterations && !isDone) {
      if (cancelToken?.isCancelled ?? false) {
        yield const ManusErrorEvent('Task cancelled by user.');
        break;
      }

      iteration++;

      // Inject current plan progress into root system prompt if active
      if (currentPlan.isNotEmpty) {
        final planSummary = currentPlan.steps
            .map((s) => '- [${s.status.toSerializedString()}] ${s.description}')
            .join('\n');
        messages[0] = {
          'role': 'system',
          'content': '$systemPrompt\n\nCurrent Plan Progress:\n$planSummary',
        };
      }

      Map<String, dynamic>? completionData;
      const currentToolChoice = 'any';

      // 1. Invoke Supabase Edge Function 'chat' or test chatInvoker
      if (chatInvoker != null) {
        try {
          completionData = await chatInvoker!({
            'model': fixedModel,
            'messages': List<Map<String, dynamic>>.from(messages),
            'tools': toolSchemas,
            'tool_choice': currentToolChoice,
            'stream': false,
          });
        } catch (e) {
          debugPrint('[ManusAgentLoopService] chatInvoker failed: $e');
          yield ManusErrorEvent('Failed to communicate with AI model: $e');
          break;
        }
      } else if (!SupabaseConfig.isUnconfigured) {
        try {
          await SupabaseConfig.ensureValidToken();
          final client = SupabaseConfig.client;
          final token = client.auth.currentSession?.accessToken;
          final res = await client.functions.invoke(
            'chat',
            body: {
              'model': fixedModel,
              'messages': messages,
              'tools': toolSchemas,
              'tool_choice': currentToolChoice,
              'stream': false,
            },
            headers: {if (token != null) 'Authorization': 'Bearer $token'},
          );
          if (res.status < 400 && res.data != null) {
            completionData = res.data is String
                ? jsonDecode(res.data as String) as Map<String, dynamic>
                : res.data as Map<String, dynamic>;
          } else {
            final errMsg =
                '[ManusAgentLoopService] chat edge returned status ${res.status}: ${res.data}';
            debugPrint(errMsg);
            yield ManusErrorEvent(
              'Edge function error (${res.status}): ${res.data}',
            );
            break;
          }
        } catch (e) {
          debugPrint(
            '[ManusAgentLoopService] Edge function chat invoke failed: $e',
          );
          yield ManusErrorEvent('Failed to communicate with AI model: $e');
          break;
        }
      }

      // If no completion data was returned, fail honestly with real error
      if (completionData == null) {
        yield const ManusErrorEvent(
          'Could not receive response from AI model. Please verify your connection.',
        );
        break;
      }

      final choices = completionData['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        yield const ManusErrorEvent('Empty response received from LLM.');
        break;
      }

      final choice = choices.first as Map<String, dynamic>;
      final messageObj = choice['message'] as Map<String, dynamic>;
      final content = messageObj['content']?.toString() ?? '';
      final toolCalls =
          (messageObj['tool_calls'] ?? messageObj['toolCalls'])
              as List<dynamic>?;

      if (toolCalls != null && toolCalls.isNotEmpty) {
        for (int i = 0; i < toolCalls.length; i++) {
          final rawCall = toolCalls[i];
          if (rawCall is! Map<String, dynamic>) {
            yield const ManusErrorEvent(
              'Invalid tool call structure returned by LLM.',
            );
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

        final calledNames = toolCalls
            .map(
              (c) =>
                  (c as Map<String, dynamic>)['function']?['name']
                      ?.toString() ??
                  '',
            )
            .join(', ');
        debugPrint('[ManusAgentLoopService] Response tool calls: $calledNames');
      } else {
        messages.add(messageObj);
        debugPrint(
          '[ManusAgentLoopService] LLM returned plain text (len: ${content.length}): $content',
        );
        if (content.isNotEmpty) {
          yield ManusThinkingEvent(content);
        }
        // A plain text answer must NEVER end a Work run!
        messages.add({
          'role': 'user',
          'content':
              'You have not called any tools on your computer. You must use your tools to perform the task on your computer (e.g. browser_navigate, shell_exec, file_write). Do not answer in plain text. Execute the task now.',
        });
        continue;
      }

      // Process tool calls in order
      for (final rawToolCall in toolCalls) {
        if (cancelToken?.isCancelled ?? false) break;

        final toolCall = rawToolCall as Map<String, dynamic>;
        final toolCallId = toolCall['id']!.toString().trim();
        final functionObj = toolCall['function'] as Map<String, dynamic>;
        final toolName = functionObj['name']?.toString() ?? '';
        final rawArgs = functionObj['arguments'];
        Map<String, dynamic> args = {};
        if (rawArgs is String) {
          try {
            args = jsonDecode(rawArgs) as Map<String, dynamic>;
          } catch (_) {}
        } else if (rawArgs is Map) {
          args = Map<String, dynamic>.from(rawArgs);
        }

        final brief = args['brief']?.toString() ?? toolName;
        final currentRunningStep = currentPlan.currentRunningStep;
        final stepId = currentRunningStep?.id ?? 'step_$iteration';

        String category = 'mcp';
        if (toolName.startsWith('shell_')) {
          category = 'shell';
        } else if (toolName.startsWith('file_')) {
          category = 'file';
        } else if (toolName.startsWith('browser_')) {
          category = 'browser';
        } else if (toolName.contains('search')) {
          category = 'search';
        } else if (toolName.startsWith('message_')) {
          category = 'message';
        } else if (toolName == 'plan_report' || toolName == 'replan') {
          category = 'plan';
        }

        final bool isMetaTool =
            toolName.startsWith('message_') ||
            toolName == 'plan_report' ||
            toolName == 'replan' ||
            toolName == 'deliver_result';

        final toolEvent = WorkToolEvent(
          id: toolCallId,
          stepId: stepId,
          toolName: toolName,
          toolCategory: category,
          brief: brief,
          arguments: args,
          status: 'running',
          timestamp: DateTime.now(),
        );

        if (!isMetaTool) {
          yield ManusToolStartedEvent(toolEvent);
        }

        dynamic executionResult;
        String? originalContent;
        String? modifiedContent;
        String? browserUrl;
        String? screenshotUrl;

        bool toolSuccess = true;
        try {
          if (toolName == 'message_notify_user') {
            final msg = args['message']?.toString() ?? '';
            debugPrint(
              '[ManusAgentLoopService] message_notify_user call: "$msg"',
            );
            yield ManusMessageNotifyEvent(msg);
            executionResult = {'status': 'ok', 'delivered': true};
          } else if (toolName == 'message_ask_user') {
            final question = args['question']?.toString() ?? '';
            debugPrint(
              '[ManusAgentLoopService] message_ask_user call: "$question"',
            );
            yield ManusMessageAskEvent(
              question,
              toolCallId,
              List<Map<String, dynamic>>.from(messages),
            );
            isDone = true;
            executionResult = {
              'status': 'waiting_for_user_response',
              'question': question,
            };
          } else if (toolName == 'plan_report') {
            final title = args['title']?.toString() ?? '';
            final goal = args['goal']?.toString() ?? '';
            final rawSteps = args['steps'] as List<dynamic>? ?? [];
            final steps = rawSteps.map((s) {
              final map = Map<String, dynamic>.from(s as Map);
              return WorkStep(
                id: map['id']?.toString() ?? '',
                description: map['description']?.toString() ?? '',
                status: WorkStepStatus.fromString(
                  map['status']?.toString() ?? 'pending',
                ),
              );
            }).toList();

            currentPlan = WorkPlan(
              title: title.isNotEmpty ? title : currentPlan.title,
              goal: goal.isNotEmpty ? goal : currentPlan.goal,
              steps: steps,
            );
            yield ManusPlanEvent(currentPlan);
            executionResult = {'status': 'ok', 'plan_updated': true};
          } else if (toolName == 'replan') {
            final reason = args['reason']?.toString() ?? '';
            final rawRemaining =
                args['remaining_steps'] as List<dynamic>? ?? [];
            final completedSteps = currentPlan.steps
                .where((s) => s.isCompleted)
                .toList();
            final newSteps = rawRemaining.map((s) {
              final map = Map<String, dynamic>.from(s as Map);
              return WorkStep(
                id: map['id']?.toString() ?? '',
                description: map['description']?.toString() ?? '',
                status: WorkStepStatus.pending,
              );
            }).toList();

            currentPlan = currentPlan.copyWith(
              steps: [...completedSteps, ...newSteps],
            );
            yield ManusPlanEvent(currentPlan);
            executionResult = {
              'status': 'ok',
              'replan_applied': true,
              'reason': reason,
            };
          } else if (toolName == 'deliver_result') {
            final summary =
                args['message']?.toString() ??
                args['summary']?.toString() ??
                '';
            debugPrint(
              '[ManusAgentLoopService] deliver_result call: summary="$summary"',
            );
            final rawAttachments = args['attachments'] as List<dynamic>? ?? [];
            final attachments = <WorkAttachment>[];

            for (final item in rawAttachments) {
              final path = item.toString();
              final name = path.split('/').last;
              final ext = name.contains('.') ? name.split('.').last : 'txt';

              int size = 0;
              String? preview;
              try {
                final fileRes = await _runtime.invokeDaytona(
                  action: 'file_read',
                  params: {'path': path, 'limit': 30},
                );
                preview = fileRes['content']?.toString();
                size = preview?.length ?? 0;
              } catch (_) {}

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

            final result = WorkTaskResult(
              summary: summary,
              attachments: attachments,
              completedAt: DateTime.now(),
            );

            yield ManusTaskCompletedEvent(result);
            isDone = true;
            executionResult = {'status': 'ok', 'delivered': true};
          } else if (toolName == 'shell_exec') {
            final command = args['command']?.toString() ?? '';
            final res = await _runtime.invokeDaytona(
              action: 'shell',
              params: {'command': command, 'cwd': args['cwd']},
            );
            final out =
                res['output']?.toString() ?? res['stdout']?.toString() ?? '';
            final err = res['stderr']?.toString() ?? '';
            executionResult = out.isNotEmpty
                ? out
                : (err.isNotEmpty
                      ? 'Stderr: $err'
                      : 'Command completed (exit code ${res['exitCode'] ?? 0})');
          } else if (toolName == 'shell_view') {
            executionResult = 'Process output: completed';
          } else if (toolName == 'shell_wait') {
            final seconds = args['seconds'] as int? ?? 1;
            await Future.delayed(Duration(seconds: seconds));
            executionResult = 'Wait completed after ${seconds}s';
          } else if (toolName == 'shell_kill_process') {
            executionResult = 'Process terminated';
          } else if (toolName == 'file_read') {
            final path =
                args['file_path']?.toString() ?? args['path']?.toString() ?? '';
            final res = await _runtime.invokeDaytona(
              action: 'file_read',
              params: {
                'path': path,
                'file_path': path,
                'offset': args['offset'],
                'limit': args['limit'],
              },
            );
            originalContent = res['content']?.toString();
            executionResult = originalContent ?? '';
          } else if (toolName == 'file_write') {
            final path =
                args['file_path']?.toString() ?? args['path']?.toString() ?? '';
            final content = args['content']?.toString() ?? '';
            final append = args['append'] == true;
            try {
              final prev = await _runtime.invokeDaytona(
                action: 'file_read',
                params: {'path': path, 'file_path': path},
              );
              originalContent = prev['content']?.toString();
            } catch (_) {}

            final res = await _runtime.invokeDaytona(
              action: 'file_write',
              params: {
                'path': path,
                'file_path': path,
                'content': content,
                'append': append,
              },
            );
            modifiedContent = content;
            executionResult = res['message'] ?? 'File written successfully';
          } else if (toolName == 'file_str_replace') {
            final path =
                args['file_path']?.toString() ?? args['path']?.toString() ?? '';
            final oldStr = args['old_str']?.toString() ?? '';
            final newStr = args['new_str']?.toString() ?? '';

            try {
              final prev = await _runtime.invokeDaytona(
                action: 'file_read',
                params: {'path': path, 'file_path': path},
              );
              originalContent = prev['content']?.toString();
            } catch (_) {}

            final res = await _runtime.invokeDaytona(
              action: 'file_replace',
              params: {
                'path': path,
                'file_path': path,
                'oldStr': oldStr,
                'newStr': newStr,
              },
            );
            modifiedContent =
                res['newContent']?.toString() ??
                originalContent?.replaceAll(oldStr, newStr);
            executionResult = res['message'] ?? 'Replacement succeeded';
          } else if (toolName == 'file_find_by_name') {
            final pattern = args['pattern']?.toString() ?? '*';
            final path = args['dir_path']?.toString() ?? '/';
            final res = await _runtime.glob(pattern, path: path);
            executionResult = jsonEncode(res);
          } else if (toolName == 'file_find_in_content') {
            final regex = args['regex']?.toString() ?? '';
            final path = args['file_path']?.toString() ?? '.';
            final res = await _runtime.grep(regex, path: path);
            executionResult = jsonEncode(res);
          } else if (toolName == 'info_search_web' ||
              toolName == 'search_web') {
            final query = args['query']?.toString() ?? '';
            final searchResults = await _runtime.searchWeb(query);
            executionResult = jsonEncode(searchResults);
          } else if (toolName == 'browser_navigate') {
            final urlArg = args['url']?.toString().trim() ?? '';
            final url = urlArg.isNotEmpty ? urlArg : 'https://www.google.com';
            debugPrint(
              '[ManusAgentLoopService] browser_navigate call: url=$url, brief=$brief',
            );
            final navRes = await _runtime.navigateBrowser(url);
            browserUrl = navRes['url']?.toString() ?? url;
            screenshotUrl = navRes['screenshot_url']?.toString();
            final title = navRes['title']?.toString() ?? '';
            final elements =
                (navRes['interactive_elements'] as List<dynamic>?)?.join(
                  '\n',
                ) ??
                '';
            debugPrint(
              '[ManusAgentLoopService] browser_navigate done: title=$title, elements=${(navRes['interactive_elements'] as List<dynamic>?)?.length ?? 0}, screenshot=$screenshotUrl',
            );
            executionResult =
                'Page loaded: $title ($browserUrl)\n\nInteractive elements:\n$elements';
          } else if (toolName == 'browser_view') {
            debugPrint(
              '[ManusAgentLoopService] browser_view call: brief=$brief',
            );
            final viewRes = await _runtime.browserView();
            browserUrl = viewRes['url']?.toString();
            screenshotUrl = viewRes['screenshot_url']?.toString();
            final title = viewRes['title']?.toString() ?? '';
            final elements =
                (viewRes['interactive_elements'] as List<dynamic>?)?.join(
                  '\n',
                ) ??
                '';
            executionResult =
                'Current page: $title ($browserUrl)\n\nInteractive elements:\n$elements';
          } else if (toolName == 'browser_click') {
            final rawIndex = args['index'];
            final index = rawIndex is int
                ? rawIndex
                : int.tryParse(rawIndex?.toString() ?? '');
            final rawX = args['coordinate_x'];
            final x = rawX is int ? rawX : int.tryParse(rawX?.toString() ?? '');
            final rawY = args['coordinate_y'];
            final y = rawY is int ? rawY : int.tryParse(rawY?.toString() ?? '');
            debugPrint(
              '[ManusAgentLoopService] browser_click call: index=$index, x=$x, y=$y, brief=$brief',
            );
            final clickRes = await _runtime.browserClick(
              index: index,
              x: x,
              y: y,
            );
            browserUrl = clickRes['url']?.toString();
            screenshotUrl = clickRes['screenshot_url']?.toString();
            final title = clickRes['title']?.toString() ?? '';
            final elements =
                (clickRes['interactive_elements'] as List<dynamic>?)?.join(
                  '\n',
                ) ??
                '';
            executionResult =
                'Clicked element ${index ?? ""}. Current page: $title ($browserUrl)\n\nInteractive elements:\n$elements';
          } else if (toolName == 'browser_input') {
            final rawIndex = args['index'];
            final index = rawIndex is int
                ? rawIndex
                : int.tryParse(rawIndex?.toString() ?? '');
            final text = args['text']?.toString() ?? '';
            final pressEnter = args['press_enter'] == true;
            debugPrint(
              '[ManusAgentLoopService] browser_input call: index=$index, text="$text", enter=$pressEnter, brief=$brief',
            );
            final inputRes = await _runtime.browserInput(
              index: index,
              text: text,
              pressEnter: pressEnter,
            );
            browserUrl = inputRes['url']?.toString();
            screenshotUrl = inputRes['screenshot_url']?.toString();
            final title = inputRes['title']?.toString() ?? '';
            final elements =
                (inputRes['interactive_elements'] as List<dynamic>?)?.join(
                  '\n',
                ) ??
                '';
            executionResult =
                'Typed text into element ${index ?? ""}. Current page: $title ($browserUrl)\n\nInteractive elements:\n$elements';
          } else if (toolName == 'browser_scroll') {
            final direction = args['direction']?.toString() ?? 'down';
            debugPrint(
              '[ManusAgentLoopService] browser_scroll call: direction=$direction, brief=$brief',
            );
            final scrollRes = await _runtime.browserScroll(
              direction: direction,
            );
            browserUrl = scrollRes['url']?.toString();
            screenshotUrl = scrollRes['screenshot_url']?.toString();
            final elements =
                (scrollRes['interactive_elements'] as List<dynamic>?)?.join(
                  '\n',
                ) ??
                '';
            executionResult =
                'Scrolled $direction. Interactive elements:\n$elements';
          } else if (toolName == 'browser_press_key') {
            final key = args['key']?.toString() ?? 'Enter';
            debugPrint(
              '[ManusAgentLoopService] browser_press_key call: key=$key, brief=$brief',
            );
            final keyRes = await _runtime.browserPressKey(key: key);
            browserUrl = keyRes['url']?.toString();
            screenshotUrl = keyRes['screenshot_url']?.toString();
            final elements =
                (keyRes['interactive_elements'] as List<dynamic>?)?.join(
                  '\n',
                ) ??
                '';
            executionResult =
                'Pressed key $key. Interactive elements:\n$elements';
          } else if (toolName == 'browser_restart') {
            final url = args['url']?.toString();
            debugPrint(
              '[ManusAgentLoopService] browser_restart call: url=$url, brief=$brief',
            );
            final restartRes = await _runtime.browserRestart(url: url);
            browserUrl = restartRes['url']?.toString();
            screenshotUrl = restartRes['screenshot_url']?.toString();
            final title = restartRes['title']?.toString() ?? '';
            final elements =
                (restartRes['interactive_elements'] as List<dynamic>?)?.join(
                  '\n',
                ) ??
                '';
            executionResult =
                'Browser restarted at $browserUrl. Current page: $title\n\nInteractive elements:\n$elements';
          } else {
            executionResult = {'status': 'unsupported_tool', 'tool': toolName};
          }
        } catch (err) {
          toolSuccess = false;
          executionResult = 'Tool execution failed: $err';
        }

        final finishedEvent = toolEvent.copyWith(
          result: executionResult is String
              ? executionResult
              : jsonEncode(executionResult),
          originalFileContent: originalContent,
          modifiedFileContent: modifiedContent,
          browserUrl: browserUrl,
          screenshotUrl: screenshotUrl,
          status: toolSuccess ? 'completed' : 'failed',
        );

        if (!isMetaTool) {
          // Attach tool event to current running step in plan
          if (currentRunningStep != null) {
            final updatedSteps = currentPlan.steps.map((s) {
              if (s.id == currentRunningStep.id) {
                return s.copyWith(tools: [...s.tools, finishedEvent]);
              }
              return s;
            }).toList();
            currentPlan = currentPlan.copyWith(steps: updatedSteps);
            yield ManusPlanEvent(currentPlan);
          }

          yield ManusToolFinishedEvent(finishedEvent);

          // Persist tool event to Supabase
          await _persistence.saveToolEvent(conversationId, finishedEvent);
        }

        messages.add({
          'role': 'tool',
          'tool_call_id': toolCallId,
          'toolCallId': toolCallId,
          'name': toolName,
          'content': finishedEvent.result,
        });

        if (isDone) break;
      }
    }
  }
}
