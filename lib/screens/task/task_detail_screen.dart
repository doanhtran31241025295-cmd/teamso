import 'package:flutter/material.dart';

import '../../controllers/projects_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/task_model.dart';

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({
    super.key,
    required this.projects,
    required this.projectId,
    required this.userId,
    this.task,
  });

  final ProjectsController projects;
  final String projectId;
  final String userId;
  final TaskModel? task;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _outputLinkController;
  TaskModel? _task;
  String? _assigneeId;
  String _priority = 'medium';
  String _outputType = 'docs';
  bool _outputRequired = true;
  DateTime? _dueDate;
  bool _busy = false;

  bool get _isCreating => widget.task == null;
  bool get _isLeader =>
      widget.projects.roleInProject(widget.projectId) == 'Leader';
  bool get _isAssignee => _task?.assigneeId == widget.userId;
  bool get _hasPendingDeadline => _task?.deadlineRequest?.status == 'pending';
  List<Map<String, dynamic>> get _members =>
      widget.projects.membersForProject(widget.projectId);

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    _titleController = TextEditingController(text: _task?.title ?? '');
    _descriptionController = TextEditingController(
      text: _task?.description ?? '',
    );
    _outputLinkController = TextEditingController(
      text: _task?.outputLink ?? '',
    );
    _assigneeId = _task?.assigneeId;
    _priority = _priorityCode(_task?.priority ?? 'medium');
    _outputType = _task?.outputType ?? 'docs';
    _outputRequired = _task?.outputRequired ?? true;
    _dueDate = _task?.dueDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _outputLinkController.dispose();
    super.dispose();
  }

  String _priorityCode(String value) => switch (value.toLowerCase()) {
    'high' || 'cao' => 'high',
    'low' || 'thấp' => 'low',
    _ => 'medium',
  };

  String _memberId(Map<String, dynamic> member) =>
      (member['id'] ?? member['userId'] ?? member['user_id'] ?? '').toString();

  String _memberName(Map<String, dynamic> member) =>
      (member['displayName'] ??
              member['name'] ??
              member['username'] ??
              'Thành viên')
          .toString();

  Future<void> _selectDate({bool extension = false}) async {
    final minimum = extension && _task?.dueDate != null
        ? _task!.dueDate!.toLocal().add(const Duration(days: 1))
        : DateTime.now();
    final initial = _dueDate?.toLocal().isBefore(minimum) == true
        ? minimum
        : _dueDate?.toLocal() ?? minimum;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: extension ? minimum : DateTime(2000),
      lastDate: DateTime(2100),
      helpText: extension ? 'Chọn deadline đề xuất' : 'Chọn deadline',
    );
    if (selected == null || !mounted) return;
    setState(
      () => _dueDate = DateTime(
        selected.year,
        selected.month,
        selected.day,
        23,
        59,
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final fields = <String, dynamic>{
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim(),
      'assigneeId': _assigneeId,
      'priority': _priority,
      'dueDate': _dueDate?.toUtc().toIso8601String(),
      'outputType': _outputType,
      'outputRequired': _outputType != 'none' && _outputRequired,
    };
    await _run(() async {
      if (_isCreating) {
        await widget.projects.createTask(widget.projectId, fields);
      } else {
        await widget.projects.updateTask(_task!, fields);
      }
      if (mounted) Navigator.of(context).pop(true);
    }, _isCreating ? 'Đã tạo công việc.' : 'Đã cập nhật công việc.');
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && Navigator.of(context).canPop()) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshTask() async {
    final id = _task?.id;
    if (id == null) return;
    final tasks = widget.projects.tasksForProject(widget.projectId);
    final matches = tasks.where((task) => task.id == id);
    if (matches.isNotEmpty && mounted) setState(() => _task = matches.first);
  }

  Future<void> _startTask() async {
    final task = _task;
    if (task == null) return;
    await _run(() async {
      await widget.projects.startTask(task);
      await _refreshTask();
    }, 'Đã chuyển sang Đang làm.');
  }

  Future<void> _submitTask() async {
    final task = _task;
    if (task == null) return;
    if (task.outputType != 'none' &&
        task.outputRequired &&
        _outputLinkController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập đường dẫn kết quả.')),
      );
      return;
    }
    await _run(() async {
      await widget.projects.submitTask(task, _outputLinkController.text.trim());
      await _refreshTask();
    }, 'Đã gửi kết quả.');
  }

  Future<void> _reviewTask({required bool approve}) async {
    final task = _task;
    if (task == null) return;
    await _run(() async {
      if (approve) {
        await widget.projects.approveTask(task);
      } else {
        await widget.projects.requestChanges(
          task,
          'Vui lòng cập nhật công việc.',
        );
      }
      await _refreshTask();
    }, approve ? 'Đã duyệt công việc.' : 'Đã yêu cầu chỉnh sửa.');
  }

  Future<void> _requestDeadline() async {
    final task = _task;
    if (task == null) return;
    var reasonDraft = '';
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xin lùi deadline'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              onPressed: () => _selectDate(extension: true),
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(
                _dueDate == null ? 'Chọn ngày đề xuất' : _dateLabel(_dueDate),
              ),
            ),
            TextField(
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              onChanged: (value) => reasonDraft = value,
              decoration: const InputDecoration(
                labelText: 'Lý do',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, reasonDraft.trim()),
            child: const Text('Gửi yêu cầu'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty || _dueDate == null || !mounted) {
      return;
    }
    await _run(() async {
      await widget.projects.requestDeadlineExtension(task, _dueDate!, reason);
      await _refreshTask();
    }, 'Đã gửi yêu cầu lùi deadline.');
  }

  Future<void> _reviewDeadline(bool approve) async {
    final task = _task;
    if (task == null) return;
    await _run(() async {
      await widget.projects.reviewDeadlineRequest(task, approve: approve);
      await _refreshTask();
    }, approve ? 'Đã duyệt deadline mới.' : 'Đã từ chối yêu cầu.');
  }

  String _dateLabel(DateTime? date) {
    if (date == null) return 'Chưa đặt deadline';
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  Color _statusColor(String status) => switch (status) {
    'Hoàn thành' => AppColors.green,
    'Đang làm' => const Color(0xFF4285F4),
    'Chờ duyệt' => const Color(0xFFDB9B18),
    'Cần sửa' => AppColors.pink,
    _ => AppColors.textSecondary,
  };

  Widget _buildEditableFields() => Form(
    key: _formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'Tên công việc',
            border: OutlineInputBorder(),
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Vui lòng nhập tên công việc.'
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _descriptionController,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Mô tả',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _assigneeId,
          decoration: const InputDecoration(
            labelText: 'Người được giao',
            border: OutlineInputBorder(),
          ),
          items: _members
              .map(
                (member) => DropdownMenuItem(
                  value: _memberId(member),
                  child: Text(
                    _memberName(member),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .where((item) => item.value?.isNotEmpty == true)
              .toList(),
          onChanged: (value) => setState(() => _assigneeId = value),
          validator: (value) =>
              value == null ? 'Chọn thành viên được giao.' : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _priority,
          decoration: const InputDecoration(
            labelText: 'Ưu tiên',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'high', child: Text('Cao')),
            DropdownMenuItem(value: 'medium', child: Text('Trung bình')),
            DropdownMenuItem(value: 'low', child: Text('Thấp')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _priority = value);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _outputType,
          decoration: const InputDecoration(
            labelText: 'Loại đầu ra',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'docs', child: Text('Tài liệu')),
            DropdownMenuItem(value: 'drive', child: Text('Google Drive')),
            DropdownMenuItem(value: 'sheet', child: Text('Bảng tính')),
            DropdownMenuItem(value: 'file', child: Text('Tệp')),
            DropdownMenuItem(value: 'none', child: Text('Không yêu cầu')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _outputType = value);
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Bắt buộc nộp kết quả'),
          value: _outputType != 'none' && _outputRequired,
          onChanged: _outputType == 'none'
              ? null
              : (value) => setState(() => _outputRequired = value),
        ),
        OutlinedButton.icon(
          onPressed: () => _selectDate(),
          icon: const Icon(Icons.event_outlined),
          label: Text(_dueDate == null ? 'Đặt deadline' : _dateLabel(_dueDate)),
        ),
        if (_dueDate != null)
          TextButton(
            onPressed: () => setState(() => _dueDate = null),
            child: const Text('Xóa deadline'),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: Icon(_isCreating ? Icons.add_task : Icons.save_outlined),
          label: Text(_isCreating ? 'Tạo task' : 'Lưu thay đổi'),
        ),
      ],
    ),
  );

  Widget _buildDetails() {
    final task = _task!;
    final deadline = task.deadlineRequest;
    final isAssignee = _isAssignee || _isLeader;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                task.title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Chip(
              label: Text(task.status),
              backgroundColor: _statusColor(task.status)
                  .withValues(alpha: 0.13),
              labelStyle: TextStyle(
                color: _statusColor(task.status),
                fontWeight: FontWeight.w700,
              ),
              side: BorderSide.none,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          task.description.isEmpty ? 'Chưa có mô tả.' : task.description,
          style: const TextStyle(color: AppColors.textSecondary, height: 1.45),
        ),
        const SizedBox(height: 18),
        _detailRow(
          Icons.person_outline,
          'Người thực hiện',
          widget.projects.assigneeName(task),
        ),
        _detailRow(Icons.flag_outlined, 'Ưu tiên', task.priorityLabel),
        _detailRow(
          Icons.calendar_today_outlined,
          'Deadline',
          _dateLabel(task.dueDate),
        ),
        if (task.outputLink.isNotEmpty)
          _detailRow(Icons.link, 'Kết quả', task.outputLink),
        if (task.reviewComment.isNotEmpty)
          _detailRow(
            Icons.rate_review_outlined,
            'Nhận xét',
            task.reviewComment,
          ),
        if (deadline != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Yêu cầu lùi hạn: ${_dateLabel(deadline.requestedDueDate)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(deadline.reason),
                Text(
                  'Trạng thái: ${deadline.status == 'pending'
                      ? 'Chờ duyệt'
                      : deadline.status == 'approved'
                      ? 'Đã duyệt'
                      : 'Đã từ chối'}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                if (_isLeader && deadline.status == 'pending') ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _busy ? null : () => _reviewDeadline(true),
                        child: const Text('Duyệt ngày mới'),
                      ),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _reviewDeadline(false),
                        child: const Text('Từ chối'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
        if (task.outputType != 'none' &&
            isAssignee &&
            task.status != 'Hoàn thành') ...[
          const SizedBox(height: 18),
          TextField(
            controller: _outputLinkController,
            decoration: const InputDecoration(
              labelText: 'Đường dẫn kết quả',
              hintText: 'https://...',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (_isLeader && task.status == 'Chờ duyệt')
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _reviewTask(approve: true),
                icon: const Icon(Icons.check),
                label: const Text('Duyệt task'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _reviewTask(approve: false),
                icon: const Icon(Icons.edit_note),
                label: const Text('Yêu cầu sửa'),
              ),
            ],
          )
        else if (isAssignee && task.status != 'Hoàn thành')
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (task.status == 'Cần làm' || task.status == 'Cần sửa')
                OutlinedButton.icon(
                  onPressed: _busy ? null : _startTask,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Bắt đầu'),
                ),
              if (task.status == 'Đang làm' || task.status == 'Cần sửa')
                FilledButton.icon(
                  onPressed: _busy ? null : _submitTask,
                  icon: const Icon(Icons.send_outlined),
                  label: Text(_isLeader ? 'Hoàn thành' : 'Gửi duyệt'),
                ),
              if (!_isLeader && !_hasPendingDeadline)
                TextButton.icon(
                  onPressed: _busy ? null : _requestDeadline,
                  icon: const Icon(Icons.event_busy_outlined),
                  label: const Text('Xin lùi deadline'),
                ),
            ],
          ),
        if (_hasPendingDeadline && !_isLeader)
          const Text(
            'Yêu cầu lùi deadline đang chờ Leader duyệt.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
      ],
    );
  }

  Widget _detailRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: Text(value, maxLines: 3, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.pageBackground,
    appBar: AppBar(
      title: Text(_isCreating ? 'Tạo task' : 'Chi tiết công việc'),
      actions: [
        if (!_isCreating && _isLeader)
          IconButton(
            tooltip: 'Chỉnh sửa task',
            onPressed: () => setState(() => _showEditForm = !_showEditForm),
            icon: Icon(_showEditForm ? Icons.close : Icons.edit_outlined),
          ),
      ],
    ),
    body: _busy && _task == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
            children: [
              if (_isCreating || _showEditForm)
                _buildEditableFields()
              else
                _buildDetails(),
            ],
          ),
  );

  bool _showEditForm = false;
}
