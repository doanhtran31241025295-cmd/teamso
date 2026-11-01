import 'package:flutter/material.dart';

import '../../controllers/projects_controller.dart';
import '../../core/utils/api_json.dart';
import '../../services/api_client.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key, required this.api, required this.projects});

  final ApiClient api;
  final ProjectsController projects;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  static const _defaultVoteOptions = [
    'Thứ Sáu - 19:00',
    'Thứ Bảy - 14:00',
    'Chủ Nhật - 09:00',
  ];

  String? _projectId;
  List<Map<String, dynamic>> _documents = [];
  List<Map<String, dynamic>> _meetings = [];
  List<Map<String, dynamic>> _votes = [];
  bool _loading = false;
  String? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.projects.addListener(_onProjectsChanged);
    _onProjectsChanged();
  }

  @override
  void dispose() {
    widget.projects.removeListener(_onProjectsChanged);
    super.dispose();
  }

  void _onProjectsChanged() {
    final projects = widget.projects.projects;
    if (projects.isEmpty) {
      if (_projectId != null) {
        setState(() {
          _projectId = null;
          _documents = [];
          _meetings = [];
          _votes = [];
          _error = null;
        });
      } else if (mounted) {
        setState(() {});
      }
      return;
    }

    final hasSelectedProject = projects.any(
      (project) => widget.projects.projectId(project) == _projectId,
    );
    if (!hasSelectedProject) {
      final nextProjectId = widget.projects.projectId(projects.first);
      setState(() {
        _projectId = nextProjectId;
        _documents = [];
        _meetings = [];
        _votes = [];
      });
      _loadWorkspace(nextProjectId);
    } else if (mounted) {
      setState(() {});
    }
  }

  String get _workspacePath =>
      '/projects/${Uri.encodeComponent(_projectId!)}/workspace';

  Future<void> _loadWorkspace(String projectId) async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.api.request(
        'GET',
        '/projects/${Uri.encodeComponent(projectId)}/workspace',
        protected: true,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _documents = asMapList(response['documents']);
        _meetings = asMapList(response['meetings']);
        _votes = asMapList(response['votes']);
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refreshWorkspace() async {
    final projectId = _projectId;
    if (projectId != null) await _loadWorkspace(projectId);
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    try {
      await action();
      if (successMessage != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<String?> _showInputDialog({
    required String title,
    required String label,
  }) async {
    final controller = TextEditingController();

    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (value) {
              final text = value.trim();
              if (text.isNotEmpty) Navigator.pop(dialogContext, text);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) Navigator.pop(dialogContext, value);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _addDocument() async {
    final title = await _showInputDialog(
      title: 'Thêm tài liệu',
      label: 'Tên tài liệu hoặc đường dẫn',
    );
    if (!mounted || title == null) return;

    await _runAction(() async {
      await widget.api.request(
        'POST',
        '$_workspacePath/documents',
        body: {'title': title},
        protected: true,
      );
      await _loadWorkspace(_projectId!);
    }, successMessage: 'Đã thêm tài liệu.');
  }

  Future<void> _deleteDocument(Map<String, dynamic> document) async {
    final id = stringValue(document, const ['id']);
    await _runAction(() async {
      await widget.api.request(
        'DELETE',
        '$_workspacePath/documents/${Uri.encodeComponent(id)}',
        protected: true,
      );
      await _loadWorkspace(_projectId!);
    }, successMessage: 'Đã xóa tài liệu.');
  }

  Future<void> _addMeeting() async {
    final title = await _showInputDialog(
      title: 'Thêm lịch họp',
      label: 'Tên cuộc họp và thời gian',
    );
    if (!mounted || title == null) return;

    await _runAction(() async {
      await widget.api.request(
        'POST',
        '$_workspacePath/meetings',
        body: {'title': title},
        protected: true,
      );
      await _loadWorkspace(_projectId!);
    }, successMessage: 'Đã thêm lịch họp.');
  }

  Future<void> _deleteMeeting(Map<String, dynamic> meeting) async {
    final id = stringValue(meeting, const ['id']);
    await _runAction(() async {
      await widget.api.request(
        'DELETE',
        '$_workspacePath/meetings/${Uri.encodeComponent(id)}',
        protected: true,
      );
      await _loadWorkspace(_projectId!);
    }, successMessage: 'Đã xóa lịch họp.');
  }

  Future<void> _createVote() async {
    final question = await _showInputDialog(
      title: 'Tạo bình chọn',
      label: 'Nội dung câu hỏi',
    );
    if (!mounted || question == null) return;

    await _runAction(() async {
      await widget.api.request(
        'POST',
        '$_workspacePath/votes',
        body: {'question': question, 'options': _defaultVoteOptions},
        protected: true,
      );
      await _loadWorkspace(_projectId!);
    }, successMessage: 'Đã tạo bình chọn.');
  }

  Future<void> _submitVote(Map<String, dynamic> vote, int optionIndex) async {
    final id = stringValue(vote, const ['id']);
    await _runAction(() async {
      await widget.api.request(
        'POST',
        '$_workspacePath/votes/${Uri.encodeComponent(id)}/vote',
        body: {'optionIndex': optionIndex},
        protected: true,
      );
      await _loadWorkspace(_projectId!);
    }, successMessage: 'Đã ghi nhận bình chọn.');
  }

  String _projectName(Map<String, dynamic> project) =>
      stringValue(project, const ['name', 'title'], fallback: 'Dự án');

  bool _canDelete(Map<String, dynamic> item) {
    return stringValue(item, const ['createdBy']) == widget.projects.userId ||
        (_projectId != null &&
            widget.projects.roleInProject(_projectId!) == 'Leader');
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget child,
    VoidCallback? onAdd,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (onAdd != null)
                  IconButton(
                    tooltip: 'Thêm mới',
                    onPressed: _loading ? null : onAdd,
                    icon: const Icon(Icons.add),
                  ),
              ],
            ),
            const Divider(),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildDocuments() {
    if (_documents.isEmpty) return const Text('Chưa có tài liệu nào.');
    return Column(
      children: [
        for (final document in _documents)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: Text(stringValue(document, const ['title'])),
            subtitle: const Text('Tài liệu nhóm'),
            trailing: _canDelete(document)
                ? IconButton(
                    tooltip: 'Xóa tài liệu',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _loading
                        ? null
                        : () => _deleteDocument(document),
                  )
                : null,
          ),
      ],
    );
  }

  Widget _buildVote(Map<String, dynamic> vote) {
    final options = (vote['options'] as List? ?? const [])
        .map((option) => option.toString())
        .toList();
    final counts = (vote['voteCounts'] as List? ?? const [])
        .map((count) => count is num ? count.toInt() : 0)
        .toList();
    final selected = vote['selectedOption'] is num
        ? (vote['selectedOption'] as num).toInt()
        : null;
    final totalVotes = counts.fold<int>(0, (sum, count) => sum + count);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stringValue(vote, const ['question']),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          RadioGroup<int>(
            groupValue: selected,
            onChanged: (value) {
              if (value != null && selected == null && !_loading) {
                _submitVote(vote, value);
              }
            },
            child: Column(
              children: [
                for (var index = 0; index < options.length; index++)
                  RadioListTile<int>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(options[index]),
                    subtitle: Text(
                      '${index < counts.length ? counts[index] : 0} phiếu',
                    ),
                    value: index,
                    enabled: selected == null && !_loading,
                  ),
              ],
            ),
          ),
          Text('Tổng số phiếu: $totalVotes'),
        ],
      ),
    );
  }

  Widget _buildVotes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_votes.isEmpty) const Text('Chưa có bình chọn nào.'),
        for (final vote in _votes) _buildVote(vote),
        OutlinedButton.icon(
          onPressed: _loading ? null : _createVote,
          icon: const Icon(Icons.add_chart),
          label: const Text('Tạo bình chọn mới'),
        ),
      ],
    );
  }

  Widget _buildMeetings() {
    if (_meetings.isEmpty) return const Text('Chưa có lịch họp nào.');
    return Column(
      children: [
        for (final meeting in _meetings)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(stringValue(meeting, const ['title'])),
            subtitle: const Text('Lịch họp nhóm'),
            trailing: _canDelete(meeting)
                ? IconButton(
                    tooltip: 'Xóa lịch họp',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _loading ? null : () => _deleteMeeting(meeting),
                  )
                : null,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final projects = widget.projects.projects;
    final hasProject =
        _projectId != null &&
        projects.any(
          (project) => widget.projects.projectId(project) == _projectId,
        );

    return RefreshIndicator(
      onRefresh: _refreshWorkspace,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'TeamUp Workspace',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Không gian tài liệu, bình chọn và lịch họp được chia sẻ '
            'với thành viên dự án.',
          ),
          const SizedBox(height: 16),
          if (projects.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: hasProject ? _projectId : null,
              decoration: const InputDecoration(
                labelText: 'Dự án',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final project in projects)
                  DropdownMenuItem(
                    value: widget.projects.projectId(project),
                    child: Text(_projectName(project)),
                  ),
              ],
              onChanged: _loading
                  ? null
                  : (value) {
                      if (value == null || value == _projectId) return;
                      setState(() {
                        _projectId = value;
                        _documents = [];
                        _meetings = [];
                        _votes = [];
                      });
                      _loadWorkspace(value);
                    },
            ),
          const SizedBox(height: 16),
          if (!widget.projects.loaded && projects.isEmpty)
            const Center(child: CircularProgressIndicator())
          else if (projects.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Bạn cần tham gia một dự án để dùng Workspace.'),
              ),
            )
          else if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    TextButton(
                      onPressed: _projectId == null
                          ? null
                          : () => _loadWorkspace(_projectId!),
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            if (_loading) const LinearProgressIndicator(),
            _buildSection(
              title: 'Tài liệu nhóm',
              icon: Icons.folder_outlined,
              onAdd: _addDocument,
              child: _buildDocuments(),
            ),
            _buildSection(
              title: 'Quick Vote',
              icon: Icons.how_to_vote_outlined,
              child: _buildVotes(),
            ),
            _buildSection(
              title: 'Lịch họp nhóm',
              icon: Icons.groups_outlined,
              onAdd: _addMeeting,
              child: _buildMeetings(),
            ),
          ],
        ],
      ),
    );
  }
}
