import 'work_tool_event.dart';

enum WorkStepStatus {
  pending,
  running,
  completed,
  failed;

  static WorkStepStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'running':
        return WorkStepStatus.running;
      case 'completed':
        return WorkStepStatus.completed;
      case 'failed':
        return WorkStepStatus.failed;
      default:
        return WorkStepStatus.pending;
    }
  }

  String toSerializedString() {
    switch (this) {
      case WorkStepStatus.running:
        return 'running';
      case WorkStepStatus.completed:
        return 'completed';
      case WorkStepStatus.failed:
        return 'failed';
      case WorkStepStatus.pending:
        return 'pending';
    }
  }
}

class WorkStep {
  final String id;
  final String description;
  final WorkStepStatus status;
  final String? reflection;
  final List<WorkToolEvent> tools;

  const WorkStep({
    required this.id,
    required this.description,
    this.status = WorkStepStatus.pending,
    this.reflection,
    this.tools = const [],
  });

  bool get isRunning => status == WorkStepStatus.running;
  bool get isCompleted => status == WorkStepStatus.completed;
  bool get isPending => status == WorkStepStatus.pending;
  bool get isFailed => status == WorkStepStatus.failed;

  WorkStep copyWith({
    String? id,
    String? description,
    WorkStepStatus? status,
    String? reflection,
    List<WorkToolEvent>? tools,
  }) {
    return WorkStep(
      id: id ?? this.id,
      description: description ?? this.description,
      status: status ?? this.status,
      reflection: reflection ?? this.reflection,
      tools: tools ?? this.tools,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'description': description,
      'status': status.toSerializedString(),
      if (reflection != null) 'reflection': reflection,
      'tools': tools.map((t) => t.toJson()).toList(),
    };
  }

  factory WorkStep.fromJson(Map<String, dynamic> json) {
    return WorkStep(
      id: json['id']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      status: WorkStepStatus.fromString(
        json['status']?.toString() ?? 'pending',
      ),
      reflection: json['reflection']?.toString(),
      tools:
          (json['tools'] as List<dynamic>?)
              ?.map(
                (e) =>
                    WorkToolEvent.fromJson(Map<String, dynamic>.from(e as Map)),
              )
              .toList() ??
          const [],
    );
  }
}
