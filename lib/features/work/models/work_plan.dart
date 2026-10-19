import 'work_step.dart';

class WorkPlan {
  final String title;
  final String goal;
  final List<WorkStep> steps;

  const WorkPlan({this.title = '', this.goal = '', this.steps = const []});

  bool get isEmpty => steps.isEmpty;
  bool get isNotEmpty => steps.isNotEmpty;

  int get totalCount => steps.length;
  int get completedCount => steps.where((s) => s.isCompleted).length;

  double get progressPercentage {
    if (totalCount == 0) return 0.0;
    return (completedCount / totalCount).clamp(0.0, 1.0);
  }

  WorkStep? get currentRunningStep {
    final running = steps.where((s) => s.isRunning);
    if (running.isNotEmpty) return running.first;
    final pending = steps.where((s) => s.isPending);
    if (pending.isNotEmpty) return pending.first;
    return null;
  }

  bool get isAllCompleted => totalCount > 0 && completedCount == totalCount;

  WorkPlan copyWith({String? title, String? goal, List<WorkStep>? steps}) {
    return WorkPlan(
      title: title ?? this.title,
      goal: goal ?? this.goal,
      steps: steps ?? this.steps,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'goal': goal,
      'steps': steps.map((s) => s.toJson()).toList(),
    };
  }

  factory WorkPlan.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'] as List<dynamic>? ?? const [];
    return WorkPlan(
      title: json['title']?.toString() ?? '',
      goal: json['goal']?.toString() ?? '',
      steps: rawSteps
          .map((e) => WorkStep.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}
