import 'notification_navigation.dart';
import '../../core/theme/accent_surface.dart';

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../controllers/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../services/service_errors.dart';
import '../../widgets/app_widgets.dart';
import '../tasks/task_store.dart';

/// Thông báo đọc trực tiếp từ `users/{uid}/notifications` qua stream realtime.
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key, this.session, this.unread, this.onTask});
  final void Function(String projectId, String taskId)? onTask;
  final SessionController? session;

  /// Báo số thông báo chưa đọc lên MainScreen để hiện badge.
  final ValueNotifier<int>? unread;

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

enum _NotificationType {
  assigned,
  deadline,
  completed,
  updated,
  meeting,
  vote,
  document,
  project,
  pendingReview,
  reviewRequired,
  revisionRequired,
  chat,
}

enum _NotificationFilter {
  chat,
  all,
  unread,
  task,
  reviewRequired,
  pendingReview,
  revisionRequired,
  workspace,
  project,
  deadline,
}

class _TeamNotification {
  _TeamNotification({
    required this.id,
    required this.title,
    required this.description,
    required this.time,
    required this.type,
    this.projectId = '',
    this.projectName = '',
    this.taskTitle = '',
    this.actorName = '',
    this.isRead = false,
  });
  final String id;
  final String title;
  final String description;
  final String time;
  final String projectId, projectName, taskTitle, actorName;
  final _NotificationType type;
  bool isRead;

  static _TeamNotification? fromJson(Map<String, dynamic> j) {
    final id = j['id']?.toString();
    if (id == null || id.isEmpty) return null;
    final type = switch ((j['type'] ?? '').toString().toLowerCase()) {
      'assigned' || 'assign' || 'task_assigned' => _NotificationType.assigned,
      'deadline' || 'due' || 'reminder' => _NotificationType.deadline,
      'meeting' => _NotificationType.meeting,
      'vote' => _NotificationType.vote,
      'document' => _NotificationType.document,
      'member_added' ||
      'project_joined' ||
      'member_left' => _NotificationType.project,
      'completed' || 'done' || 'approved' => _NotificationType.completed,
      'pending_review' => _NotificationType.pendingReview,
      'review_required' => _NotificationType.reviewRequired,
      'revision_required' => _NotificationType.revisionRequired,
      'chat' => _NotificationType.chat,
      _ => _NotificationType.updated,
    };
    final created = _createdAt(j['createdAt']);
    return _TeamNotification(
      id: id,
      title: (j['title'] ?? 'Thông báo').toString(),
      description: (j['body'] ?? j['description'] ?? j['message'] ?? '')
          .toString(),
      time: created == null ? '' : _ago(created.toLocal()),
      type: type,
      projectId: (j['projectId'] ?? '').toString(),
      projectName: (j['projectName'] ?? '').toString(),
      taskTitle: (j['taskTitle'] ?? '').toString(),
      actorName: (j['actorName'] ?? '').toString(),
      isRead: j['read'] == true || j['isRead'] == true,
    );
  }

  static DateTime? _createdAt(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Vừa xong';
    if (d.inMinutes < 60) return '${d.inMinutes} phút trước';
    if (d.inHours < 24) return '${d.inHours} giờ trước';
    if (d.inDays == 1) return 'Hôm qua';
    if (d.inDays < 7) return '${d.inDays} ngày trước';
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year}';
  }
}

class _NotificationScreenState extends State<NotificationScreen> {
  _NotificationFilter _selectedFilter = _NotificationFilter.all;
  final ScrollController _filterScroll = ScrollController();
  final Map<_NotificationFilter, GlobalKey> _filterKeys = {};
  List<_TeamNotification> _notifications = [];
  bool _loading = true;
  String? _loadError;
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;

  @override
  void initState() {
    super.initState();
    _listen();
    TaskStore.instance.addListener(_projectsChanged);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _filterScroll.dispose();
    TaskStore.instance.removeListener(_projectsChanged);
    super.dispose();
  }

  int get _unreadCount => _notifications.where((n) => !n.isRead).length;

  void _projectsChanged() {
    if (mounted) setState(() {});
  }

  String _projectLabel(_TeamNotification n) {
    for (final project in TaskStore.instance.projects) {
      if (project['id'] == n.projectId) {
        return 'Dự án: ${project['name'] ?? n.projectName}';
      }
    }
    if (n.projectName.isNotEmpty) return 'Dự án: ${n.projectName}';
    return n.projectId.isEmpty ? '' : 'Dự án: ${n.projectId}';
  }

  void _syncBadge() {
    final notifier = widget.unread;
    if (notifier != null && notifier.value != _unreadCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) notifier.value = _unreadCount;
      });
    }
  }

  /// Đăng ký lại stream; gọi khi mở màn hình và khi người dùng kéo làm mới.
  void _listen() {
    _subscription?.cancel();
    _subscription = null;
    final session = widget.session;
    if (session == null) {
      setState(() {
        _notifications = [];
        _loading = false;
        _loadError = 'Bạn chưa đăng nhập.';
      });
      _syncBadge();
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    _subscription = session.notifications.watchMine().listen(
      (rows) {
        if (!mounted) return;
        setState(() {
          _notifications = rows
              .map(_TeamNotification.fromJson)
              .whereType<_TeamNotification>()
              .toList();
          _loading = false;
          _loadError = null;
        });
        _syncBadge();
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _loadError = errorText(error);
        });
        _syncBadge();
      },
    );
  }

  Future<void> _refresh() async {
    _listen();
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  List<_TeamNotification> get _filtered => switch (_selectedFilter) {
    _NotificationFilter.chat =>
      _notifications.where((n) => n.type == _NotificationType.chat).toList(),
    _NotificationFilter.all => _notifications,
    _NotificationFilter.reviewRequired =>
      _notifications
          .where((n) => n.type == _NotificationType.reviewRequired)
          .toList(),
    _NotificationFilter.pendingReview =>
      _notifications
          .where((n) => n.type == _NotificationType.pendingReview)
          .toList(),
    _NotificationFilter.revisionRequired =>
      _notifications
          .where((n) => n.type == _NotificationType.revisionRequired)
          .toList(),
    _NotificationFilter.project =>
      _notifications.where((n) => n.type == _NotificationType.project).toList(),
    _NotificationFilter.unread =>
      _notifications.where((n) => !n.isRead).toList(),
    _NotificationFilter.task =>
      _notifications
          .where(
            (n) => {
              _NotificationType.assigned,
              _NotificationType.updated,
              _NotificationType.completed,
              _NotificationType.pendingReview,
              _NotificationType.reviewRequired,
              _NotificationType.revisionRequired,
            }.contains(n.type),
          )
          .toList(),
    _NotificationFilter.deadline =>
      _notifications
          .where((n) => n.type == _NotificationType.deadline)
          .toList(),
    _NotificationFilter.workspace =>
      _notifications
          .where(
            (n) =>
                n.type == _NotificationType.meeting ||
                n.type == _NotificationType.vote ||
                n.type == _NotificationType.document,
          )
          .toList(),
  };

  IconData _iconForType(_NotificationType t) => switch (t) {
    _NotificationType.chat => Icons.chat_bubble_outline_rounded,
    _NotificationType.assigned => Icons.assignment_ind_outlined,
    _NotificationType.deadline => Icons.schedule_rounded,
    _NotificationType.completed => Icons.task_alt_rounded,
    _NotificationType.updated => Icons.sync_rounded,
    _NotificationType.meeting => Icons.event_outlined,
    _NotificationType.vote => Icons.poll_outlined,
    _NotificationType.document => Icons.description_outlined,
    _NotificationType.project => Icons.group_add_outlined,
    _NotificationType.pendingReview => Icons.hourglass_empty_rounded,
    _NotificationType.reviewRequired => Icons.fact_check_outlined,
    _NotificationType.revisionRequired => Icons.edit_note_rounded,
  };

  Color _colorForType(_NotificationType t) => switch (t) {
    _NotificationType.chat => const Color(0xFFB74F8A),
    _NotificationType.assigned => AppColors.purple,
    _NotificationType.deadline => const Color(0xFFE08A00),
    _NotificationType.completed => AppColors.green,
    _NotificationType.updated => AppColors.darkPurple,
    _NotificationType.meeting => const Color(0xFF5078BB),
    _NotificationType.vote => const Color(0xFF45968A),
    _NotificationType.document => const Color(0xFFA3724C),
    _NotificationType.project => const Color(0xFF5B939D),
    _NotificationType.pendingReview => const Color(0xFFB88920),
    _NotificationType.reviewRequired => const Color(0xFF43845B),
    _NotificationType.revisionRequired => AppColors.pink,
  };

  String _labelForType(_NotificationType t) => switch (t) {
    _NotificationType.chat => 'Tin nhắn',
    _NotificationType.assigned => 'Giao việc',
    _NotificationType.deadline => 'Deadline',
    _NotificationType.completed => 'Hoàn thành',
    _NotificationType.updated => 'Cập nhật',
    _NotificationType.meeting => 'Lịch họp',
    _NotificationType.vote => 'Bình chọn',
    _NotificationType.document => 'Tài liệu',
    _NotificationType.project => 'Dự án',
    _NotificationType.pendingReview => 'Chờ duyệt',
    _NotificationType.reviewRequired => 'Cần bạn duyệt',
    _NotificationType.revisionRequired => 'Cần sửa',
  };

  Future<void> _markAsRead(_TeamNotification n) async {
    if (n.isRead) return;
    // Stream realtime sẽ cập nhật lại danh sách sau khi Firestore ghi xong,
    // nên chỉ optimistic-set để badge phản hồi ngay.
    setState(() => n.isRead = true);
    _syncBadge();
    final session = widget.session;
    if (session == null) return;
    try {
      await session.notifications.markRead(n.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => n.isRead = false);
      _syncBadge();
      showAppSnack(context, errorText(e), error: true);
    }
  }

  Future<void> _markAllAsRead() async {
    final session = widget.session;
    if (session == null) return;
    final previouslyUnread = _notifications.where((n) => !n.isRead).toList();
    if (previouslyUnread.isEmpty) return;
    setState(() {
      for (final n in previouslyUnread) {
        n.isRead = true;
      }
    });
    _syncBadge();
    try {
      await session.notifications.markAllRead();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        for (final n in previouslyUnread) {
          n.isRead = false;
        }
      });
      _syncBadge();
      showAppSnack(context, errorText(e), error: true);
    }
  }

  void _showDetail(_TeamNotification n) {
    _markAsRead(n);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _TypeBadge(
                      icon: _iconForType(n.type),
                      color: _colorForType(n.type),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        n.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_projectLabel(n).isNotEmpty) ...[
                  Text(
                    _projectLabel(n),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                ],
                if (n.taskTitle.isNotEmpty) Text('Công việc: ${n.taskTitle}'),
                if (n.actorName.isNotEmpty)
                  Text('Người thực hiện thao tác: ${n.actorName}'),
                const SizedBox(height: 8),
                Text(n.description),
                const SizedBox(height: 10),
                Text(
                  '${_labelForType(n.type)} · ${n.time}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheet),
                    child: const Text('Đóng'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, _NotificationFilter f) => Padding(
    key: _filterKeys.putIfAbsent(f, () => GlobalKey()),
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: _selectedFilter == f,
      showCheckmark: false,
      selectedColor: const Color(0xFF695296),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: _selectedFilter == f ? Colors.white : AppColors.darkPurple,
        fontWeight: FontWeight.w700,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      shape: const StadiumBorder(),
      onSelected: (_) {
        setState(() => _selectedFilter = f);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final target = _filterKeys[f]?.currentContext;
          final renderObject = target?.findRenderObject();
          if (target != null && renderObject != null) {
            Scrollable.of(target).position.ensureVisible(
              renderObject,
              alignment: .5,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            );
          }
        });
      },
    ),
  );

  Widget _tile(_TeamNotification n) {
    final (pastel, color) = switch (n.type) {
      _NotificationType.vote ||
      _NotificationType.deadline ||
      _NotificationType.revisionRequired => AppColors.workspaceVote,
      _NotificationType.chat ||
      _NotificationType.meeting => AppColors.workspaceMeeting,
      _ => AppColors.workspaceDocument,
    };
    final gradient = pastelGradient(
      Color.lerp(Colors.white, pastel, n.isRead ? .6 : 1)!,
    );
    const foreground = AppColors.darkPurple;
    return Dismissible(
      key: ValueKey('notif-${n.id}'),
      direction: n.isRead ? DismissDirection.none : DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        await _markAsRead(n);
        return false; // chỉ đánh dấu đã đọc, không xoá khỏi danh sách
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: AppColors.successSoft,
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.done_all_rounded, color: AppColors.green),
            SizedBox(width: 8),
            Text('Đã đọc', style: TextStyle(color: AppColors.green)),
          ],
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            final session = widget.session;
            if (session != null) {
              NotificationNavigation.open(context, session, {
                'id': n.id,
              }, onTask: widget.onTask);
            }
          },
          onLongPress: () => _showDetail(n),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: AccentBoxDecoration(
              accent: color,
              gradient: gradient,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TypeBadge(icon: _iconForType(n.type), color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.title,
                        style: TextStyle(
                          fontSize: 17,
                          height: 1.3,
                          color: foreground,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (_projectLabel(n).isNotEmpty) ...[
                        Text(
                          _projectLabel(n),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: foreground.withValues(alpha: .9),
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        n.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: foreground.withValues(alpha: .9),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_labelForType(n.type)} · ${n.time}',
                        style: TextStyle(
                          fontSize: 11,
                          color: foreground.withValues(alpha: .8),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!n.isRead)
                  Container(
                    margin: const EdgeInsets.only(left: 8, top: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Mới',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFB8428B),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SkeletonList(count: 5, itemHeight: 88);
    final items = _filtered;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Column(
        children: [
          if (_loadError != null)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF6DD),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _loadError!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: _listen,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            decoration: AccentBoxDecoration(
              accent: AppColors.workspaceMeeting.$2,
              gradient: pastelGradient(AppColors.workspaceMeeting.$1),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _unreadCount == 0
                        ? 'Bạn đã đọc hết thông báo'
                        : '$_unreadCount chưa đọc',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: _unreadCount == 0 ? null : _markAllAsRead,
                  icon: const Icon(Icons.done_all_rounded, size: 18),
                  label: const Text('Đọc tất cả'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 58,
            child: ListView(
              controller: _filterScroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                _chip('Tất cả', _NotificationFilter.all),
                _chip('Chưa đọc', _NotificationFilter.unread),
                _chip('Công việc', _NotificationFilter.task),
                _chip('Tin nhắn', _NotificationFilter.chat),
                _chip('Cần bạn duyệt', _NotificationFilter.reviewRequired),
                _chip('Chờ duyệt', _NotificationFilter.pendingReview),
                _chip('Cần sửa', _NotificationFilter.revisionRequired),
                _chip('Workspace', _NotificationFilter.workspace),
                _chip('Dự án', _NotificationFilter.project),
                _chip('Deadline', _NotificationFilter.deadline),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: items.isEmpty
                  ? ListView(
                      // ListView để kéo-làm-mới vẫn hoạt động khi danh sách rỗng
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: 360,
                          child: EmptyState(
                            icon: Icons.notifications_off_outlined,
                            title: _selectedFilter == _NotificationFilter.unread
                                ? 'Không còn thông báo chưa đọc'
                                : 'Chưa có thông báo nào',
                            message: 'Kéo xuống để làm mới.',
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _tile(items[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.icon, required this.color});
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 46,
    height: 46,
    child: Icon(icon, color: color, size: 30),
  );
}
