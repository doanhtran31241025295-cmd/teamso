import 'package:flutter/material.dart';

import '../../controllers/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../controllers/projects_controller.dart';
import '../../widgets/project_form_dialog.dart';
import 'project_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session, required this.projects});
  final SessionController session;
  final ProjectsController projects;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ProjectsController get _data => widget.projects;
  final TextEditingController _searchController = TextEditingController();

  String _filter = 'Tất cả';

  List<Map<String, dynamic>> get _filteredProjects {
    final query = _searchController.text.trim().toLowerCase();

    return _data.projects.where((project) {
      final name = project['name']?.toString() ?? '';
      final tag = project['tag']?.toString() ?? '';
      final role = _data.roleInProject(_data.projectId(project));

      final matchesSearch =
          name.toLowerCase().contains(query) ||
          tag.toLowerCase().contains(query);

      final matchesRole =
          _filter == 'Tất cả' ||
          (_filter == 'Tôi là leader' && role == 'Leader') ||
          (_filter == 'Tôi là member' && role == 'Member');

      return matchesSearch && matchesRole;
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _projectColor(Map<String, dynamic> project) {
    final value = project['color'];

    if (value is Color) return value;
    if (value is int) return Color(value);

    switch (project['tag']?.toString()) {
      case 'Mobile':
      case 'Mobile App':
        return AppColors.green;
      case 'Marketing':
        return AppColors.pink;
      case 'Research':
        return AppColors.yellow;
      default:
        return AppColors.purple;
    }
  }

  IconData _projectIcon(Map<String, dynamic> project) {
    switch (project['tag']?.toString()) {
      case 'Mobile':
      case 'Mobile App':
        return Icons.phone_android_rounded;
      case 'Marketing':
        return Icons.campaign_outlined;
      case 'Research':
        return Icons.lightbulb_outline_rounded;
      default:
        return Icons.dashboard_customize_outlined;
    }
  }

  int _projectProgress(String projectId) => _data.progressOf(projectId);

  int _projectMemberCount(Map<String, dynamic> project) =>
      _data.memberCount(project);

  String _displayName() {
    final name = widget.session.user?.name.trim() ?? '';
    return name.isEmpty ? 'bạn' : name;
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 11) return 'Chào buổi sáng';
    if (hour < 14) return 'Chào buổi trưa';
    if (hour < 18) return 'Chào buổi chiều';
    return 'Chào buổi tối';
  }

  void _openProject(Map<String, dynamic> project) {
    final projectId = _data.projectId(project);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectDetailScreen(
          projectId: projectId,
          apiClient: widget.session.api,
          currentUserId: widget.session.user?.id,
        ),
      ),
    ).then((_) => _data.load(silent: true));
  }

  Future<void> _createProject() async {
    final fields = await showProjectFormDialog(context);
    if (fields == null || !mounted) return;
    try {
      await _data.createProject(fields);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  void _showProjectOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bạn muốn làm gì?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(
                    Icons.add_box_outlined,
                    color: AppColors.darkPurple,
                  ),
                  title: const Text('Tạo project mới'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _createProject();
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.group_add_outlined,
                    color: AppColors.green,
                  ),
                  title: const Text('Tham gia project'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Chức năng tham gia dự án sẽ được bổ sung sau.',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label) {
    final selected = _filter == label;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: AppColors.darkPurple,
        backgroundColor: Colors.white,
        side: BorderSide(
          color: selected ? AppColors.darkPurple : AppColors.border,
        ),
        labelStyle: TextStyle(
          fontSize: 12,
          color: selected ? Colors.white : AppColors.textPrimary,
        ),
        onSelected: (_) {
          setState(() => _filter = label);
        },
      ),
    );
  }

  Widget _smallTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color == AppColors.yellow ? AppColors.darkPurple : color,
        ),
      ),
    );
  }

  Widget _buildProjectCard(Map<String, dynamic> project) {
    final projectId = _data.projectId(project);
    final name = project['name']?.toString() ?? 'Dự án';
    final tag = project['tag']?.toString() ?? 'Project';
    final role = _data.roleInProject(projectId);
    final isLeader = role == 'Leader';
    final color = _projectColor(project);
    final progress = _projectProgress(projectId);
    final memberCount = _projectMemberCount(project);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openProject(project),
      child: Card(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_projectIcon(project), color: color, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _smallTag(
                              role,
                              isLeader ? AppColors.purple : AppColors.green,
                            ),
                            _smallTag(tag, color),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: progress / 100,
                        minHeight: 7,
                        backgroundColor: AppColors.border,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.green,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$progress%',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.people_outline,
                    size: 17,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$memberCount',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProjectsSection() {
    if (!_data.loaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_data.error != null && _data.projects.isEmpty) {
      return _stateMessage(
        icon: Icons.cloud_off_outlined,
        title: _data.error!,
        action: TextButton.icon(
          onPressed: _data.load,
          icon: const Icon(Icons.refresh),
          label: const Text('Thử lại'),
        ),
      );
    }
    if (_data.projects.isEmpty) {
      return _stateMessage(
        icon: Icons.folder_open_rounded,
        title: 'Chưa có dự án',
        subtitle: 'Bạn chưa tham gia dự án nào.',
      );
    }
    final projects = _filteredProjects;
    if (projects.isEmpty) {
      return _stateMessage(
        icon: Icons.search_off,
        title: 'Không tìm thấy dự án phù hợp',
      );
    }
    return Column(
      children: [
        for (final project in projects)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildProjectCard(project),
          ),
      ],
    );
  }

  Widget _stateMessage({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(icon, size: 44, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 8), action],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _data,
    builder: (context, _) => _buildPage(context),
  );

  Widget _buildPage(BuildContext context) {
    final count = _data.projects.length;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _data.load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
            children: [
              Text(
                '${_greeting()}, ${_displayName()}! 👋',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Cùng nhau tạo nên những dự án tuyệt vời!',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Tìm kiếm dự án...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close),
                        ),
                  filled: true,
                  fillColor: AppColors.pageBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('Tất cả'),
                    _buildFilterChip('Tôi là leader'),
                    _buildFilterChip('Tôi là member'),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Dự án của bạn',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '$count dự án',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildProjectsSection(),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showProjectOptions,
        backgroundColor: AppColors.darkPurple,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}
