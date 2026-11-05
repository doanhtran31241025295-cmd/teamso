import '../core/theme/accent_surface.dart';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

// Giữ lại tên cũ để các màn hình hiện có (profile...) tự đồng bộ theo theme.
const olive = AppColors.darkPurple;
const ink = AppColors.textPrimary;

class Frame extends StatelessWidget {
  const Frame({
    super.key,
    required this.child,
    this.appBar,
    this.bottomNavigationBar,
  });
  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: appBar,
    bottomNavigationBar: bottomNavigationBar,
    body: DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SafeArea(child: child),
        ),
      ),
    ),
  );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 52,
    child: FilledButton(
      onPressed: loading ? null : onPressed,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: loading
            ? const SizedBox(
                key: ValueKey('loading'),
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : Row(
                key: const ValueKey('label'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(label),
                ],
              ),
      ),
    ),
  );
}

/// Khối thông báo lỗi nội tuyến (thay cho Text đỏ trơ trọi).
class InlineError extends StatelessWidget {
  const InlineError(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: AccentBoxDecoration(
        accent: AppColors.danger,
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 20,
            color: AppColors.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Avatar có chữ cái đầu khi chưa có ảnh / ảnh lỗi.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    this.large = false,
    this.url = '',
    this.name = '',
    this.radius,
  });
  final bool large;
  final String url, name;
  final double? radius;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    if (parts.isEmpty) return '';
    final list = parts.toList();
    final first = list.first.characters.first;
    final last = list.length > 1 ? list.last.characters.first : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final r = radius ?? (large ? 45.0 : 30.0);
    final fallback = _initials.isEmpty
        ? Icon(
            Icons.person_outline_rounded,
            size: r * 1.2,
            color: AppColors.darkPurple,
          )
        : Text(
            _initials,
            style: TextStyle(
              fontSize: r * 0.7,
              fontWeight: FontWeight.w700,
              color: AppColors.darkPurple,
            ),
          );
    return CircleAvatar(
      radius: r,
      backgroundColor: AppColors.purpleSoft,
      child: ClipOval(
        child: url.isEmpty
            ? fallback
            : Image.network(
                url,
                width: r * 2,
                height: r * 2,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : fallback,
                errorBuilder: (_, error, stack) => fallback,
              ),
      ),
    );
  }
}
