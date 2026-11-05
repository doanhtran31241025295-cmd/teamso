import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

const chatHeaderColor = AppColors.pageHeader;

/// Rounded content sheet shared by the conversation list and message rooms.
class ChatPanel extends StatelessWidget {
  const ChatPanel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: chatHeaderColor,
    child: Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        color: Colors.white,
      ),
      child: child,
    ),
  );
}
