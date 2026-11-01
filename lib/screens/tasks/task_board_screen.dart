import 'package:flutter/material.dart';

import '../../controllers/projects_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/task_model.dart';
import '../../widgets/project_form_dialog.dart';
import '../task/task_detail_screen.dart';

class TaskBoardScreen extends StatefulWidget {
  const TaskBoardScreen({super.key, required this.projects});
  final ProjectsController projects;

  @override
  State<TaskBoardScreen> createState() => _TaskBoardScreenState();
}

class _TaskBoardScreenState extends State<TaskBoardScreen>
    with SingleTickerProviderStateMixin {
  ProjectsController get _data => widget.projects;
  bool _busy = false;
  bool _isKanban = false;
  String? _selectedProjectId;

  String get _activeProjectId {
    final selected = _selectedProjectId;
    if (selected != null && _data.projectById(selected) != null) {
      return selected;
    }
    return _data.projects.isEmpty ? '' : _data.projectId(_data.projects.first);
  }

  Map<String, dynamic>? get _activeProject =>
      _data.projectById(_activeProjectId);

  late final TabController _tabController;

  static const List<String> _statuses = [
    'Cần làm',
    'Đang làm',
    'Cần sửa',
    'Chờ duyệt',
    'Hoàn thành',
  ];

  @override
  void initState() {
    super.initState();

    // Mở mặc định ở tab Đang làm.
    _tabController = TabController(
      length: _statuses.length,
      initialIndex: 1,
      vsync: this,
    );

    _tabController.addListener(_handleTabChange);
  }

  void _handleTabChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  List<TaskModel> _tasksForStatus(String status) {
    final result = _data
        .tasksForProject(_activeProjectId)
        .where((task) => _data.taskStatus(task) == status)
        .toList();

    result.sort((a, b) {
      // Ưu tiên cao xếp trước; không hiện nhãn "Ưu tiên 1".
      final priorityA = _priorityRank(a.priorityLabel);
      final priorityB = _priorityRank(b.priorityLabel);

      if (priorityA != priorityB) {
        return priorityA.compareTo(priorityB);
      }

      final dateA = a.dueDate;
      final dateB = b.dueDate;

      if (dateA == null && dateB == null) {
        return 0;
      }
      if (dateA == null) {
        return 1;
      }
      if (dateB == null) {
        return -1;
      }

      return dateA.compareTo(dateB);
    });

    return result;
  }

  int _priorityRank(String? priority) {
    switch (priority) {
      case 'Cao':
        return 0;
      case 'Trung bình':
        return 1;
      case 'Thấp':
        return 2;
      default:
        return 3;
    }
  }

  int _countForStatus(String status) {
    return _data
        .tasksForProject(_activeProjectId)
        .where((task) => _data.taskStatus(task) == status)
        .length;
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) {
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

  Color _statusColor(String status) {
    switch (status) {
      case 'Hoàn thành':
        return AppColors.green;
      case 'Đang làm':
        return const Color(0xFF4285F4);
      case 'Chờ duyệt':
      case 'Cần bạn duyệt':
        return const Color(0xFFDB9B18);
      case 'Cần sửa':
        return AppColors.pink;
      default:
        return AppColors.textSecondary;
    }
  }

  Color _projectColor(Map<String, dynamic>? project) {
    final color = project?['color'];

    if (color is Color) {
      return color;
    }
    if (color is int) {
      return Color(color);
    }

    switch (project?['tag']?.toString()) {
      case 'Mobile':
        return AppColors.green;
      case 'Marketing':
        return AppColors.pink;
      case 'Research':
        return const Color(0xFFE1B32C);
      default:
        return AppColors.purple;
    }
  }

  /// Chạy một thao tác API, chặn bấm trùng và báo kết quả bằng snackbar.
  Future<void> _run(
    Future<void> Function() action,
    String successMessage,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _showMessage(successMessage);
    } catch (e) {
      _showMessage(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startTask(TaskModel task) =>
      _run(() => _data.startTask(task), 'Đã chuyển công việc sang Đang làm.');

  Future<void> _submitTask(TaskModel task) async {
    var outputLink = task.outputLink;

    final outputType = task.outputType;
    final outputRequired = task.outputRequired;
    final isLeader = _data.roleInProject(task.projectId) == 'Leader';

    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Gửi kết quả công việc'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(task.title),
              if (outputType != 'none') ...[
                const SizedBox(height: 12),
                Text(
                  outputRequired
                      ? 'Công việc này yêu cầu đầu ra.'
                      : 'Bạn có thể bổ sung đường dẫn kết quả.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  minLines: 1,
                  maxLines: 3,
                  onChanged: (value) => outputLink = value,
                  decoration: const InputDecoration(
                    labelText: 'Đường dẫn kết quả',
                    hintText: 'https://...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                final link = outputLink.trim();

                if (outputType != 'none' && outputRequired && link.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Vui lòng nhập đường dẫn kết quả.'),
                    ),
                  );
                  return;
                }

                Navigator.of(dialogContext).pop(link);
              },
              child: const Text('Gửi'),
            ),
          ],
        );
      },
    );

    if (result == null) {
      return;
    }

    if (!mounted) return;
    await _run(
      () => _data.submitTask(task, result),
      isLeader
          ? 'Đã hoàn thành công việc.'
          : 'Đã gửi công việc cho Leader duyệt.',
    );
  }

  Future<void> _reviewTask(TaskModel task, {required bool approve}) async {
    if (approve) {
      await _run(() => _data.approveTask(task), 'Đã duyệt công việc.');
      return;
    }

    var commentDraft = '';

    final comment = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Yêu cầu chỉnh sửa'),
          content: TextField(
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            onChanged: (value) => commentDraft = value,
            decoration: const InputDecoration(
              labelText: 'Nhận xét',
              hintText: 'Nêu rõ phần cần chỉnh sửa',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(commentDraft.trim()),
              child: const Text('Gửi yêu cầu'),
            ),
          ],
        );
      },
    );

    if (comment == null || !mounted) {
      return;
    }

    await _run(
      () => _data.requestChanges(task, comment),
      'Đã yêu cầu chỉnh sửa công việc.',
    );
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildStatusTabs() {
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      labelColor: AppColors.darkPurple,
      unselectedLabelColor: AppColors.textSecondary,
      indicatorColor: AppColors.purple,
      indicatorWeight: 3,
      dividerColor: const Color(0xFFECEBF2),
      tabs: _statuses.map((status) {
        final count = _countForStatus(status);
        return Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(status),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _tabController.index == _statuses.indexOf(status)
                      ? AppColors.purple.withValues(alpha: 0.15)
                      : const Color(0xFFF0EFF5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTaskList(String status) {
    final tasks = _tasksForStatus(status);

    if (tasks.isEmpty) {
      return RefreshIndicator(
        onRefresh: _data.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 110),
            Icon(Icons.task_alt_rounded, size: 52, color: Color(0xFFD0CEDC)),
            SizedBox(height: 12),
            Center(
              child: Text(
                'Không có công việc trong mục này',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _data.load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: tasks.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return _buildTaskCard(tasks[index], status);
        },
      ),
    );
  }

  Widget _buildTaskCard(TaskModel task, String currentTab) {
    final projectId = task.projectId;
    final project = _data.projectById(projectId);
    final projectColor = _projectColor(project);
    final status = _data.taskStatus(task);
    final statusColor = _statusColor(status);
    final isMyTask = _data.assigneeId(task) == _data.userId;
    final isLeader = _data.roleInProject(projectId) == 'Leader';
    final isReviewTab = currentTab == 'Chờ duyệt';

    final canStart =
        !_busy && isMyTask && (status == 'Cần làm' || status == 'Cần sửa');

    final canSubmit =
        !_busy && isMyTask && (status == 'Đang làm' || status == 'Cần sửa');

    final canReview = !_busy && isLeader && status == 'Chờ duyệt';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFECEBF2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Xem chi tiết task',
                onPressed: () => _openTask(task),
                icon: const Icon(Icons.open_in_new_outlined, size: 19),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Nhãn dự án
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: projectColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  project?['tag']?.toString() ??
                      project?['name']?.toString() ??
                      'Dự án',
                  style: TextStyle(
                    color: projectColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (task.priorityLabel == 'Cao')
                const Text(
                  'Cao',
                  style: TextStyle(
                    color: Color(0xFFB94B54),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              const Icon(
                Icons.person_outline_rounded,
                size: 17,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  _data.assigneeName(task),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              const Icon(
                Icons.calendar_today_outlined,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                _formatDate(task.dueDate?.toIso8601String()),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),

          if (task.reviewComment.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.pink.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Nhận xét: ${task.reviewComment}',
                style: const TextStyle(color: Color(0xFFB94B83), fontSize: 12),
              ),
            ),
          ],

          if (task.outputLink.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.link_rounded,
                  color: AppColors.purple,
                  size: 17,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    task.outputLink,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.darkPurple,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],

          if (canStart || canSubmit || (canReview && isReviewTab)) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canStart && status == 'Cần làm')
                  OutlinedButton.icon(
                    onPressed: () => _startTask(task),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Bắt đầu'),
                  ),
                if (canSubmit)
                  FilledButton.icon(
                    onPressed: () => _submitTask(task),
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Gửi kết quả'),
                  ),
                if (canReview && isReviewTab) ...[
                  FilledButton.icon(
                    onPressed: () => _reviewTask(task, approve: true),
                    icon: const Icon(Icons.check_rounded, size: 17),
                    label: const Text('Duyệt'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.green,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _reviewTask(task, approve: false),
                    icon: const Icon(Icons.edit_note_rounded, size: 17),
                    label: const Text('Yêu cầu sửa'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openTask(TaskModel task) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => TaskDetailScreen(
        projects: _data,
        projectId: task.projectId,
        userId: _data.userId,
        task: task,
      ),
    ),
  );

  Future<void> _createTask() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => TaskDetailScreen(
        projects: _data,
        projectId: _activeProjectId,
        userId: _data.userId,
      ),
    ),
  );

  Future<void> _createProject() async {
    final result = await showProjectFormDialog(context);
    if (result == null || !mounted) return;
    try {
      final id = await _data.createProject(result);
      if (mounted) {
        setState(() => _selectedProjectId = id);
        _showMessage('Đã tạo dự án.');
      }
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  Widget _memberAvatar(Map<String, dynamic> member) {
    final name =
        (member['displayName'] ?? member['name'] ?? member['username'] ?? 'T')
            .toString();
    final imageUrl = (member['avatarUrl'] ?? member['photoUrl'] ?? '')
        .toString();
    final fallback = CircleAvatar(
      backgroundColor: AppColors.softPurple,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: const TextStyle(
          color: AppColors.darkPurple,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    if (imageUrl.isEmpty) return fallback;
    return CircleAvatar(
      backgroundColor: AppColors.softPurple,
      child: ClipOval(
        child: Image.network(
          imageUrl,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        ),
      ),
    );
  }

  void _showProjectInfo() {
    final project = _activeProject;
    if (project == null) return;
    final members = _data.membersForProject(_activeProjectId);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Text(
                (project['name'] ?? project['title'] ?? 'Dự án').toString(),
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                (project['description'] ?? '').toString().trim().isEmpty
                    ? 'Chưa có mô tả dự án.'
                    : (project['description']).toString(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Quy tắc nhóm',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                (project['rules'] ?? '').toString().trim().isEmpty
                    ? 'Chưa có quy tắc nhóm.'
                    : (project['rules']).toString(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Thành viên (${members.length})',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              for (final member in members)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _memberAvatar(member),
                  title: Text(
                    (member['displayName'] ??
                            member['name'] ??
                            member['username'] ??
                            'Thành viên')
                        .toString(),
                  ),
                  subtitle: Text(
                    (member['role'] ??
                            (_data.roleInProject(_activeProjectId) == 'Leader'
                                ? 'Leader'
                                : 'Member'))
                        .toString(),
                  ),
                ),
              if (_data.roleInProject(_activeProjectId) == 'Leader')
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showAddMember();
                  },
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Thêm thành viên bằng username'),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showContributions();
                },
                icon: const Icon(Icons.leaderboard_outlined),
                label: const Text('Bảng điểm đóng góp'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddMember() async {
    var usernameDraft = '';
    final username = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Thêm thành viên'),
        content: TextField(
          autofocus: true,
          textCapitalization: TextCapitalization.none,
          onChanged: (value) => usernameDraft = value,
          decoration: const InputDecoration(
            labelText: 'Username',
            hintText: 'vd: nguyenvana',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, usernameDraft.trim()),
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
    if (username == null || username.isEmpty || !mounted) return;
    try {
      await _data.addProjectMember(_activeProjectId, username);
      _showMessage('Đã thêm thành viên vào dự án.');
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  void _showContributions() {
    final stats = _data.contributionStats(_activeProjectId);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  'Đóng góp thành viên',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Tỷ lệ hoàn thành = task hoàn thành / tổng task được giao.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: stats.isEmpty
                    ? const Center(child: Text('Chưa có dữ liệu thành viên.'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                        itemCount: stats.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final member = stats[index];
                          final map =
                              _data
                                  .membersForProject(_activeProjectId)
                                  .where(
                                    (item) =>
                                        (item['id'] ??
                                                item['userId'] ??
                                                item['user_id'])
                                            .toString() ==
                                        member.userId,
                                  )
                                  .firstOrNull ??
                              <String, dynamic>{
                                'displayName': member.name,
                                'avatarUrl': member.avatarUrl,
                              };
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: _memberAvatar(map),
                            title: Text(member.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${member.role} · ${member.completed}/${member.assigned} task hoàn thành',
                                ),
                                const SizedBox(height: 6),
                                LinearProgressIndicator(
                                  value: member.completionPercent / 100,
                                  minHeight: 5,
                                  backgroundColor: AppColors.border,
                                  color: AppColors.green,
                                ),
                              ],
                            ),
                            trailing: Text(
                              '${member.completionPercent}%',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.darkPurple,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProjectHeader() {
    final project = _activeProject;
    if (project == null) return const SizedBox.shrink();
    final progress = _data.progressOf(_activeProjectId);
    final tasks = _data.tasksForProject(_activeProjectId);
    final done = tasks.where((task) => task.isDone).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _activeProjectId,
                    isExpanded: true,
                    items: _data.projects.map((item) {
                      final id = _data.projectId(item);
                      return DropdownMenuItem(
                        value: id,
                        child: Text(
                          (item['name'] ?? item['title'] ?? 'Dự án').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (id) {
                      if (id != null) setState(() => _selectedProjectId = id);
                    },
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Thông tin dự án và thành viên',
                onPressed: _showProjectInfo,
                icon: const Icon(Icons.info_outline),
              ),
              IconButton(
                tooltip: 'Bảng điểm đóng góp',
                onPressed: _showContributions,
                icon: const Icon(Icons.leaderboard_outlined),
              ),
            ],
          ),
          if ((project['description'] ?? '').toString().trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                project['description'].toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress / 100,
                    minHeight: 7,
                    backgroundColor: AppColors.border,
                    color: AppColors.green,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$progress%',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.darkPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '$done/${tasks.length} công việc hoàn thành · ${_data.memberCount(project)} thành viên',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewControls() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Row(
      children: [
        Expanded(
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.view_list_outlined),
                label: Text('Danh sách'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.view_kanban_outlined),
                label: Text('Kanban'),
              ),
            ],
            selected: {_isKanban},
            onSelectionChanged: (value) =>
                setState(() => _isKanban = value.first),
            showSelectedIcon: false,
          ),
        ),
        const SizedBox(width: 8),
        if (_data.roleInProject(_activeProjectId) == 'Leader')
          IconButton.filled(
            tooltip: 'Tạo task',
            onPressed: _createTask,
            icon: const Icon(Icons.add_task),
          ),
      ],
    ),
  );

  Widget _buildKanban() => RefreshIndicator(
    onRefresh: _data.load,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      children: _statuses.map((status) {
        final tasks = _tasksForStatus(status);
        return Container(
          width: 280,
          height: double.infinity,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        status,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      '${tasks.length}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: tasks.isEmpty
                    ? const Center(
                        child: Text(
                          'Chưa có task',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(10),
                        itemCount: tasks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _buildTaskCard(tasks[index], status),
                      ),
              ),
            ],
          ),
        );
      }).toList(),
    ),
  );

  Widget _buildBody() {
    if (!_data.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_data.error != null && _data.projects.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 44),
              const SizedBox(height: 12),
              Text(_data.error!, textAlign: TextAlign.center),
              TextButton.icon(
                onPressed: _data.load,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }
    if (_data.projects.isEmpty) {
      return RefreshIndicator(
        onRefresh: _data.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: 110),
            const Icon(
              Icons.folder_open_rounded,
              size: 52,
              color: Color(0xFFD0CEDC),
            ),
            const SizedBox(height: 12),
            const Center(child: Text('Chưa có dự án')),
            const SizedBox(height: 4),
            const Center(
              child: Text(
                'Tạo dự án hoặc tham gia nhóm để quản lý task.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: FilledButton.icon(
                onPressed: _createProject,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Tạo dự án'),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        _buildProjectHeader(),
        _buildViewControls(),
        if (!_isKanban) _buildStatusTabs(),
        Expanded(
          child: _isKanban
              ? _buildKanban()
              : TabBarView(
                  controller: _tabController,
                  children: _statuses.map(_buildTaskList).toList(),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _data,
    builder: (context, _) =>
        Scaffold(backgroundColor: AppColors.pageBackground, body: _buildBody()),
  );
}
