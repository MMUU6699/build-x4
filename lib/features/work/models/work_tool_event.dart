class WorkToolEvent {
  final String id;
  final String stepId;
  final String toolName;
  final String
  toolCategory; // 'shell', 'file', 'browser', 'search', 'mcp', 'plan', 'message'
  final String brief;
  final Map<String, dynamic> arguments;
  final String result;
  final String? originalFileContent;
  final String? modifiedFileContent;
  final String? browserUrl;
  final String? screenshotUrl;
  final String status; // 'calling', 'running', 'completed', 'failed'
  final DateTime timestamp;

  const WorkToolEvent({
    required this.id,
    required this.stepId,
    required this.toolName,
    required this.toolCategory,
    required this.brief,
    this.arguments = const {},
    this.result = '',
    this.originalFileContent,
    this.modifiedFileContent,
    this.browserUrl,
    this.screenshotUrl,
    this.status = 'completed',
    required this.timestamp,
  });

  bool get isCalling => status == 'calling' || status == 'running';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';

  bool get isShell => toolCategory == 'shell' || toolName.startsWith('shell_');
  bool get isFile => toolCategory == 'file' || toolName.startsWith('file_');
  bool get isBrowser =>
      toolCategory == 'browser' || toolName.startsWith('browser_');
  bool get isSearch => toolCategory == 'search' || toolName.contains('search');
  bool get isMcp => toolCategory == 'mcp' || toolName.startsWith('mcp_');
  bool get isPlan =>
      toolCategory == 'plan' ||
      toolName == 'plan_report' ||
      toolName == 'replan';
  bool get isMessage =>
      toolCategory == 'message' || toolName.startsWith('message_');

  WorkToolEvent copyWith({
    String? id,
    String? stepId,
    String? toolName,
    String? toolCategory,
    String? brief,
    Map<String, dynamic>? arguments,
    String? result,
    String? originalFileContent,
    String? modifiedFileContent,
    String? browserUrl,
    String? screenshotUrl,
    String? status,
    DateTime? timestamp,
  }) {
    return WorkToolEvent(
      id: id ?? this.id,
      stepId: stepId ?? this.stepId,
      toolName: toolName ?? this.toolName,
      toolCategory: toolCategory ?? this.toolCategory,
      brief: brief ?? this.brief,
      arguments: arguments ?? this.arguments,
      result: result ?? this.result,
      originalFileContent: originalFileContent ?? this.originalFileContent,
      modifiedFileContent: modifiedFileContent ?? this.modifiedFileContent,
      browserUrl: browserUrl ?? this.browserUrl,
      screenshotUrl: screenshotUrl ?? this.screenshotUrl,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'step_id': stepId,
      'tool_name': toolName,
      'tool_category': toolCategory,
      'brief': brief,
      'arguments': arguments,
      'result': result,
      if (originalFileContent != null)
        'original_file_content': originalFileContent,
      if (modifiedFileContent != null)
        'modified_file_content': modifiedFileContent,
      if (browserUrl != null) 'browser_url': browserUrl,
      if (screenshotUrl != null) 'screenshot_url': screenshotUrl,
      'status': status,
      'created_at': timestamp.toIso8601String(),
    };
  }

  factory WorkToolEvent.fromJson(Map<String, dynamic> json) {
    return WorkToolEvent(
      id: json['id']?.toString() ?? '',
      stepId: json['step_id']?.toString() ?? json['stepId']?.toString() ?? '',
      toolName:
          json['tool_name']?.toString() ?? json['toolName']?.toString() ?? '',
      toolCategory:
          json['tool_category']?.toString() ??
          json['toolCategory']?.toString() ??
          'mcp',
      brief: json['brief']?.toString() ?? '',
      arguments: json['arguments'] is Map
          ? Map<String, dynamic>.from(json['arguments'] as Map)
          : const {},
      result: json['result']?.toString() ?? '',
      originalFileContent:
          json['original_file_content']?.toString() ??
          json['originalFileContent']?.toString(),
      modifiedFileContent:
          json['modified_file_content']?.toString() ??
          json['modifiedFileContent']?.toString(),
      browserUrl:
          json['browser_url']?.toString() ?? json['browserUrl']?.toString(),
      screenshotUrl:
          json['screenshot_url']?.toString() ??
          json['screenshotUrl']?.toString(),
      status: json['status']?.toString() ?? 'completed',
      timestamp: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : (json['timestamp'] != null
                ? DateTime.tryParse(json['timestamp'].toString()) ??
                      DateTime.now()
                : DateTime.now()),
    );
  }
}
