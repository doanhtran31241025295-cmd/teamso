import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../services/app_services.dart';
import '../../services/service_errors.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/auth_widgets.dart';
import '../home/project_detail_screen.dart';
import 'qr_scan_screen.dart';

/// Tham gia project bằng mã nhập tay hoặc quét QR. Backend kiểm tra mã tồn
/// tại, chặn tham gia trùng và ghi memberIds / members / projectMemberships.
class JoinProjectScreen extends StatefulWidget {
  const JoinProjectScreen({super.key, this.initialCode});

  /// Mã điền sẵn (ví dụ khi mở từ deep link).
  final String? initialCode;

  @override
  State<JoinProjectScreen> createState() => _JoinProjectScreenState();
}

class _JoinProjectScreenState extends State<JoinProjectScreen> {
  final _code = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCode;
    if (initial != null) _code.text = extractJoinCode(initial);
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// Nhận mã trần (8K2P9XQ1) hoặc đường dẫn chứa mã
  /// (teamup://join/8K2P9XQ1, https://.../join?code=8K2P9XQ1).
  static String extractJoinCode(String raw) {
    final text = raw.trim();
    final uri = Uri.tryParse(text);
    if (uri != null && uri.hasScheme) {
      final q = uri.queryParameters['code'] ?? uri.queryParameters['joinCode'];
      if (q != null && q.isNotEmpty) return q.trim().toUpperCase();
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) return segments.last.toUpperCase();
      if (uri.scheme == 'teamup' &&
          uri.pathSegments.isEmpty &&
          uri.host.isNotEmpty &&
          uri.host != 'join') {
        return uri.host.toUpperCase();
      }
    }
    return text.toUpperCase();
  }

  Future<void> _scan() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (raw == null || !mounted) return;
    final code = extractJoinCode(raw);
    _code.text = code;
    await _join();
  }

  Future<void> _join() async {
    if (_loading) return;
    final code = extractJoinCode(_code.text);
    if (!RegExp(r'^[A-Z0-9]{8}$').hasMatch(code)) {
      setState(() => _error = 'Mã tham gia gồm 8 ký tự chữ và số.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final project = await AppServices.instance.projects.join(code);
      if (!mounted) return;
      showAppSnack(context, 'Bạn đã tham gia dự án ${project['name']}');
      final projectId = project['id']?.toString() ?? '';
      if (projectId.isEmpty) {
        Navigator.pop(context, project);
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ProjectDetailScreen(projectId: projectId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tham gia dự án')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            const PageIntro(
              title: 'Cùng tham gia với nhóm',
              description: 'Kết nối với dự án bằng mã mời hoặc quét QR.',
              icon: Icons.group_add_outlined,
            ),
            const Text(
              'Nhập mã tham gia do Leader chia sẻ, hoặc quét mã QR của dự án.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _code,
              enabled: !_loading,
              autofocus: true,
              maxLength: 8,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _join(),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                TextInputFormatter.withFunction(
                  (old, value) =>
                      value.copyWith(text: value.text.toUpperCase()),
                ),
              ],
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
              ),
              decoration: const InputDecoration(
                labelText: 'Mã tham gia',
                hintText: '8K2P9XQ1',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              InlineError(_error!),
            ],
            const SizedBox(height: 20),
            PrimaryButton(
              'Tham gia',
              icon: Icons.group_add_outlined,
              loading: _loading,
              onPressed: _join,
            ),
            const SizedBox(height: 16),
            Row(
              children: const [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('hoặc'),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loading ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Quét mã QR'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
