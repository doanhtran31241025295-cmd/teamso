import 'package:flutter/material.dart';

import 'app_colors.dart';

// Share a room's colors between its list card and its open conversation.
final _roomIndices = <String, int>{};
(Color, Color) chatRoomColors(String id) {
  const palette = [
    AppColors.workspaceDocument,
    AppColors.workspaceVote,
    AppColors.workspaceMeeting,
  ];
  final index =
      _roomIndices.putIfAbsent(id, () => _roomIndices.length) % palette.length;
  return palette[index];
}
