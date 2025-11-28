import 'package:cloud_firestore/cloud_firestore.dart';

enum LogCategory { user, transaction, content, admin, system }

enum LogSeverity { info, warning, critical }

class ActivityLogModel {
  final String id;
  final DateTime timestamp;
  final LogCategory category;
  final String action;
  final String actorId;
  final String actorName;
  final String? targetId;
  final String? targetType;
  final String description;
  final Map<String, dynamic> metadata;
  final LogSeverity severity;

  ActivityLogModel({
    required this.id,
    required this.timestamp,
    required this.category,
    required this.action,
    required this.actorId,
    required this.actorName,
    this.targetId,
    this.targetType,
    required this.description,
    this.metadata = const {},
    this.severity = LogSeverity.info,
  });

  factory ActivityLogModel.fromMap(Map<String, dynamic> data, String id) {
    LogCategory parseCategory(String? s) {
      final val = (s ?? '').toLowerCase();
      for (final c in LogCategory.values) {
        if (c.name.toLowerCase() == val) return c;
      }
      return LogCategory.system;
    }

    LogSeverity parseSeverity(String? s) {
      final val = (s ?? '').toLowerCase();
      for (final sev in LogSeverity.values) {
        if (sev.name.toLowerCase() == val) return sev;
      }
      return LogSeverity.info;
    }

    return ActivityLogModel(
      id: id,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      category: parseCategory(data['category']?.toString()),
      action: data['action'] ?? '',
      actorId: data['actorId'] ?? '',
      actorName: data['actorName'] ?? '',
      targetId: data['targetId']?.toString(),
      targetType: data['targetType']?.toString(),
      description: data['description'] ?? '',
      metadata: Map<String, dynamic>.from(data['metadata'] ?? {}),
      severity: parseSeverity(data['severity']?.toString()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'timestamp': Timestamp.fromDate(timestamp),
      'category': category.name,
      'action': action,
      'actorId': actorId,
      'actorName': actorName,
      'targetId': targetId,
      'targetType': targetType,
      'description': description,
      'metadata': metadata,
      'severity': severity.name,
    };
  }

  String get categoryDisplay {
    switch (category) {
      case LogCategory.user:
        return 'User Action';
      case LogCategory.transaction:
        return 'Transaction';
      case LogCategory.content:
        return 'Content';
      case LogCategory.admin:
        return 'Admin Action';
      case LogCategory.system:
        return 'System';
    }
  }

  String get severityDisplay {
    switch (severity) {
      case LogSeverity.info:
        return 'Info';
      case LogSeverity.warning:
        return 'Warning';
      case LogSeverity.critical:
        return 'Critical';
    }
  }
}
