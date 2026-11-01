import 'package:flutter/material.dart';

import '../../controllers/projects_controller.dart';
import '../../controllers/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../chat/chat_screen.dart';
import '../home/home_screen.dart';
import '../notify/notification_screen.dart';
import '../profile/profile_screen.dart';
import '../tasks/task_board_screen.dart';
import '../workspace/workspace_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, required this.session});
  final SessionController session;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // Một nguồn dữ liệu API dùng chung cho Home và Task Board.
  late final ProjectsController _projects = ProjectsController(
    widget.session.api,
    widget.session.user!.id,
  );

  late final List<Widget> _screens = [
    HomeScreen(session: widget.session, projects: _projects),
    TaskBoardScreen(projects: _projects),
    WorkspaceScreen(api: widget.session.api, projects: _projects),
    ChatScreen(session: widget.session),
    const NotificationScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _projects.load();
  }

  @override
  void dispose() {
    _projects.dispose();
    super.dispose();
  }

  final List<String> _titles = const [
    'TeamUp',
    'Task Board',
    'Workspace',
    'Chat',
    'Thông báo',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titles[_currentIndex],
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
          IconButton(
            tooltip: 'Hồ sơ cá nhân',
            onPressed: () async {
              final goHome = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => ProfileScreen(session: widget.session),
                ),
              );
              if (mounted && goHome == true) {
                setState(() => _currentIndex = 0);
              }
            },
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        backgroundColor: Colors.white,
        indicatorColor: AppColors.purple.withValues(alpha: 0.18),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Task Board',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Workspace',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none),
            selectedIcon: Icon(Icons.notifications),
            label: 'Notify',
          ),
        ],
      ),
    );
  }
}
