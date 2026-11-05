import 'dart:async';

import '../../core/theme/accent_surface.dart';
import '../home/project_detail_screen.dart';

import 'package:flutter/material.dart';

import '../../widgets/prompt_dialog.dart';
import 'task_calendar.dart';
import 'task_store.dart';
import '../../core/theme/app_colors.dart';

const Color _textPrimary = Color(0xFF282638);
const Color _textSecondary = Color(0xFF858397);

class TaskBoardScreen extends StatefulWidget {
  const TaskBoardScreen({super.key});

  @override
  State<TaskBoardScreen> createState() => TaskBoardScreenState();
}

class TaskBoardScreenState extends State<TaskBoardScreen> {
  String? _notificationProject, _notificationTask;
  Timer? _notificationTimeout;

  @override
  void initState() {
    super.initState();
    _store.addListener(_openPendingNotification);
  }

  void openFromNotification(String projectId, String taskId) {
    _notificationTimeout?.cancel();
    _notificationProject = projectId;
    _notificationTask = taskId;
    setState(() {
      _viewMode = 0;
      _focusedStatus = null;
    });
    _notificationTimeout = Timer(const Duration(seconds: 15), () {
      if (!mounted || _notificationTask == null) return;
      _notificationTask = null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chưa tải được công việc. Vui lòng thử lại thông báo.'),
        ),
      );
    });
    _openPendingNotification();
  }

  void _openPendingNotification() {
    if (!mounted || _notificationTask == null) return;
    final task = _store.tasks
        .where(
          (t) =>
              t['id'] == _notificationTask &&
              t['projectId'] == _notificationProject,
        )
        .firstOrNull;
    if (task == null) return;
    _notificationTask = null;
    _notificationTimeout?.cancel();
    final status = task['status']?.toString() ?? 'Cần làm';
    final review =
        status == 'Chờ duyệt' &&
        _store.roleInProject(task['projectId'].toString()) == 'Leader';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openTask(task, review ? 'Cần bạn duyệt' : status);
    });
  }

  final TaskStore _store = TaskStore.instance;

  final ScrollController _statusScroll = ScrollController();
  final Map<String, GlobalKey> _statusKeys = {};
  String? _focusedStatus;
  String _taskQuery = '';

  /// 0 = danh sách theo trạng thái, 1 = lịch họp nhóm + deadline.
  int _viewMode = 0;

  static const List<String> _statuses = [
    'Cần làm',
    'Đang làm',
    'Cần sửa',
    'Chờ duyệt',
    'Cần bạn duyệt',
  ];

  List<Map<String, dynamic>> _tasksForStatus(String status) {
    List<Map<String, dynamic>> result;

    if (status == 'Cần bạn duyệt') {
      result = _store.tasksToReview();
    } else {
      result = _store
          .tasksForCurrentUser()
          .where((task) => task['status'] == status)
          .toList();
    }

    result.sort((a, b) {
      // Ưu tiên cao xếp trước; không hiện nhãn "Ưu tiên 1".
      final priorityA = _priorityRank(a['priority']?.toString());
      final priorityB = _priorityRank(b['priority']?.toString());

      if (priorityA != priorityB) {
        return priorityA.compareTo(priorityB);
      }

      final dateA = DateTime.tryParse(a['dueDate']?.toString() ?? '');
      final dateB = DateTime.tryParse(b['dueDate']?.toString() ?? '');

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
        return teamUpGreen;
      case 'Đang làm':
        return const Color(0xFF4285F4);
      case 'Chờ duyệt':
      case 'Cần bạn duyệt':
        return const Color(0xFFDB9B18);
      case 'Cần sửa':
        return teamUpPink;
      default:
        return _textSecondary;
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
        return teamUpGreen;
      case 'Marketing':
        return teamUpPink;
      case 'Research':
        return const Color(0xFFE1B32C);
      default:
        return teamUpPurple;
    }
  }

  Future<void> _startTask(Map<String, dynamic> task) async {
    try {
      await _store.startTask(task['id'].toString());
      setState(() {});
      _showMessage('Đã chuyển công việc sang Đang làm.');
    } catch (e) {
      _showMessage(e.toString());
    }
  }

  Future<void> _submitTask(Map<String, dynamic> task) async {
    final outputType = task['outputType']?.toString() ?? 'none';
    final outputRequired = task['outputRequired'] == true;
    final needsLink = outputType != 'none';
    final title = task['title']?.toString() ?? 'Công việc';

    final result = await showTextPrompt(
      context,
      title: 'Gửi kết quả công việc',
      message: needsLink
          ? '$title\n\n${outputRequired ? 'Công việc này yêu cầu đầu ra.' : 'Bạn có thể bổ sung đường dẫn kết quả.'}'
          : title,
      label: 'Đường dẫn kết quả',
      hint: 'https://...',
      initialText: task['outputLink']?.toString() ?? '',
      confirmLabel: 'Gửi',
      maxLines: 3,
      showField: needsLink,
      validator: (text) => outputRequired && text.isEmpty
          ? 'Vui lòng nhập đường dẫn kết quả.'
          : null,
    );

    if (result == null || !mounted) {
      return;
    }

    try {
      await _store.submitTask(task['id'].toString(), outputLink: result);

      if (!mounted) return;
      setState(() {});
      _showMessage(
        _store.roleInProject(task['projectId'].toString()) == 'Leader'
            ? 'Đã hoàn thành công việc.'
            : 'Đã gửi công việc cho Leader duyệt.',
      );
    } catch (e) {
      _showMessage(e.toString());
    }
  }

  Future<void> _reviewTask(
    Map<String, dynamic> task, {
    required bool approve,
  }) async {
    if (approve) {
      try {
        await _store.approveTask(task['id'].toString());
        if (!mounted) return;
        setState(() {});
        _showMessage('Đã duyệt công việc.');
      } catch (e) {
        _showMessage(e.toString());
      }
      return;
    }

    final comment = await showTextPrompt(
      context,
      title: 'Yêu cầu chỉnh sửa',
      label: 'Nhận xét',
      hint: 'Nêu rõ phần cần chỉnh sửa',
      confirmLabel: 'Gửi yêu cầu',
      minLines: 2,
      maxLines: 5,
    );

    if (comment == null || !mounted) {
      return;
    }

    try {
      await _store.requestTaskChanges(task['id'].toString(), comment: comment);
      if (!mounted) return;
      setState(() {});
      _showMessage('Đã yêu cầu chỉnh sửa công việc.');
    } catch (e) {
      _showMessage(e.toString());
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Mỗi cột trạng thái một màu riêng.
  Color _tabColor(int index) {
    const colors = [
      _textSecondary, // Cần làm
      Color(0xFF4285F4), // Đang làm
      teamUpPink, // Cần sửa
      Color(0xFFDB9B18), // Chờ duyệt
      teamUpGreen, // Cần bạn duyệt
    ];
    return colors[index.clamp(0, colors.length - 1)];
  }

  Color _selectedFilterColor(String? status) => switch (status) {
    'Cần làm' => const Color(0xFF7666A5),
    'Đang làm' => const Color(0xFF356BAE),
    'Cần sửa' => const Color(0xFFB5447D),
    'Chờ duyệt' => const Color(0xFF926713),
    'Cần bạn duyệt' => const Color(0xFF347546),
    _ => teamUpDarkPurple,
  };

  @override
  void dispose() {
    _notificationTimeout?.cancel();
    _store.removeListener(_openPendingNotification);
    _statusScroll.dispose();
    super.dispose();
  }

  int _countFor(String? status) => status == null
      ? _visibleEntries(null).length
      : _tasksForStatus(status).length;

  Widget _buildStatusTabs() => SizedBox(
    height: MediaQuery.textScalerOf(context).scale(14) + 40,
    child: ListView.separated(
      controller: _statusScroll,
      scrollDirection: Axis.horizontal,
      itemCount: _statuses.length + 1,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final status = index == 0 ? null : _statuses[index - 1];
        final selected = _focusedStatus == status;
        final accent = status == null
            ? teamUpDarkPurple
            : _statusColor(status);
        return Center(
          key: _statusKeys.putIfAbsent(status ?? 'all', () => GlobalKey()),
          child: ChoiceChip(
            label: Text('${status ?? 'Tất cả'} (${_countFor(status)})'),
            selected: selected,
            showCheckmark: false,
            backgroundColor: Colors.white,
            selectedColor: teamUpDarkPurple,
            side: BorderSide(
              color: selected ? teamUpDarkPurple : accent.withValues(alpha: .25),
            ),
            labelStyle: TextStyle(
              color: selected ? Colors.white : _textPrimary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            shape: const StadiumBorder(),
            onSelected: (_) {
              setState(() => _focusedStatus = status);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || !_statusScroll.hasClients) return;
                final target = _statusKeys[status ?? 'all']?.currentContext
                    ?.findRenderObject();
                if (target != null) {
                  _statusScroll.position.ensureVisible(
                    target,
                    alignment: .5,
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                  );
                }
              });
            },
          ),
        );
      },
    ),
  );

  /// Danh sách phẳng (task, tab) sau khi lọc trạng thái + từ khóa.
  /// Khi xem "Tất cả", việc cần tôi duyệt chỉ hiện một lần (kèm nút duyệt).
  List<(Map<String, dynamic>, String)> _visibleEntries(String? focused) {
    final query = _taskQuery.toLowerCase().trim();
    String key(Map<String, dynamic> t) => '${t['projectId']}/${t['id']}';
    final reviewKeys = {for (final t in _tasksForStatus('Cần bạn duyệt')) key(t)};
    final out = <(Map<String, dynamic>, String)>[];
    for (final status in focused == null ? _statuses : [focused]) {
      for (final task in _tasksForStatus(status)) {
        if (focused == null &&
            status != 'Cần bạn duyệt' &&
            reviewKeys.contains(key(task))) {
          continue;
        }
        if (query.isNotEmpty &&
            !(task['title'] ?? '').toString().toLowerCase().contains(query)) {
          continue;
        }
        out.add((task, status));
      }
    }
    return out;
  }

  Widget _buildHeaderCard() {
    final mine = _store.tasksForCurrentUser();
    final done = mine.where((t) => t['status'] == 'Hoàn thành').length;
    return Container(
      padding: const EdgeInsets.all(22),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: AccentBoxDecoration(
        accent: teamUpPurple,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE5E5FB), Color(0xFFF4E8F5)],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .8),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.assignment_ind_outlined,
              size: 26,
              color: teamUpDarkPurple,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Việc của tôi',
                  style: TextStyle(
                    fontSize: 23,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: teamUpDarkPurple,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${mine.length} công việc · $done hoàn thành',
                  style: const TextStyle(fontSize: 12, color: _textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openTask(Map<String, dynamic> task, String group) {
    final taskId = task['id'];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheet).height * .72,
          child: ListenableBuilder(
            listenable: _store,
            builder: (context, _) {
              final current = _store.tasks
                  .where(
                    (t) =>
                        t['id'] == taskId &&
                        t['projectId'] == task['projectId'],
                  )
                  .firstOrNull;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: current == null
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Công việc không còn khả dụng.'),
                      )
                    : _buildTaskCard(current, group),
              );
            },
          ),
        ),
      ),
    );
  }

  void _createTask() {
    final projects = _store
        .projectsForCurrentUser()
        .where((p) => _store.canCreateTask(p['id'].toString()))
        .toList();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            const Text(
              'Tạo công việc cho dự án',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            for (final project in projects)
              ListTile(
                leading: const Icon(Icons.folder_outlined, color: teamUpPurple),
                title: Text(project['name']?.toString() ?? 'Dự án'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(sheet);
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ProjectDetailScreen(
                        projectId: project['id'].toString(),
                        openCreateTask: true,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task, String currentTab) {
    final projectId = task['projectId']?.toString() ?? '';
    final project = _store.projectById(projectId);
    final projectColor = _projectColor(project);
    final status = task['status']?.toString() ?? 'Cần làm';
    final statusColor = _statusColor(status);
    final assigneeId = task['assigneeId']?.toString() ?? '';
    final isMyTask =
        assigneeId == _store.currentUserId ||
        (task['assigneeIds'] is List &&
            (task['assigneeIds'] as List).contains(_store.currentUserId));
    final isLeader = _store.roleInProject(projectId) == 'Leader';
    final isReviewTab = currentTab == 'Cần bạn duyệt';

    final canStart = isMyTask && (status == 'Cần làm' || status == 'Cần sửa');

    final canSubmit = isMyTask && status == 'Đang làm';

    final canReview = isLeader && status == 'Chờ duyệt';

    final pastel = switch (status) {
      'Đang làm' => const Color(0xFFDDEEFF),
      'Chờ duyệt' || 'Cần bạn duyệt' => const Color(0xFFFFEDCB),
      'Hoàn thành' => const Color(0xFFDCF3E8),
      'Cần sửa' => const Color(0xFFFCDDEC),
      _ => const Color(0xFFE9DAFA),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AccentBoxDecoration(
        accent: statusColor,
        gradient: pastelGradient(pastel),
        borderRadius: BorderRadius.circular(24),
      ),
      child: _buildTaskCardBody(
        task,
        currentTab,
        project,
        projectColor,
        status,
        statusColor,
        assigneeId,
        canStart,
        canSubmit,
        canReview,
        isReviewTab,
      ),
    );
  }

  Widget _buildTaskCardBody(
    Map<String, dynamic> task,
    String currentTab,
    Map<String, dynamic>? project,
    Color projectColor,
    String status,
    Color statusColor,
    String assigneeId,
    bool canStart,
    bool canSubmit,
    bool canReview,
    bool isReviewTab,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                task['title']?.toString() ?? 'Công việc',
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                ),
              ),
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

        // Nhãn dự án: luôn hiện tên dự án .
        Builder(
          builder: (context) {
            final name = (project?['name'] ?? '').toString().trim();
            return Wrap(
              spacing: 7,
              runSpacing: 7,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 260),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: projectColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_outlined, size: 14, color: projectColor),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          name.isEmpty ? 'Dự án' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: projectColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            const Icon(
              Icons.person_outline_rounded,
              size: 17,
              color: _textSecondary,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                _store.memberName(assigneeId),
                style: const TextStyle(color: _textSecondary, fontSize: 12),
              ),
            ),
            const Icon(
              Icons.calendar_today_outlined,
              size: 14,
              color: _textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              _formatDate(task['dueDate']?.toString()),
              style: const TextStyle(color: _textSecondary, fontSize: 12),
            ),
          ],
        ),

        if (task['reviewComment'] != null &&
            task['reviewComment'].toString().trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: teamUpPink.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Nhận xét: ${task['reviewComment']}',
              style: const TextStyle(color: Color(0xFFB94B83), fontSize: 12),
            ),
          ),
        ],

        if (task['outputLink'] != null &&
            task['outputLink'].toString().trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.link_rounded, color: teamUpPurple, size: 17),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  task['outputLink'].toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: teamUpDarkPurple, fontSize: 12),
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
              if (canStart)
                OutlinedButton.icon(
                  onPressed: () => _startTask(task),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(
                    status == 'Cần sửa' ? 'Tiếp tục chỉnh sửa' : 'Bắt đầu',
                  ),
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
                  style: FilledButton.styleFrom(backgroundColor: teamUpGreen),
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
    );
  }

  Widget _buildViewToggle() => Container(
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .75),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      children: [
        for (var i = 0; i < 2; i++)
          Expanded(
            child: Material(
              color: _viewMode == i ? teamUpDarkPurple : Colors.transparent,
              borderRadius: BorderRadius.circular(26),
              child: InkWell(
                borderRadius: BorderRadius.circular(26),
                onTap: () => setState(() => _viewMode = i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        i == 0
                            ? Icons.format_list_bulleted_rounded
                            : Icons.calendar_month_outlined,
                        size: 18,
                        color: _viewMode == i ? Colors.white : teamUpDarkPurple,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          i == 0 ? 'Công việc' : 'Lịch họp & deadline',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _viewMode == i
                                ? Colors.white
                                : teamUpDarkPurple,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  /// Task của tôi + task tôi cần duyệt (không trùng).
  List<Map<String, dynamic>> _myCalendarTasks() {
    final byId = <String, Map<String, dynamic>>{};
    for (final task in _store.tasksForCurrentUser()) {
      byId[task['id'].toString()] = task;
    }
    for (final task in _store.tasksToReview()) {
      byId[task['id'].toString()] = task;
    }
    return byId.values.toList();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _store,
    builder: (context, _) {
      final canCreate = _store.projectsForCurrentUser().any(
        (p) => _store.canCreateTask(p['id'].toString()),
      );
      final entries = _visibleEntries(_focusedStatus);
      final hasAny = _visibleEntries(null).isNotEmpty;
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.white,
          ),
          child: Column(
            children: [
              Expanded(
                child: _viewMode == 0
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                        children: [
                          _buildViewToggle(),
                          const SizedBox(height: 16),
                          _buildHeaderCard(),
                          TextField(
                            onChanged: (v) => setState(() => _taskQuery = v),
                            decoration: const InputDecoration(
                              hintText: 'Tìm công việc…',
                              prefixIcon: Icon(Icons.search_rounded),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _buildStatusTabs(),
                          const SizedBox(height: 18),
                          if (entries.isEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 40,
                                horizontal: 20,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.task_alt_rounded,
                                    size: 42,
                                    color: teamUpPurple,
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    hasAny
                                        ? 'Không có công việc phù hợp'
                                        : 'Bạn chưa có công việc cần xử lý',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (hasAny) ...[
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Thử đổi từ khóa hoặc bộ lọc trạng thái.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: _textSecondary,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            )
                          else
                            for (final (task, tab) in entries)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _buildTaskCard(task, tab),
                              ),
                        ],
                      )
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: _buildViewToggle(),
                          ),
                          Expanded(
                            child: TaskCalendarView(
                              store: _store,
                              myTasks: _myCalendarTasks(),
                              teamTasks: List.of(_store.tasks),
                              meetings: List.of(_store.meetings),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        floatingActionButton: canCreate
            ? FloatingActionButton.extended(
                onPressed: _createTask,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Tạo công việc'),
              )
            : null,
      );
    },
  );
}
