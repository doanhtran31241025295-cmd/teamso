import 'package:flutter/foundation.dart';

@immutable
class TaskModel {
  const TaskModel({
    required this.id,
    required this.projectId,
    required this.title,
    required this.status,
    required this.assigneeId,
    this.description = '',
    this.assigneeName = '',
    this.priority = 'Trung bình',
    this.dueDate,
    this.outputType = 'docs',
    this.outputRequired = true,
    this.outputLink = '',
    this.reviewComment = '',
    this.deadlineRequest,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String projectId;
  final String title;
  final String description;
  final String status;
  final String assigneeId;
  final String assigneeName;
  final String priority;
  final DateTime? dueDate;
  final String outputType;
  final bool outputRequired;
  final String outputLink;
  final String reviewComment;
  final DeadlineRequest? deadlineRequest;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isDone => const [
    'done',
    'completed',
    'hoàn thành',
  ].contains(status.toLowerCase().trim());

  String get priorityLabel => switch (priority.toLowerCase()) {
    'high' || 'cao' => 'Cao',
    'low' || 'thấp' => 'Thấp',
    _ => 'Trung bình',
  };

  factory TaskModel.fromJson(Map<String, dynamic> json) => TaskModel(
    id: _text(json['id'] ?? json['_id'] ?? json['taskId']),
    projectId: _text(json['projectId'] ?? json['project_id']),
    title: _text(json['title'] ?? json['name'], 'Công việc'),
    description: _text(json['description']),
    status: _normalizeStatus(_text(json['status'] ?? json['taskStatus'])),
    assigneeId: _text(
      json['assigneeId'] ?? json['assignee_id'] ?? json['assignedTo'],
    ),
    assigneeName: _text(json['assigneeName'] ?? json['assignee_name']),
    priority: _text(json['priority'] ?? json['priorityCode'], 'Trung bình'),
    dueDate: _date(json['dueDate'] ?? json['due_date'] ?? json['deadline']),
    outputType: _text(json['outputType'] ?? json['output_type'], 'docs'),
    outputRequired: json['outputRequired'] != false,
    outputLink: _text(json['outputLink'] ?? json['output_link']),
    reviewComment: _text(json['reviewComment'] ?? json['review_comment']),
    deadlineRequest: json['deadlineRequest'] is Map
        ? DeadlineRequest.fromJson(
            Map<String, dynamic>.from(json['deadlineRequest'] as Map),
          )
        : null,
    createdAt: _date(json['createdAt']),
    updatedAt: _date(json['updatedAt']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'title': title,
    'description': description,
    'status': status,
    'assigneeId': assigneeId,
    'assigneeName': assigneeName,
    'priority': priority,
    'dueDate': dueDate?.toIso8601String(),
    'outputType': outputType,
    'outputRequired': outputRequired,
    'outputLink': outputLink,
    'reviewComment': reviewComment,
    if (deadlineRequest != null) 'deadlineRequest': deadlineRequest!.toJson(),
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };
}

@immutable
class DeadlineRequest {
  const DeadlineRequest({
    required this.requestedDueDate,
    required this.requestedBy,
    required this.reason,
    required this.status,
    this.createdAt,
  });

  final DateTime requestedDueDate;
  final String requestedBy;
  final String reason;
  final String status;
  final DateTime? createdAt;

  factory DeadlineRequest.fromJson(Map<String, dynamic> json) =>
      DeadlineRequest(
        requestedDueDate: _date(json['requestedDueDate']) ?? DateTime.now(),
        requestedBy: _text(json['requestedBy']),
        reason: _text(json['reason']),
        status: _text(json['status'], 'pending'),
        createdAt: _date(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
    'requestedDueDate': requestedDueDate.toIso8601String(),
    'requestedBy': requestedBy,
    'reason': reason,
    'status': status,
    'createdAt': createdAt?.toIso8601String(),
  };
}

@immutable
class MemberTaskStats {
  const MemberTaskStats({
    required this.userId,
    required this.name,
    required this.role,
    required this.assigned,
    required this.completed,
    this.avatarUrl = '',
  });

  final String userId;
  final String name;
  final String role;
  final String avatarUrl;
  final int assigned;
  final int completed;

  int get completionPercent =>
      assigned == 0 ? 0 : (completed * 100 / assigned).round();
}

String _normalizeStatus(String value) {
  switch (value
      .toLowerCase()
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .trim()) {
    case 'todo':
    case 'to do':
    case 'pending':
    case 'cần làm':
      return 'Cần làm';
    case 'doing':
    case 'in progress':
    case 'đang làm':
      return 'Đang làm';
    case 'submitted':
    case 'waiting review':
    case 'pending review':
    case 'chờ duyệt':
      return 'Chờ duyệt';
    case 'revision':
    case 'needs changes':
    case 'cần sửa':
      return 'Cần sửa';
    case 'done':
    case 'completed':
    case 'hoàn thành':
      return 'Hoàn thành';
    default:
      return value.isEmpty ? 'Cần làm' : value;
  }
}

String _text(dynamic value, [String fallback = '']) =>
    value is String && value.trim().isNotEmpty ? value.trim() : fallback;

DateTime? _date(dynamic value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is Map) {
    final seconds = value['_seconds'] ?? value['seconds'];
    if (seconds is num) {
      return DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);
    }
  }
  return null;
}
