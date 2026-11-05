import 'chat_panel.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/accent_surface.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/chat_palette.dart';
import '../../utils/chat_time.dart';
import '../../widgets/app_widgets.dart';

/// Only receives the signed-in user's real memberships; never supplies demo rooms.
class ProjectChatList extends StatefulWidget {
  const ProjectChatList({
    super.key,
    required this.projects,
    required this.previews,
    required this.onSelected,
    this.loading = false,
    this.error,
    this.previewErrors = const {},
    this.currentUserId = '',
    this.unreadCounts = const {},
    this.onCreate,
    this.creating = false,
  });
  final VoidCallback? onCreate;
  final bool creating;
  final List<Map<String, dynamic>> projects;
  final Map<String, Map<String, dynamic>?> previews;
  final Set<String> previewErrors;
  final ValueChanged<String> onSelected;
  final bool loading;
  final String? error;
  final String currentUserId;
  final Map<String, int> unreadCounts;
  @override
  State<ProjectChatList> createState() => _ProjectChatListState();
}

enum _ChatFilter { all, direct, project }

class _ProjectChatListState extends State<ProjectChatList> {
  String _query = '';
  _ChatFilter _filter = _ChatFilter.all;
  DateTime? _date(dynamic value) {
    if (value is Timestamp) return value.toDate().toLocal();
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  }

  String _time(DateTime? date) =>
      date == null ? '' : conversationTimeLabel(date);

  DateTime _sortDate(Map<String, dynamic> project) =>
      _date(widget.previews[project['id'].toString()]?['createdAt']) ??
      _date(project['createdAt']) ??
      DateTime.fromMillisecondsSinceEpoch(0);
  String _preview(String id) {
    if (widget.previewErrors.contains(id)) return 'Không tải được tin nhắn';
    if (!widget.previews.containsKey(id)) return 'Đang tải tin nhắn…';
    final message = widget.previews[id];
    if (message == null) return 'Chưa có tin nhắn';
    final text = (message['content'] ?? '').toString().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    if (message['kind'] != 'user') return text;
    final sender = message['senderId'] == widget.currentUserId
        ? 'Bạn'
        : (message['senderName'] ?? 'Thành viên').toString();
    return '$sender: $text';
  }

  @override
  Widget build(BuildContext context) {
    final Widget? placeholder;
    if (widget.loading && widget.projects.isEmpty) {
      placeholder = const Center(child: CircularProgressIndicator());
    } else if (widget.error != null && widget.projects.isEmpty) {
      placeholder = EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Không tải được dự án',
        message: widget.error,
      );
    } else if (widget.projects.isEmpty) {
      placeholder = const EmptyState(
        icon: Icons.forum_outlined,
        title: 'Chưa có cuộc trò chuyện',
        message:
            'Bấm dấu + để nhắn riêng hoặc chọn một dự án để trò chuyện cùng nhóm.',
      );
    } else {
      placeholder = null;
    }
    final projects =
        widget.projects
            .where((project) {
              final isDirect = project['id'].toString().startsWith('direct:');
              if (_filter == _ChatFilter.direct && !isDirect) return false;
              if (_filter == _ChatFilter.project && isDirect) return false;
              return (project['name'] ?? '')
                  .toString()
                  .toLowerCase()
                  .contains(_query.trim().toLowerCase());
            })
            .toList()
          ..sort((a, b) {
            final byTime = _sortDate(b).compareTo(_sortDate(a));
            return byTime != 0
                ? byTime
                : (a['name'] ?? '').toString().compareTo(
                    (b['name'] ?? '').toString(),
                  );
          });
    return ChatPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Tìm cuộc trò chuyện…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  tooltip: 'Trò chuyện mới',
                  onPressed: widget.creating ? null : widget.onCreate,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.darkPurple,
                    foregroundColor: Colors.white,
                    fixedSize: const Size(48, 48),
                  ),
                  icon: widget.creating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add_rounded, size: 26),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (f, label) in [
                  (_ChatFilter.all, 'Tất cả'),
                  (_ChatFilter.direct, 'Cá nhân'),
                  (_ChatFilter.project, 'Dự án'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _filter == f,
                    showCheckmark: false,
                    selectedColor: AppColors.darkPurple,
                    backgroundColor: Colors.white,
                    side: BorderSide.none,
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _filter == f
                          ? Colors.white
                          : AppColors.darkPurple,
                    ),
                    onSelected: (_) => setState(() => _filter = f),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
            child: Row(
              children: [
                const Icon(
                  Icons.expand_more_rounded,
                  size: 20,
                  color: AppColors.darkPurple,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Cuộc trò chuyện',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkPurple,
                    ),
                  ),
                ),
                Text(
                  '${widget.projects.length}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (widget.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                widget.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: placeholder != null
                ? placeholder
                : projects.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Không tìm thấy cuộc trò chuyện',
                    message: 'Thử đổi bộ lọc hoặc tìm bằng tên khác.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: projects.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final project = projects[index];
                      final id = project['id'].toString();
                      final latest = widget.previews[id];
                      final (tone, accent) = chatRoomColors(id);
                      return Card(
                        color: tone,
                        shape: AccentCardBorder(accent: accent),
                        clipBehavior: Clip.antiAlias,
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 5,
                        ),
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: pastelGradient(tone),
                          ),
                          child: ListTile(
                            key: ValueKey('chat-project-$id'),
                            onTap: () => widget.onSelected(id),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            leading: CircleAvatar(
                              radius: 27,
                              backgroundColor: Colors.white.withValues(
                                alpha: .8,
                              ),
                              child: Icon(
                                id.startsWith('direct:')
                                    ? Icons.person_outline_rounded
                                    : Icons.groups_outlined,
                                color: accent,
                                size: 26,
                              ),
                            ),
                            title: Text(
                              (project['name'] ?? 'Dự án').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 7),
                              child: Text(
                                _preview(id),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _time(_date(latest?['createdAt'])),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                if ((widget.unreadCounts[id] ?? 0) > 0) ...[
                                  const SizedBox(height: 6),
                                  Badge(
                                    label: Text(
                                      '${widget.unreadCounts[id]! > 99 ? '99+' : widget.unreadCounts[id]}',
                                    ),
                                    backgroundColor: accent,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
