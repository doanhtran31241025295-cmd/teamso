import 'package:flutter/foundation.dart';

import '../core/utils/api_json.dart';
import '../models/task_model.dart';
import '../services/api_client.dart';

/// Nguồn dữ liệu duy nhất cho Home và Task Board: dự án của tài khoản đang
/// đăng nhập và các công việc trong từng dự án, đều lấy từ API.
///
/// Endpoint sử dụng (cùng quy ước với ProjectDetailScreen):
///   GET   /projects                     danh sách dự án của người dùng
///   GET   /projects/:id/tasks           công việc của một dự án
///   PATCH /tasks/:id/start
///   POST  /tasks/:id/submit             {outputLink}
///   POST  /tasks/:id/approve
///   POST  /tasks/:id/request-changes    {comment}
class ProjectsController extends ChangeNotifier {
  ProjectsController(this.api, this.userId);

  final ApiClient api;
  final String userId;

  List<Map<String, dynamic>> projects = [];
  final Map<String, List<TaskModel>> _tasks = {};
  bool loading = false;
  bool loaded = false;
  String? error;

  int _generation = 0;
  bool _disposed = false;

  Future<void> load({bool silent = false}) async {
    final generation = ++_generation;
    if (!silent || !loaded) {
      loading = true;
      error = null;
      _notify();
    }
    try {
      final response = await api.request('GET', '/projects', protected: true);
      final mine = extractList(response, const [
        'projects',
        'items',
        'results',
      ]).where(_isMine).toList();

      final entries = await Future.wait(
        mine.map((project) async {
          final id = projectId(project);
          try {
            final res = await api.request(
              'GET',
              '/projects/${Uri.encodeComponent(id)}/tasks',
              protected: true,
            );
            final list = extractList(res, const [
              'tasks',
              'items',
              'results',
            ]).map((t) => TaskModel.fromJson({...t, 'projectId': id})).toList();
            return MapEntry(id, list);
          } on ApiException catch (e) {
            // Phiên hết hạn đã được ApiClient xử lý; các lỗi khác chỉ làm
            // dự án này tạm thời không có công việc.
            if (e.status == 401) rethrow;
            return MapEntry(id, <TaskModel>[]);
          }
        }),
      );
      if (generation != _generation) return;
      projects = mine;
      _tasks
        ..clear()
        ..addEntries(entries);
      error = null;
    } catch (e) {
      if (generation != _generation) return;
      error = e.toString();
    } finally {
      if (generation == _generation) {
        loading = false;
        loaded = true;
        _notify();
      }
    }
  }

  // ---- Đọc dữ liệu -------------------------------------------------------

  String projectId(Map<String, dynamic> p) =>
      stringValue(p, const ['id', '_id', 'projectId', 'project_id']);

  Map<String, dynamic>? projectById(String id) {
    for (final p in projects) {
      if (projectId(p) == id) return p;
    }
    return null;
  }

  List<TaskModel> tasksForProject(String id) => _tasks[id] ?? const [];

  List<TaskModel> get allTasks => [for (final list in _tasks.values) ...list];

  String taskId(TaskModel task) => task.id;

  String taskStatus(TaskModel task) => task.status;

  String assigneeId(TaskModel task) => task.assigneeId;

  List<TaskModel> tasksForCurrentUser() =>
      allTasks.where((t) => assigneeId(t) == userId).toList();

  List<TaskModel> tasksToReview() => allTasks
      .where(
        (t) =>
            roleInProject(t.projectId) == 'Leader' &&
            taskStatus(t) == 'Chờ duyệt',
      )
      .toList();

  int progressOf(String id) {
    final list = tasksForProject(id);
    if (list.isEmpty) return 0;
    final done = list.where((t) => taskStatus(t) == 'Hoàn thành').length;
    return ((done / list.length) * 100).round();
  }

  List<Map<String, dynamic>> _membersOf(Map<String, dynamic> p) =>
      asMapList(firstValue(p, const ['members', 'projectMembers']));

  List<Map<String, dynamic>> membersForProject(String id) {
    final project = projectById(id);
    if (project == null) return const [];
    final members = _membersOf(project);
    final leaderId = stringValue(project, const [
      'leaderId',
      'leader_id',
      'ownerId',
    ]);
    if (leaderId.isNotEmpty &&
        !members.any(
          (member) =>
              stringValue(member, const ['id', 'userId', 'user_id']) ==
              leaderId,
        )) {
      members.insert(0, {
        'id': leaderId,
        'displayName': stringValue(project, const [
          'leaderName',
          'ownerName',
        ], fallback: 'Leader'),
        'avatarUrl': stringValue(project, const ['leaderAvatarUrl']),
        'role': 'Leader',
      });
    }
    return members;
  }

  List<MemberTaskStats> contributionStats(String id) {
    final tasks = tasksForProject(id);
    return membersForProject(id).map((member) {
      final memberId = stringValue(member, const [
        'id',
        '_id',
        'userId',
        'user_id',
      ]);
      final assigned = tasks
          .where((task) => task.assigneeId == memberId)
          .toList();
      return MemberTaskStats(
        userId: memberId,
        name: stringValue(member, const [
          'displayName',
          'name',
          'fullName',
          'username',
        ], fallback: 'Thành viên'),
        role: stringValue(
          member,
          const ['role'],
          fallback:
              memberId == stringValue(projectById(id) ?? {}, const ['leaderId'])
              ? 'Leader'
              : 'Member',
        ),
        avatarUrl: stringValue(member, const ['avatarUrl', 'photoUrl']),
        assigned: assigned.length,
        completed: assigned.where((task) => task.isDone).length,
      );
    }).toList()..sort(
      (a, b) => b.completionPercent.compareTo(a.completionPercent),
    );
  }

  int memberCount(Map<String, dynamic> p) {
    final raw = firstValue(p, const ['members', 'projectMembers']);
    if (raw is List) return raw.length;
    final n = firstValue(p, const ['memberCount', 'membersCount']);
    return n is num ? n.toInt() : int.tryParse('$n') ?? 0;
  }

  String roleInProject(String id) {
    final p = projectById(id);
    if (p == null) return 'Member';
    final role = stringValue(p, const ['myRole', 'role', 'currentUserRole']);
    if (role.isNotEmpty) {
      return const ['leader', 'owner', 'admin'].contains(role.toLowerCase())
          ? 'Leader'
          : 'Member';
    }
    final leader = stringValue(p, const ['leaderId', 'leader_id', 'ownerId']);
    return leader == userId ? 'Leader' : 'Member';
  }

  String assigneeName(TaskModel task) {
    if (task.assigneeName.isNotEmpty) return task.assigneeName;
    if (task.assigneeId == userId) return 'Bạn';
    for (final member in membersForProject(task.projectId)) {
      if (stringValue(member, const ['id', '_id', 'userId', 'user_id']) ==
          task.assigneeId) {
        return stringValue(member, const [
          'displayName',
          'name',
          'fullName',
          'username',
        ], fallback: 'Thành viên');
      }
    }
    return 'Thành viên';
  }

  Future<String> createProject(Map<String, dynamic> fields) async {
    final response = await api.request(
      'POST',
      '/projects',
      body: fields,
      protected: true,
    );
    await load(silent: true);
    final project = asMap(response['project']) ?? response;
    return stringValue(project, const ['id', '_id', 'projectId']);
  }

  Future<void> addProjectMember(String projectId, String username) => _act(
    () => api.request(
      'POST',
      '/projects/${Uri.encodeComponent(projectId)}/members',
      body: {'username': username.trim()},
      protected: true,
    ),
  );

  /// Chỉ giữ dự án mà tài khoản là thành viên (phòng khi API trả rộng hơn).
  bool _isMine(Map<String, dynamic> p) {
    if (stringValue(p, const [
      'myRole',
      'role',
      'currentUserRole',
    ]).isNotEmpty) {
      return true;
    }
    if (stringValue(p, const ['leaderId', 'leader_id', 'ownerId']) == userId) {
      return true;
    }
    final raw = firstValue(p, const ['members', 'projectMembers']);
    if (raw is! List || raw.isEmpty) return true;
    return raw.any((m) {
      final map = asMap(m);
      final id = map == null
          ? m.toString()
          : stringValue(map, const ['id', '_id', 'userId', 'user_id']);
      return id == userId;
    });
  }

  // ---- Thao tác công việc ------------------------------------------------

  Future<void> createTask(String projectId, Map<String, dynamic> fields) =>
      _act(
        () => api.request(
          'POST',
          '/projects/${Uri.encodeComponent(projectId)}/tasks',
          body: fields,
          protected: true,
        ),
      );

  Future<void> updateTask(TaskModel task, Map<String, dynamic> fields) => _act(
    () => api.request(
      'PATCH',
      _taskPath(task, ''),
      body: fields,
      protected: true,
    ),
  );

  Future<void> startTask(TaskModel task) => _act(
    () => api.request(
      'PATCH',
      _taskPath(task, 'start'),
      body: const {},
      protected: true,
    ),
  );

  Future<void> submitTask(TaskModel task, String outputLink) => _act(
    () => api.request(
      'POST',
      _taskPath(task, 'submit'),
      body: {'outputLink': outputLink},
      protected: true,
    ),
  );

  Future<void> approveTask(TaskModel task) => _act(
    () => api.request(
      'POST',
      _taskPath(task, 'approve'),
      body: const {},
      protected: true,
    ),
  );

  Future<void> requestChanges(TaskModel task, String comment) => _act(
    () => api.request(
      'POST',
      _taskPath(task, 'request-changes'),
      body: {'comment': comment},
      protected: true,
    ),
  );

  Future<void> requestDeadlineExtension(
    TaskModel task,
    DateTime dueDate,
    String reason,
  ) => _act(
    () => api.request(
      'POST',
      '${_taskPath(task, '')}/deadline-requests',
      body: {'requestedDueDate': dueDate.toIso8601String(), 'reason': reason},
      protected: true,
    ),
  );

  Future<void> reviewDeadlineRequest(
    TaskModel task, {
    required bool approve,
  }) => _act(
    () => api.request(
      'POST',
      '${_taskPath(task, '')}/deadline-requests/${approve ? 'approve' : 'reject'}',
      body: const {},
      protected: true,
    ),
  );

  String _taskPath(TaskModel task, String action) {
    final id = taskId(task);
    if (id.isEmpty) throw const ApiException('Công việc không có ID hợp lệ.');
    final base = '/tasks/${Uri.encodeComponent(id)}';
    return action.isEmpty ? base : '$base/$action';
  }

  Future<void> _act(Future<Map<String, dynamic>> Function() action) async {
    await action();
    await load(silent: true);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
