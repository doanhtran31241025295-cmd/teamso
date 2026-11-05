import '../../core/theme/accent_surface.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/app_services.dart';
import '../../services/service_errors.dart';
import '../../services/team_services.dart';
import '../../widgets/prompt_dialog.dart';
import 'invite_member_dialog.dart';

import 'package:url_launcher/url_launcher.dart';
import '../projects/project_qr_sheet.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';

const Color _background = Colors.white;
const Color _textPrimary = Color(0xFF282638);
const Color _textSecondary = Color(0xFF858397);

/// Project detail screen backed by realtime Cloud Firestore streams.
class ProjectDetailScreen extends StatefulWidget {
  final String projectId;
  final String? currentUserId;
  final bool openCreateTask;
  final String? initialTaskId;

  const ProjectDetailScreen({
    super.key,
    required this.projectId,
    this.currentUserId,
    this.openCreateTask = false,
    this.initialTaskId,
  });

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  // Dùng chung bộ Service của toàn app thay vì tạo instance riêng ở màn hình.
  final ProjectService _projectService = AppServices.instance.projects;
  final TaskService _taskService = AppServices.instance.tasks;
  StreamSubscription? _projectSubscription;
  StreamSubscription? _taskSubscription;
  StreamSubscription? _memberSubscription;

  String _taskFilter = 'Tất cả';
  final _taskFilterScroll = ScrollController();
  final Map<String, GlobalKey> _taskFilterKeys = {};
  String _taskQuery = '';
  bool _loading = true;
  bool _openedInitialTask = false;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _project;
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _members = [];

  String get _currentUserId => _currentUserIdFromProject();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTaskId == null ? 0 : 1,
    );
    _listenRealtime();
  }

  @override
  void dispose() {
    _taskFilterScroll.dispose();
    _tabController.dispose();
    _cancelSubscriptions();
    super.dispose();
  }

  void _cancelSubscriptions() {
    _projectSubscription?.cancel();
    _taskSubscription?.cancel();
    _memberSubscription?.cancel();
    _projectSubscription = null;
    _taskSubscription = null;
    _memberSubscription = null;
  }

  /// Stream realtime là nguồn dữ liệu duy nhất cho cả ba Pane (project, tasks,
  /// members), nên màn hình không gọi thêm `get`/`list` trùng logic truy vấn.
  void _listenRealtime() {
    _projectSubscription = _projectService
        .watch(widget.projectId)
        .listen(
          (project) {
            if (!mounted) return;
            if (project == null) {
              setState(() {
                _loading = false;
                _error = 'Không tìm thấy dự án.';
              });
              return;
            }
            setState(() {
              _project = project;
              _loading = false;
              _error = null;
            });
            if (widget.openCreateTask && !_openedInitialTask && _isLeader) {
              _openedInitialTask = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _showCreateTaskDialog();
              });
            }
          },
          onError: (Object error) {
            if (mounted) {
              setState(() {
                _loading = false;
                _error = errorText(error);
              });
            }
          },
        );
    _taskSubscription = _taskService
        .watch(projectId: widget.projectId)
        .listen(
          (rows) {
            if (!mounted) return;
            setState(() => _tasks = rows);
          },
          onError: (Object error) {
            if (mounted) setState(() => _error = errorText(error));
          },
        );
    _memberSubscription = _projectService
        .watchMembers(widget.projectId)
        .listen(
          (rows) {
            if (!mounted) return;
            setState(() => _members = rows);
          },
          onError: (Object error) {
            if (mounted) setState(() => _error = errorText(error));
          },
        );
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry('$key', value));
    }
    return null;
  }

  dynamic _firstValue(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      if (json.containsKey(key) && json[key] != null) {
        return json[key];
      }
    }
    return null;
  }

  String _stringValue(
    Map<String, dynamic> json,
    List<String> keys, {
    String fallback = '',
  }) {
    final value = _firstValue(json, keys);
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    return value == null ? fallback : value.toString();
  }

  /// Kéo-làm-mới và nút thử lại: dựng lại các subscription realtime. Stream đã
  /// phát dữ liệu mới nhất nên không cần gọi `get`/`list` trùng ở đây.
  Future<void> _loadPage({bool showLoading = true}) async {
    if (!mounted) return;
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    _cancelSubscriptions();
    _listenRealtime();
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  String get _role {
    final project = _project ?? {};
    final role = _stringValue(project, const [
      'myRole',
      'role',
      'currentUserRole',
    ]);
    if (role.isNotEmpty) {
      return role.toLowerCase() == 'leader' ? 'Leader' : 'Member';
    }
    final leaderId = _stringValue(project, const [
      'leaderId',
      'leader_id',
      'ownerId',
    ]);
    if (leaderId.isNotEmpty && leaderId == _currentUserId) {
      return 'Leader';
    }
    return 'Member';
  }

  bool get _isLeader => _role.toLowerCase() == 'leader';

  String _taskId(Map<String, dynamic> task) =>
      _stringValue(task, const ['id', '_id', 'taskId', 'task_id']);

  String _status(Map<String, dynamic> task) => _normalizeStatus(
    _stringValue(task, const [
      'status',
      'taskStatus',
      'task_status',
    ], fallback: 'Cần làm'),
  );

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
      case 'in progress':
      case 'doing':
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

  String _assigneeId(Map<String, dynamic> task) {
    final ids = task['assigneeIds'];
    if (ids is List && ids.isNotEmpty) return ids.first.toString();
    return _stringValue(task, const [
      'assigneeId',
      'assignee_id',
      'assignedTo',
      'userId',
      'user_id',
    ]);
  }

  String _currentUserIdFromProject() {
    final supplied = widget.currentUserId?.trim() ?? '';
    if (supplied.isNotEmpty) {
      return supplied;
    }
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  String _memberName(dynamic memberOrId) {
    if (memberOrId is Map) {
      final member = _asMap(memberOrId) ?? {};
      return _stringValue(member, const [
        'name',
        'displayName',
        'fullName',
        'full_name',
        'username',
        'email',
      ], fallback: 'Thành viên');
    }
    final id = memberOrId?.toString() ?? '';
    final found = _members.where(
      (m) =>
          _stringValue(m, const ['uid', 'id', '_id', 'userId', 'user_id']) ==
          id,
    );
    if (found.isNotEmpty) {
      return _memberName(found.first);
    }
    return id.isEmpty ? 'Chưa phân công' : 'Thành viên $id';
  }

  String _leaderId() => _stringValue(_project ?? {}, const [
    'leaderId',
    'leader_id',
    'ownerId',
    'owner_id',
  ]);

  bool _isMyTask(Map<String, dynamic> task) {
    final userId = _currentUserIdFromProject();
    final ids = task['assigneeIds'];
    return userId.isNotEmpty &&
        (ids is List ? ids.contains(userId) : _assigneeId(task) == userId);
  }

  int _countStatus(String status) =>
      _tasks.where((task) => _status(task) == status).length;

  Color _statusColor(String status) {
    switch (status) {
      case 'Hoàn thành':
        return teamUpGreen;
      case 'Đang làm':
        return const Color(0xFF4285F4);
      case 'Chờ duyệt':
        return const Color(0xFFDB9B18);
      case 'Cần sửa':
        return teamUpPink;
      default:
        return const Color(0xFF9270C5);
    }
  }

  Color _projectColor(Map<String, dynamic> project) {
    final raw = _firstValue(project, const ['color', 'colorValue']);
    if (raw is int) {
      return Color(raw);
    }
    switch (_stringValue(project, const ['tag', 'category']).toLowerCase()) {
      case 'mobile':
        return teamUpGreen;
      case 'marketing':
        return teamUpPink;
      case 'research':
        return const Color(0xFFE1B32C);
      default:
        return teamUpDarkPurple;
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

  void _message(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
      // Stream realtime tự cập nhật project/tasks/members sau khi ghi,
      // nên không cần gọi lại truy vấn ở đây.
      if (mounted) {
        _message(successMessage);
      }
    } catch (e) {
      if (mounted) {
        _message(errorText(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _showCreateTaskDialog() async {
    if (!_isLeader) {
      _message('Chỉ Leader của dự án mới được tạo công việc.');
      return;
    }
    // Danh sách người thực hiện: lấy uid từ nhiều khóa có thể có và loại trùng
    // (DropdownButton không cho phép hai mục cùng value).
    final seen = <String>{};
    final memberItems = <DropdownMenuItem<String>>[];
    for (final member in _members) {
      final id = _stringValue(member, const [
        'uid',
        'id',
        '_id',
        'userId',
        'user_id',
      ]);
      if (id.isEmpty || !seen.add(id)) continue;
      memberItems.add(
        DropdownMenuItem<String>(
          value: id,
          child: Text(_memberName(member), overflow: TextOverflow.ellipsis),
        ),
      );
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          _CreateTaskDialog(memberItems: memberItems, formatDate: _formatDate),
    );
    if (result == null || !mounted) {
      return;
    }
    await _runAction(
      () => _taskService.create(widget.projectId, result),
      successMessage: 'Đã tạo công việc.',
    );
  }

  Future<void> _startTask(Map<String, dynamic> task) async {
    final id = _taskId(task);
    if (id.isEmpty) {
      _message('Task không có ID hợp lệ.');
      return;
    }
    await _runAction(
      () => _taskService.transition(widget.projectId, id, 'in_progress'),
      successMessage: 'Đã chuyển công việc sang Đang làm.',
    );
  }

  Future<void> _submitTask(Map<String, dynamic> task) async {
    final initialLink = _stringValue(task, const [
      'outputLink',
      'output_link',
      'submissionUrl',
      'submission_url',
    ]);
    final outputType = _stringValue(task, const [
      'outputType',
      'output_type',
    ], fallback: 'docs');
    final outputRequired =
        _firstValue(task, const ['outputRequired', 'output_required']) != false;
    final needsLink = outputType != 'none';
    final title = _stringValue(task, const [
      'title',
      'name',
    ], fallback: 'Công việc');

    final result = await showTextPrompt(
      context,
      title: 'Gửi kết quả công việc',
      message: needsLink
          ? title
          : '$title\n\nCông việc này không yêu cầu đường dẫn đầu ra.',
      label: 'Đường dẫn kết quả',
      hint: 'https://docs.google.com/...',
      initialText: initialLink,
      confirmLabel: 'Gửi',
      maxLines: 3,
      showField: needsLink,
      validator: (text) {
        if (outputRequired && text.isEmpty) {
          return 'Vui lòng nhập đường dẫn kết quả.';
        }
        if (text.isNotEmpty) {
          final uri = Uri.tryParse(text);
          if (uri == null ||
              !uri.hasAuthority ||
              !['http', 'https'].contains(uri.scheme)) {
            return 'Vui lòng nhập URL bắt đầu bằng http:// hoặc https://';
          }
        }
        return null;
      },
    );
    if (result == null || !mounted) {
      return;
    }

    final id = _taskId(task);
    if (id.isEmpty) {
      _message('Task không có ID hợp lệ.');
      return;
    }
    await _runAction(
      () async {
        await _taskService.transition(
          widget.projectId,
          id,
          _isLeader && _isMyTask(task) ? 'completed' : 'pending_review',
          outputLink: result,
        );
      },
      successMessage: _isLeader
          ? 'Đã cập nhật kết quả công việc.'
          : 'Đã gửi công việc để Leader duyệt.',
    );
  }

  Future<void> _reviewTask(
    Map<String, dynamic> task, {
    required bool approve,
  }) async {
    String? comment;
    if (!approve) {
      comment = await showTextPrompt(
        context,
        title: 'Yêu cầu chỉnh sửa',
        label: 'Nhận xét',
        hint: 'Nêu rõ nội dung cần chỉnh sửa',
        confirmLabel: 'Gửi yêu cầu',
        minLines: 2,
        maxLines: 5,
      );
      if (comment == null || !mounted) {
        return;
      }
    }

    final id = _taskId(task);
    if (id.isEmpty) {
      _message('Task không có ID hợp lệ.');
      return;
    }
    await _runAction(
      () async {
        await _taskService.transition(
          widget.projectId,
          id,
          approve ? 'completed' : 'revision_required',
          comment: comment,
        );
      },
      successMessage: approve
          ? 'Đã duyệt công việc.'
          : 'Đã gửi yêu cầu chỉnh sửa.',
    );
  }

  Future<void> _openLink(String rawLink) async {
    final uri = Uri.tryParse(rawLink.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        !['http', 'https'].contains(uri.scheme)) {
      _message('Đường dẫn không hợp lệ.');
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        _message('Không thể mở đường dẫn này.');
      }
    } catch (_) {
      if (mounted) {
        _message('Đã xảy ra lỗi khi mở đường dẫn.');
      }
    }
  }

  Widget _statCard(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: AccentBoxDecoration(
          accent: color,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.18),
              color.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: _textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addMemberByUsername() async {
    final picked = await showInviteMemberDialog(
      context,
      service: _projectService,
      existingUids: {
        for (final member in _members)
          (member['uid'] ?? member['id'] ?? '').toString(),
      },
    );
    final username = (picked?['username'] ?? '').toString();
    if (username.isEmpty || !mounted) return;
    await _runAction(
      () => _projectService.addMemberByUsername(widget.projectId, username),
      successMessage: 'Đã thêm thành viên.',
    );
  }

  Future<void> _removeMember(String uid) async {
    await _runAction(
      () => _projectService.removeMember(widget.projectId, uid),
      successMessage: 'Đã xóa thành viên khỏi dự án.',
    );
  }

  /// Leader chỉnh tên/mô tả/thẻ của dự án.
  Future<void> _editProject() async {
    final project = _project;
    if (project == null) return;
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _EditProjectDialog(
        name: _stringValue(project, const ['name'], fallback: 'Dự án'),
        description: _stringValue(project, const ['description']),
        tag: _stringValue(project, const ['tag']),
      ),
    );
    if (values == null || !mounted) return;
    await _runAction(
      () => _projectService.update(widget.projectId, values),
      successMessage: 'Đã cập nhật dự án.',
    );
  }

  Future<void> _leaveProject() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Rời dự án'),
        content: const Text('Bạn chắc chắn muốn rời khỏi dự án này?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Rời dự án'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _runAction(
      () => _projectService.leave(widget.projectId),
      successMessage: 'Bạn đã rời dự án.',
    );
    if (mounted) Navigator.maybePop(context);
  }

  Future<void> _deleteProject() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Xóa dự án'),
        content: const Text(
          'Toàn bộ công việc, thành viên và dữ liệu của dự án sẽ bị xóa vĩnh viễn. '
          'Bạn chắc chắn chứ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: teamUpPink),
            child: const Text('Xóa dự án'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _runAction(
      () => _projectService.delete(widget.projectId),
      successMessage: 'Đã xóa dự án.',
    );
    if (mounted) Navigator.maybePop(context);
  }

  void _onMenuSelected(String value) => switch (value) {
    'edit' => _editProject(),
    'leave' => _leaveProject(),
    'delete' => _deleteProject(),
    _ => null,
  };

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );

  Widget _section(String title, String subtitle, {Widget? action}) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: _textSecondary),
              ),
            ],
          ),
        ),
        ?action,
      ],
    ),
  );

  Widget _buildOverview(Map<String, dynamic> project) {
    final name = _stringValue(project, const [
      'name',
      'title',
      'projectName',
    ], fallback: 'Dự án');
    final description = _stringValue(project, const ['description']);
    final code = _stringValue(project, const ['joinCode']);
    final completed = _countStatus('Hoàn thành');
    final progress = _tasks.isEmpty ? 0.0 : completed / _tasks.length;
    return RefreshIndicator(
      onRefresh: _loadPage,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: AccentBoxDecoration(
              accent: teamUpPurple,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE5E5FB), Color(0xFFF4E8F5)],
              ),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .8),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.folder_open_rounded,
                        color: teamUpDarkPurple,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                              color: teamUpDarkPurple,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _pill(
                            _isLeader ? 'Trưởng nhóm' : 'Thành viên',
                            teamUpDarkPurple,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: Color(0xFF69627D),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$completed/${_tasks.length} công việc hoàn thành',
                        style: const TextStyle(
                          fontSize: 12,
                          color: teamUpDarkPurple,
                        ),
                      ),
                    ),
                    Text(
                      '${(progress * 100).round()}%',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: teamUpDarkPurple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    color: teamUpPurple,
                    backgroundColor: Colors.white.withValues(alpha: .75),
                  ),
                ),
              ],
            ),
          ),
          if (code.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              decoration: AccentBoxDecoration(
                accent: teamUpPurple,
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE8E6ED)),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 5,
                ),
                leading: const Icon(
                  Icons.vpn_key_outlined,
                  color: teamUpPurple,
                  size: 28,
                ),
                title: const Text(
                  'Mã tham gia',
                  style: TextStyle(fontSize: 12, color: _textSecondary),
                ),
                subtitle: SelectableText(
                  code,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: teamUpDarkPurple,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Tạo mã QR',
                      icon: const Icon(
                        Icons.qr_code_2_rounded,
                        size: 24,
                        color: teamUpDarkPurple,
                      ),
                      onPressed: () => showProjectQrSheet(
                        context,
                        projectName: name,
                        joinCode: code,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Sao chép mã tham gia',
                      icon: const Icon(
                        Icons.copy_rounded,
                        size: 20,
                        color: teamUpDarkPurple,
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        _message('Đã sao chép mã tham gia.');
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
          _section(
            'Tiến độ công việc',
            'Theo dõi tình hình thực hiện của cả nhóm',
          ),
          Row(
            children: [
              _statCard('Cần làm', _countStatus('Cần làm'), teamUpPurple),
              const SizedBox(width: 12),
              _statCard(
                'Đang làm',
                _countStatus('Đang làm'),
                const Color(0xFF5A91C8),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _statCard(
                'Chờ duyệt',
                _countStatus('Chờ duyệt'),
                const Color(0xFFB68630),
              ),
              const SizedBox(width: 12),
              _statCard('Hoàn thành', completed, teamUpGreen),
            ],
          ),
          if (_countStatus('Cần sửa') > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _pill(
                '${_countStatus('Cần sửa')} công việc cần chỉnh sửa',
                const Color(0xFFAD4D82),
              ),
            ),
          _section(
            'Thành viên',
            '${_members.length} người trong dự án',
            action: _isLeader
                ? IconButton.filledTonal(
                    tooltip: 'Thêm thành viên',
                    onPressed: _busy ? null : _addMemberByUsername,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 21),
                  )
                : null,
          ),
          Container(
            decoration: AccentBoxDecoration(
              accent: teamUpGreen,
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE8E6ED)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                if (_members.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Chưa có thông tin thành viên.',
                      style: TextStyle(color: _textSecondary),
                    ),
                  ),
                ..._members.indexed.map((entry) {
                  final member = entry.$2;
                  final id = _stringValue(member, const [
                    'uid',
                    'id',
                    '_id',
                    'userId',
                    'user_id',
                  ]);
                  final name = _memberName(member);
                  final leader =
                      id == _leaderId() ||
                      _stringValue(member, const ['role']).toLowerCase() ==
                          'leader';
                  final username = _stringValue(member, const ['username']);
                  return Column(
                    children: [
                      if (entry.$1 > 0)
                        const Divider(
                          height: 1,
                          indent: 72,
                          endIndent: 16,
                          color: Color(0xFFF0EEF5),
                        ),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 5,
                        ),
                        leading: CircleAvatar(
                          radius: 21,
                          backgroundColor: leader
                              ? const Color(0xFFF4E8F5)
                              : const Color(0xFFEFEDF8),
                          child: Text(
                            name.trim().isEmpty
                                ? '?'
                                : name.characters.first.toUpperCase(),
                            style: const TextStyle(
                              color: teamUpDarkPurple,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        title: Text(
                          id == _currentUserId ? '$name (Bạn)' : name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: username.isEmpty
                            ? null
                            : Text(
                                '@$username',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _textSecondary,
                                ),
                              ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _pill(
                              leader ? 'Trưởng nhóm' : 'Thành viên',
                              leader ? teamUpDarkPurple : teamUpGreen,
                            ),
                            if (_isLeader && !leader && id.isNotEmpty)
                              IconButton(
                                tooltip: 'Xóa thành viên',
                                onPressed: _busy
                                    ? null
                                    : () => _removeMember(id),
                                icon: const Icon(
                                  Icons.person_remove_outlined,
                                  size: 18,
                                  color: _textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTasks() {
    final rows = _tasks
        .where(
          (task) =>
              widget.initialTaskId == null ||
              task['id'] == widget.initialTaskId,
        )
        .where(
          (task) =>
              (_taskFilter == 'Tất cả' || _status(task) == _taskFilter) &&
              _stringValue(task, const [
                'title',
                'name',
              ]).toLowerCase().contains(_taskQuery.toLowerCase().trim()),
        )
        .toList();
    return RefreshIndicator(
      onRefresh: _loadPage,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: [
          Container(
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
                    Icons.assignment_outlined,
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
                        'Công việc của nhóm',
                        style: TextStyle(
                          fontSize: 23,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: teamUpDarkPurple,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_tasks.length} công việc · ${_countStatus('Hoàn thành')} hoàn thành',
                        style: const TextStyle(
                          fontSize: 12,
                          color: _textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          TextField(
            onChanged: (value) => setState(() => _taskQuery = value),
            decoration: const InputDecoration(
              hintText: 'Tìm công việc…',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(14) + 40,
            child: ListView.separated(
              controller: _taskFilterScroll,
              scrollDirection: Axis.horizontal,
              itemCount: 6,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                const statuses = [
                  'Tất cả',
                  'Cần làm',
                  'Đang làm',
                  'Chờ duyệt',
                  'Cần sửa',
                  'Hoàn thành',
                ];
                final status = statuses[index];
                final selected = _taskFilter == status;
                final accent = status == 'Tất cả'
                    ? teamUpDarkPurple
                    : _statusColor(status);
                final count = status == 'Tất cả'
                    ? _tasks.length
                    : _countStatus(status);
                return Center(
                  key: _taskFilterKeys.putIfAbsent(status, () => GlobalKey()),
                  child: ChoiceChip(
                    label: Text('$status ($count)'),
                    selected: selected,
                    showCheckmark: false,
                    backgroundColor: Colors.white,
                    selectedColor: teamUpDarkPurple,
                    side: BorderSide(
                      color: selected
                          ? teamUpDarkPurple
                          : accent.withValues(alpha: .25),
                    ),
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : _textPrimary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    shape: const StadiumBorder(),
                    onSelected: (_) {
                      setState(() => _taskFilter = status);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted || !_taskFilterScroll.hasClients) return;
                        final target = _taskFilterKeys[status]?.currentContext
                            ?.findRenderObject();
                        if (target != null) {
                          _taskFilterScroll.position.ensureVisible(
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
          ),
          const SizedBox(height: 18),
          if (rows.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
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
                    _tasks.isEmpty
                        ? 'Chưa có công việc'
                        : 'Không có công việc phù hợp',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _tasks.isEmpty
                        ? (_isLeader
                              ? 'Tạo công việc đầu tiên để bắt đầu phân công cho nhóm.'
                              : 'Công việc sẽ xuất hiện khi trưởng nhóm phân công.')
                        : 'Thử đổi từ khóa hoặc bộ lọc trạng thái.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _textSecondary, height: 1.5),
                  ),
                ],
              ),
            )
          else
            ...rows.map(
              (task) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildTaskCard(task),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final title = _stringValue(task, const [
      'title',
      'name',
    ], fallback: 'Công việc');
    final status = _status(task);
    final assigneeId = _assigneeId(task);
    final color = _statusColor(status);
    final outputLink = _stringValue(task, const [
      'outputLink',
      'output_link',
      'submissionUrl',
      'submission_url',
    ]);
    final comment = _stringValue(task, const [
      'reviewComment',
      'review_comment',
      'feedback',
    ]);
    final dueDate = _stringValue(task, const [
      'dueDate',
      'due_date',
      'deadline',
    ]);
    final mine = _isMyTask(task);
    final canStart = mine && (status == 'Cần làm' || status == 'Cần sửa');
    final canSubmit = mine && status == 'Đang làm';
    final canReview = _isLeader && status == 'Chờ duyệt';

    final pastel = switch (status) {
      'Đang làm' => const Color(0xFFDDEEFF),
      'Chờ duyệt' => const Color(0xFFFFEDCB),
      'Hoàn thành' => const Color(0xFFDCF3E8),
      'Cần sửa' => const Color(0xFFFCDDEC),
      _ => const Color(0xFFE9DAFA),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: pastelGradient(pastel),
        borderRadius: BorderRadius.circular(24),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (_stringValue(task, const ['description']).isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _stringValue(task, const ['description']),
              style: const TextStyle(color: _textSecondary, fontSize: 13),
            ),
          ],
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
                  task['assigneeIds'] is List
                      ? (task['assigneeIds'] as List)
                            .map(_memberName)
                            .join(', ')
                      : _memberName(assigneeId),
                  style: const TextStyle(fontSize: 12, color: _textSecondary),
                ),
              ),
              const Icon(
                Icons.calendar_today_outlined,
                size: 14,
                color: _textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                _formatDate(dueDate),
                style: const TextStyle(fontSize: 12, color: _textSecondary),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE7F2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Nhận xét: $comment',
                style: const TextStyle(color: Color(0xFFB94B83), fontSize: 12),
              ),
            ),
          ],
          if (outputLink.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.link_rounded, size: 17, color: teamUpPurple),
                const SizedBox(width: 6),
                Expanded(
                  child: InkWell(
                    onTap: () => _openLink(outputLink),
                    child: Text(
                      outputLink,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: teamUpDarkPurple,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Mở link',
                  onPressed: () => _openLink(outputLink),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  color: teamUpDarkPurple,
                ),
              ],
            ),
          ],
          if (canStart || canSubmit || canReview) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canStart)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _startTask(task),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(
                      status == 'Cần sửa' ? 'Tiếp tục chỉnh sửa' : 'Bắt đầu',
                    ),
                  ),
                if (canSubmit)
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _submitTask(task),
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Gửi kết quả'),
                  ),
                if (canReview) ...[
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _reviewTask(task, approve: true),
                    icon: const Icon(Icons.check_rounded, size: 17),
                    label: const Text('Duyệt'),
                    style: FilledButton.styleFrom(backgroundColor: teamUpGreen),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _reviewTask(task, approve: false),
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

  @override
  Widget build(BuildContext context) {
    final project = _project;
    final projectName = project == null
        ? 'Chi tiết dự án'
        : _stringValue(project, const [
            'name',
            'title',
            'projectName',
          ], fallback: 'Chi tiết dự án');
    final color = project == null ? teamUpDarkPurple : _projectColor(project);

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          projectName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        actions: [
          if (_project != null)
            PopupMenuButton<String>(
              tooltip: 'Tùy chọn dự án',
              enabled: !_busy,
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: _onMenuSelected,
              itemBuilder: (_) => [
                if (_isLeader)
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Sửa dự án'),
                    ),
                  ),
                if (!_isLeader)
                  const PopupMenuItem(
                    value: 'leave',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.logout_rounded),
                      title: Text('Rời dự án'),
                    ),
                  ),
                if (_isLeader)
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.delete_outline_rounded,
                        color: teamUpPink,
                      ),
                      title: Text('Xóa dự án'),
                    ),
                  ),
              ],
            ),
          IconButton(
            tooltip: 'Tải lại',
            onPressed: _loading ? null : _loadPage,
            icon: const Icon(Icons.refresh_rounded, color: _textPrimary),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: _textSecondary,
          indicatorColor: color,
          indicatorWeight: 3,
          dividerColor: Colors.transparent,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: teamUpDarkPurple,
            borderRadius: BorderRadius.circular(16),
          ),
          indicatorPadding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 7,
          ),
          tabs: const [
            Tab(text: 'Tổng quan'),
            Tab(text: 'Công việc'),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: teamUpDarkPurple),
            )
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      size: 48,
                      color: _textSecondary,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Không thể tải dữ liệu dự án',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _textSecondary),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _loadPage,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Thử lại'),
                    ),
                  ],
                ),
              ),
            )
          : project == null
          ? const Center(child: Text('API không trả về thông tin dự án.'))
          : Stack(
              children: [
                ColoredBox(
                  color: const Color(0xFFEEEBF8),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    child: ColoredBox(
                      color: _background,
                      child: TabBarView(
                        controller: _tabController,
                        children: [_buildOverview(project), _buildTasks()],
                      ),
                    ),
                  ),
                ),
                if (_busy)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: teamUpDarkPurple,
                    ),
                  ),
              ],
            ),
      floatingActionButton: !_loading && _error == null && _isLeader
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _showCreateTaskDialog,
              backgroundColor: teamUpDarkPurple,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Tạo công việc'),
            )
          : null,
    );
  }
}

/// Hộp thoại tạo công việc. Controller thuộc về State nên chỉ bị hủy sau khi
/// animation đóng kết thúc (tránh lỗi "used after being disposed").
class _CreateTaskDialog extends StatefulWidget {
  const _CreateTaskDialog({
    required this.memberItems,
    required this.formatDate,
  });

  final List<DropdownMenuItem<String>> memberItems;
  final String Function(String? value) formatDate;

  @override
  State<_CreateTaskDialog> createState() => _CreateTaskDialogState();
}

class _CreateTaskDialogState extends State<_CreateTaskDialog> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _assigneeId;
  String _priority = 'medium';
  DateTime? _dueDate;
  String _outputType = 'docs';
  bool _outputRequired = true;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _dueDate = picked);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(context, {
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim(),
      'assigneeId': _assigneeId,
      'priority': _priority,
      'dueDate': _dueDate?.toIso8601String(),
      'outputType': _outputType,
      'outputRequired': _outputType != 'none' && _outputRequired,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Tạo công việc'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Tên công việc *',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Vui lòng nhập tên công việc'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Mô tả'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _assigneeId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Người thực hiện',
                  ),
                  items: widget.memberItems,
                  onChanged: (value) => setState(() => _assigneeId = value),
                  validator: (value) =>
                      value == null ? 'Vui lòng chọn người thực hiện' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _priority,
                  decoration: const InputDecoration(
                    labelText: 'Mức độ ưu tiên',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Thấp')),
                    DropdownMenuItem(
                      value: 'medium',
                      child: Text('Trung bình'),
                    ),
                    DropdownMenuItem(value: 'high', child: Text('Cao')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _priority = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _outputType,
                  decoration: const InputDecoration(labelText: 'Loại đầu ra'),
                  items: const [
                    DropdownMenuItem(
                      value: 'docs',
                      child: Text('Google Docs / Tài liệu'),
                    ),
                    DropdownMenuItem(
                      value: 'drive',
                      child: Text('Google Drive'),
                    ),
                    DropdownMenuItem(
                      value: 'sheet',
                      child: Text('Google Sheets / Bảng tính'),
                    ),
                    DropdownMenuItem(
                      value: 'file',
                      child: Text('Tệp đính kèm'),
                    ),
                    DropdownMenuItem(
                      value: 'none',
                      child: Text('Không yêu cầu đầu ra'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _outputType = value;
                      if (value == 'none') _outputRequired = false;
                    });
                  },
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bắt buộc nộp đường dẫn/kết quả'),
                  value: _outputType == 'none' ? false : _outputRequired,
                  onChanged: _outputType == 'none'
                      ? null
                      : (value) =>
                            setState(() => _outputRequired = value ?? true),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      _dueDate == null
                          ? 'Chọn hạn hoàn thành'
                          : 'Hạn: ${widget.formatDate(_dueDate!.toIso8601String())}',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Tạo công việc')),
      ],
    );
  }
}

/// Hộp thoại sửa thông tin dự án; trả về map name/description/tag.
class _EditProjectDialog extends StatefulWidget {
  const _EditProjectDialog({
    required this.name,
    required this.description,
    required this.tag,
  });

  final String name;
  final String description;
  final String tag;

  @override
  State<_EditProjectDialog> createState() => _EditProjectDialogState();
}

class _EditProjectDialogState extends State<_EditProjectDialog> {
  late final _name = TextEditingController(text: widget.name);
  late final _description = TextEditingController(text: widget.description);
  late final _tag = TextEditingController(text: widget.tag);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _tag.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(context, {
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'tag': _tag.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Cập nhật dự án'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Tên dự án *'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Tên không được để trống' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Mô tả'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tag,
                decoration: const InputDecoration(
                  labelText: 'Thẻ / danh mục',
                  hintText: 'mobile, marketing, research...',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _save, child: const Text('Lưu')),
      ],
    );
  }
}
