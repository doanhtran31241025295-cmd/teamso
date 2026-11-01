import 'package:flutter/material.dart';

Future<Map<String, String>?> showProjectFormDialog(BuildContext context) async {
  final formKey = GlobalKey<FormState>();
  var name = '';
  var tag = '';
  var description = '';
  var rules = '';
  final result = await showDialog<Map<String, String>>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Tạo dự án'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  autofocus: true,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Tên dự án *'),
                  onChanged: (value) => name = value,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Vui lòng nhập tên dự án.'
                      : null,
                ),
                TextFormField(
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Nhãn dự án'),
                  onChanged: (value) => tag = value,
                ),
                TextFormField(
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 4000,
                  decoration: const InputDecoration(labelText: 'Mô tả'),
                  onChanged: (value) => description = value,
                ),
                TextFormField(
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 4000,
                  decoration: const InputDecoration(labelText: 'Quy tắc nhóm'),
                  onChanged: (value) => rules = value,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            Navigator.pop(dialogContext, {
              'name': name.trim(),
              'tag': tag.trim(),
              'description': description.trim(),
              'rules': rules.trim(),
            });
          },
          child: const Text('Tạo dự án'),
        ),
      ],
    ),
  );
  return result;
}
