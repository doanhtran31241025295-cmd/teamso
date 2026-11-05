import '../../core/theme/accent_surface.dart';

import 'package:flutter/material.dart';

import '../../models/task_model.dart';

const Color _taskBackground = Colors.white;
const Color _taskTextPrimary = Color(0xFF282638);
const Color _taskTextSecondary = Color(0xFF858397);
const Color _taskPurple = Color(0xFF867CB3);
const Color _taskGreen = Color(0xFF439751);
const Color _taskPink = Color(0xFFF472B6);
const Color _taskYellow = Color(0xFFFACC15);
const Color _taskRed = Color(0xFFB94B54);

class TaskDetailScreen extends StatelessWidget {
  const TaskDetailScreen({
    super.key,
    required this.task,
    this.projectName,
    this.assigneeName,
    this.onEdit,
    this.onSubmit,
    this.onApprove,
    this.onRequestChanges,
    this.canEdit = false,
    this.canReview = false,
  });

  final TaskModel task;
  final String? projectName;
  final String? assigneeName;
  final VoidCallback? onEdit;
  final VoidCallback? onSubmit;
  final VoidCallback? onApprove;
  final VoidCallback? onRequestChanges;
  final bool canEdit;
  final bool canReview;

  Color _statusColor(String status) {
    switch (status) {
      case 'Hoàn thành':
        return _taskGreen;
      case 'Đang làm':
        return const Color(0xFF4285F4);
      case 'Chờ duyệt':
        return const Color(0xFFDB9B18);
      case 'Cần sửa':
        return _taskPink;
      case 'Cần làm':
      default:
        return _taskTextSecondary;
    }
  }

  String _formatDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Chưa có hạn';
    }

    final date = DateTime.tryParse(value);
    if (date == null) {
      return 'Chưa có hạn';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: _taskTextSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _taskTextSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: _taskTextPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(task.status);
    final assignee = assigneeName ?? 'Chưa giao';
    final project = projectName ?? 'Dự án';

    return Scaffold(
      backgroundColor: _taskBackground,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Chi tiết công việc'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: AccentBoxDecoration(
                  accent: _taskPurple,
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFECEBF2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            task.title.isEmpty ? 'Công việc' : task.title,
                            style: const TextStyle(
                              color: _taskTextPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            task.status,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: _taskPurple.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            project,
                            style: const TextStyle(
                              color: _taskPurple,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (task.priority.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: task.priority == 'Cao'
                                  ? _taskRed.withValues(alpha: 0.12)
                                  : task.priority == 'Thấp'
                                  ? _taskGreen.withValues(alpha: 0.12)
                                  : _taskYellow.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              task.priority,
                              style: TextStyle(
                                color: task.priority == 'Cao'
                                    ? _taskRed
                                    : task.priority == 'Thấp'
                                    ? _taskGreen
                                    : const Color(0xFFB27A00),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _infoRow(
                      Icons.person_outline_rounded,
                      'Người thực hiện',
                      assignee,
                    ),
                    _infoRow(
                      Icons.calendar_today_outlined,
                      'Hạn hoàn thành',
                      _formatDate(task.dueDate),
                    ),
                    if (task.outputLink != null &&
                        task.outputLink!.trim().isNotEmpty)
                      _infoRow(Icons.link_rounded, 'Kết quả', task.outputLink!),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: AccentBoxDecoration(
                  accent: _taskPurple,
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFECEBF2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mô tả công việc',
                      style: TextStyle(
                        color: _taskTextPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      task.description.trim().isEmpty
                          ? 'Không có mô tả chi tiết.'
                          : task.description,
                      style: const TextStyle(
                        color: _taskTextSecondary,
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              if (task.reviewComment != null &&
                  task.reviewComment!.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: AccentBoxDecoration(
                    accent: _taskPink,
                    color: _taskPink.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _taskPink.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Nhận xét từ trưởng nhóm',
                        style: TextStyle(
                          color: _taskRed,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        task.reviewComment!,
                        style: const TextStyle(
                          color: _taskTextPrimary,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (onEdit != null ||
                  onSubmit != null ||
                  onApprove != null ||
                  onRequestChanges != null) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (onEdit != null && canEdit)
                      FilledButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        label: const Text('Sửa'),
                      ),
                    if (onSubmit != null)
                      FilledButton.icon(
                        onPressed: onSubmit,
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: const Text('Gửi kết quả'),
                      ),
                    if (onApprove != null && canReview)
                      FilledButton.icon(
                        onPressed: onApprove,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Duyệt'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _taskGreen,
                        ),
                      ),
                    if (onRequestChanges != null && canReview)
                      OutlinedButton.icon(
                        onPressed: onRequestChanges,
                        icon: const Icon(Icons.edit_note_rounded, size: 18),
                        label: const Text('Yêu cầu sửa'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
