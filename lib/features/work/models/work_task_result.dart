class WorkAttachment {
  final String name;
  final String path;
  final int sizeInBytes;
  final String fileType; // 'html', 'pdf', 'png', 'js', 'py', 'txt', etc.
  final String? previewContent;

  const WorkAttachment({
    required this.name,
    required this.path,
    this.sizeInBytes = 0,
    required this.fileType,
    this.previewContent,
  });

  String get formattedSize {
    if (sizeInBytes < 1024) {
      return '$sizeInBytes B';
    }
    if (sizeInBytes < 1024 * 1024) {
      return '${(sizeInBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'size_in_bytes': sizeInBytes,
      'file_type': fileType,
      if (previewContent != null) 'preview_content': previewContent,
    };
  }

  factory WorkAttachment.fromJson(Map<String, dynamic> json) {
    return WorkAttachment(
      name: json['name']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      sizeInBytes:
          (json['size_in_bytes'] as num?)?.toInt() ??
          (json['size'] as num?)?.toInt() ??
          0,
      fileType:
          json['file_type']?.toString() ?? json['type']?.toString() ?? 'txt',
      previewContent: json['preview_content']?.toString(),
    );
  }
}

class WorkTaskResult {
  final String summary;
  final List<WorkAttachment> attachments;
  final DateTime completedAt;

  const WorkTaskResult({
    required this.summary,
    this.attachments = const [],
    required this.completedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'summary': summary,
      'attachments': attachments.map((a) => a.toJson()).toList(),
      'completed_at': completedAt.toIso8601String(),
    };
  }

  factory WorkTaskResult.fromJson(Map<String, dynamic> json) {
    final rawAttachments = json['attachments'] as List<dynamic>? ?? const [];
    return WorkTaskResult(
      summary: json['summary']?.toString() ?? '',
      attachments: rawAttachments
          .map(
            (a) => WorkAttachment.fromJson(Map<String, dynamic>.from(a as Map)),
          )
          .toList(),
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
