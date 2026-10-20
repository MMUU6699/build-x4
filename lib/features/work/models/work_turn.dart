import 'work_task_result.dart';
import 'work_tool_event.dart';

/// One user prompt and everything the agent did for it.
///
/// A turn is the unit rendered in the conversation thread. It survives app
/// restart through `work_turns` and never replaces earlier turns.
class WorkTurn {
  const WorkTurn({
    required this.id,
    required this.conversationId,
    required this.prompt,
    this.introMessage = '',
    this.question,
    this.pendingToolCallId,
    this.events = const [],
    this.finalAnswer,
    this.error,
    this.result,
    this.durationSeconds = 0,
    this.status = 'running',
    required this.startedAt,
  });

  final String id;
  final String conversationId;
  final String prompt;
  final String introMessage;
  final String? question;

  /// Tool-call id of the pending `message_ask_user`, used to resume the model
  /// turn after the user answers.
  final String? pendingToolCallId;
  final List<WorkToolEvent> events;
  final String? finalAnswer;
  final String? error;
  final WorkTaskResult? result;
  final int durationSeconds;
  final String status; // running | waiting | completed | error | idle
  final DateTime startedAt;

  bool get isRunning => status == 'running';
  bool get isWaiting => status == 'waiting';
  bool get isCompleted => status == 'completed';
  bool get isError => status == 'error';
  bool get isStopped => status == 'stopped';

  WorkTurn copyWith({
    String? id,
    String? conversationId,
    String? prompt,
    String? introMessage,
    String? question,
    String? pendingToolCallId,
    List<WorkToolEvent>? events,
    String? finalAnswer,
    String? error,
    WorkTaskResult? result,
    int? durationSeconds,
    String? status,
    DateTime? startedAt,
  }) {
    return WorkTurn(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      prompt: prompt ?? this.prompt,
      introMessage: introMessage ?? this.introMessage,
      question: question ?? this.question,
      pendingToolCallId: pendingToolCallId ?? this.pendingToolCallId,
      events: events ?? this.events,
      finalAnswer: finalAnswer ?? this.finalAnswer,
      error: error ?? this.error,
      result: result ?? this.result,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'prompt': prompt,
      'intro_message': introMessage,
      if (question != null) 'question': question,
      if (pendingToolCallId != null) 'pending_tool_call_id': pendingToolCallId,
      'events': events.map((e) => e.toJson()).toList(),
      if (finalAnswer != null) 'final_answer': finalAnswer,
      if (error != null) 'error': error,
      if (result != null) 'attachments': result!.toJson()['attachments'],
      'duration_seconds': durationSeconds,
      'status': status,
      'started_at': startedAt.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  factory WorkTurn.fromJson(Map<String, dynamic> json) {
    final rawEvents = json['events'];
    final events = <WorkToolEvent>[];
    if (rawEvents is List) {
      for (final item in rawEvents) {
        if (item is Map) {
          events.add(WorkToolEvent.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final answer = json['final_answer']?.toString();
    final error = json['error']?.toString();
    return WorkTurn(
      id: json['id']?.toString() ?? '',
      conversationId: json['conversation_id']?.toString() ?? '',
      prompt: json['prompt']?.toString() ?? '',
      introMessage: json['intro_message']?.toString() ?? '',
      question: json['question']?.toString(),
      pendingToolCallId:
          json['pending_tool_call_id']?.toString() ??
          json['pendingToolCallId']?.toString(),
      events: events,
      finalAnswer: answer,
      error: error,
      result: answer != null
          ? WorkTaskResult(
              summary: answer,
              attachments: _attachmentsFromJson(json['attachments']),
              completedAt: json['updated_at'] != null
                  ? DateTime.tryParse(json['updated_at'].toString()) ??
                        DateTime.now()
                  : DateTime.now(),
            )
          : null,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? 'completed',
      startedAt: json['started_at'] != null
          ? DateTime.tryParse(json['started_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

List<WorkAttachment> _attachmentsFromJson(dynamic raw) {
  if (raw is! List) return const [];
  final attachments = <WorkAttachment>[];
  for (final item in raw) {
    if (item is Map) {
      attachments.add(WorkAttachment.fromJson(Map<String, dynamic>.from(item)));
    }
  }
  return attachments;
}
