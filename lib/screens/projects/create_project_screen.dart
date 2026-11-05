import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../services/app_services.dart';
import '../../services/service_errors.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/auth_widgets.dart';
import '../home/project_detail_screen.dart';

/// Màn hình tạo project. Việc sinh joinCode, gán leader, khởi tạo tiến độ
/// đều do backend (POST /api/projects) thực hiện; UID lấy từ ID token.
class CreateProjectScreen extends StatefulWidget {
  const CreateProjectScreen({super.key});

  @override
  State<CreateProjectScreen> createState() => _CreateProjectScreenState();
}

class _CreateProjectScreenState extends State<CreateProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _coverUrl = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _coverUrl.dispose();
    super.dispose();
  }

  String _fmt(DateTime? d) => d == null
      ? 'Chọn ngày'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = (isStart ? _startDate : _endDate) ?? _startDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = null;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (_loading || !(_formKey.currentState?.validate() ?? false)) return;
    if (_startDate != null &&
        _endDate != null &&
        _endDate!.isBefore(_startDate!)) {
      showAppSnack(
        context,
        'Ngày kết thúc phải sau ngày bắt đầu.',
        error: true,
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final project = await AppServices.instance.projects.create(
        name: _name.text,
        description: _description.text,
        coverUrl: _coverUrl.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
      );
      if (!mounted) return;
      final projectId = project['id']?.toString() ?? '';
      showAppSnack(
        context,
        'Đã tạo "${project['name']}". Mã tham gia: ${project['joinCode']}',
      );
      if (projectId.isEmpty) {
        Navigator.pop(context, project);
        return;
      }
      // Thay màn hình tạo bằng màn hình dự án để nút Back quay về Home.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ProjectDetailScreen(projectId: projectId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showAppSnack(context, errorText(e), error: true);
    }
  }

  Widget _dateField(String label, DateTime? value, bool isStart) => Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _loading ? null : () => _pickDate(isStart: isStart),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(
          _fmt(value),
          style: TextStyle(
            color: value == null
                ? AppColors.textSecondary
                : AppColors.textPrimary,
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tạo dự án mới')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              TextFormField(
                controller: _name,
                enabled: !_loading,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Tên dự án *',
                  prefixIcon: Icon(Icons.folder_outlined),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Vui lòng nhập tên dự án'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _description,
                enabled: !_loading,
                minLines: 3,
                maxLines: 5,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Mô tả dự án',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _coverUrl,
                enabled: !_loading,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Ảnh bìa (đường dẫn, không bắt buộc)',
                  prefixIcon: Icon(Icons.image_outlined),
                ),
                validator: (v) {
                  final s = v?.trim() ?? '';
                  if (s.isEmpty) return null;
                  final uri = Uri.tryParse(s);
                  return (uri != null && uri.hasScheme && uri.host.isNotEmpty)
                      ? null
                      : 'Đường dẫn ảnh không hợp lệ';
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _dateField('Ngày bắt đầu', _startDate, true),
                  const SizedBox(width: 12),
                  _dateField('Ngày kết thúc', _endDate, false),
                ],
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                'Tạo dự án',
                icon: Icons.check_rounded,
                loading: _loading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
