import 'notify/notification_navigation.dart';

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../widgets/app_navigation_bar.dart';

import 'package:flutter/material.dart';

import '../controllers/session_controller.dart';
import '../core/theme/app_colors.dart';
import '../widgets/auth_widgets.dart';
import 'chat/chat_screen.dart';
import 'home/home_screen.dart';
import 'notify/notification_screen.dart';
import 'profile/profile_screen.dart';
import 'tasks/task_board_screen.dart';
import 'workspace/workspace_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.session});
  final SessionController? session;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  bool _profileOpen = false;
  bool _chatRoomOpen = false;
  final _taskBoardKey = GlobalKey<TaskBoardScreenState>();
  StreamSubscription<RemoteMessage>? _foregroundPush;
  StreamSubscription<RemoteMessage>? _openedPush;

  @override
  void initState() {
    super.initState();
    final push = widget.session?.push;
    if (push == null || !push.supported) return;
    unawaited(push.start());
    _foregroundPush = FirebaseMessaging.onMessage.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.notification?.title ?? 'Bạn có thông báo mới'),
          action: SnackBarAction(
            label: 'Xem',
            onPressed: () => _openPush(message),
          ),
        ),
      );
    });
    _openedPush = FirebaseMessaging.onMessageOpenedApp.listen(_openPush);
    FirebaseMessaging.instance
        .getInitialMessage()
        .then((message) {
          if (message != null && mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _openPush(message);
            });
          }
        })
        .catchError((Object _) {});
  }

  void _openNotificationTask(String projectId, String taskId) {
    _select(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        _taskBoardKey.currentState?.openFromNotification(projectId, taskId);
    });
  }

  void _openPush(RemoteMessage message) {
    final session = widget.session;
    if (!mounted || session == null) return;
    _select(4);
    unawaited(
      NotificationNavigation.open(
        context,
        session,
        message.data,
        onTask: _openNotificationTask,
      ),
    );
  }

  final ValueNotifier<int> _unread = ValueNotifier<int>(0);
  final ValueNotifier<int> _chatUnread = ValueNotifier<int>(0);
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );

  static const _dests = appDestinations;

  List<Widget> get _screens => [
    HomeScreen(userName: widget.session?.user?.name ?? ''),
    TaskBoardScreen(key: _taskBoardKey),
    WorkspaceScreen(session: widget.session),
    ChatScreen(
      onRoomChanged: (open) {
        if (mounted && _chatRoomOpen != open) {
          setState(() => _chatRoomOpen = open);
        }
      },
      active: _currentIndex == 3 && !_profileOpen,
      unread: _chatUnread,
      session: widget.session,
      userName: widget.session?.user?.name ?? '',
    ),
    NotificationScreen(
      session: widget.session,
      unread: _unread,
      onTask: _openNotificationTask,
    ),
  ];

  @override
  void dispose() {
    _foregroundPush?.cancel();
    _openedPush?.cancel();
    _fade.dispose();
    _unread.dispose();
    _chatUnread.dispose();
    super.dispose();
  }

  Future<void> _openProfile() async {
    final session = widget.session;
    if (session == null) return;
    setState(() => _profileOpen = true);
    final tab = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => ProfileScreen(
          session: session,
          selectedTab: _currentIndex,
          unread: _unread,
          chatUnread: _chatUnread,
        ),
      ),
    );
    if (mounted) setState(() => _profileOpen = false);
    if (mounted && tab != null && tab >= 0 && tab < _dests.length) {
      setState(() => _currentIndex = tab);
    }
  }

  void _select(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
    _fade.forward(from: 0);
  }

  Widget _icon(int i, {required bool selected}) => appDestinationIcon(
    i,
    selected: selected,
    unread: _unread,
    chatUnread: _chatUnread,
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final conversationOpen = _currentIndex == 3 && _chatRoomOpen;

    // IndexedStack giữ trạng thái từng tab; hiệu ứng mờ dần chạy bằng controller
    // riêng nên không dựng lại các tab.
    final body = FadeTransition(
      opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOut),
      child: IndexedStack(
        index: _currentIndex,
        children: [
          for (final (index, screen) in _screens.indexed)
            if (index == 1 || index == 2 || index == 4)
              ColoredBox(
                color: AppColors.pageHeader,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  child: screen,
                ),
              )
            else
              screen,
        ],
      ),
    );

    return Scaffold(
      appBar: conversationOpen
          ? null
          : AppBar(
              toolbarHeight: 80,
              backgroundColor: AppColors.pageHeader,
              foregroundColor: Colors.white,
              titleTextStyle: _currentIndex <= 2
                  ? const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    )
                  : null,
              title: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _currentIndex == 0
                    ? Row(
                        key: const ValueKey('home-brand'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 60,
                            height: 60,
                            child: Transform.scale(
                              scale: 1.15,
                              child: ColorFiltered(
                                colorFilter: const ColorFilter.mode(
                                  Colors.white,
                                  BlendMode.srcIn,
                                ),
                                child: Image.asset(
                                  'assets/images/app_logo_transparent.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'TeamUp',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.7,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        key: ValueKey(_currentIndex),
                        children: [
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(
                              _currentIndex == 1
                                  ? Icons.assignment_turned_in_outlined
                                  : _dests[_currentIndex].icon,
                              size: 36,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _dests[_currentIndex].title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.6,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              actions: [
                ListenableBuilder(
                  listenable: widget.session ?? _unread,
                  builder: (context, _) {
                    final u = widget.session?.user;
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Tooltip(
                        message: 'Hồ sơ cá nhân',
                        child: InkResponse(
                          onTap: widget.session == null ? null : _openProfile,
                          radius: 24,
                          child: Avatar(
                            radius: 17,
                            url: u?.avatarUrl ?? '',
                            name: u?.name ?? '',
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
      body: wide && !conversationOpen
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: _select,
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: Colors.white,
                  indicatorColor: AppColors.darkPurple,
                  destinations: [
                    for (var i = 0; i < _dests.length; i++)
                      NavigationRailDestination(
                        icon: _icon(i, selected: false),
                        selectedIcon: _icon(i, selected: true),
                        label: Text(_dests[i].label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: wide || conversationOpen
          ? null
          : AppNavigationBar(
              selectedIndex: _currentIndex,
              onSelected: _select,
              unread: _unread,
              chatUnread: _chatUnread,
            ),
    );
  }
}
