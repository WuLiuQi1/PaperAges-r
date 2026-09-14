import 'package:flutter/material.dart';

import '../data/local_source_repository.dart';
import '../open_reading/book_sources/source_engine/source_login_ui.dart';
import '../domain/open_reading_adapter.dart';
import '../domain/source_engine.dart';

class SourceLoginScreen extends StatefulWidget {
  const SourceLoginScreen({super.key, required this.source});
  final StoredBookSource source;

  @override
  State<SourceLoginScreen> createState() => _SourceLoginScreenState();
}

class _SourceLoginScreenState extends State<SourceLoginScreen> {
  late final OpenReadingSourceAdapter _adapter = OpenReadingSourceAdapter(
    limits: const SourceEngineLimits(),
  );
  late final Future<List<SourceLoginField>> _fields = _adapter.loadLoginFields(
    widget.source.configuration,
  );
  final Map<String, TextEditingController> _controllers = {};
  var _saving = false;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _adapter.close();
    super.dispose();
  }

  Future<void> _login(List<SourceLoginField> fields) async {
    setState(() => _saving = true);
    try {
      await _adapter.login(widget.source.configuration, {
        for (final field in fields)
          if (field.isInput) field.name: _controllers[field.name]!.text,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('登录信息已保存')));
      Navigator.of(context).pop();
    } on SourceEngineFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('登录失败：${error.message}')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.source.name} · 登录'),
      actions: [
        IconButton(
          tooltip: '清除登录信息',
          onPressed: _saving
              ? null
              : () async {
                  await _adapter.clearLogin(widget.source.configuration);
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                },
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: FutureBuilder<List<SourceLoginField>>(
      future: _fields,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('无法加载登录表单：${snapshot.error}'));
        }
        final fields = snapshot.data ?? const <SourceLoginField>[];
        if (fields.isEmpty) return const Center(child: Text('该书源没有可用登录表单'));
        for (final field in fields.where((field) => field.isInput)) {
          _controllers.putIfAbsent(
            field.name,
            () => TextEditingController(text: field.defaultValue),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final field in fields.where((field) => field.isInput))
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: TextField(
                  controller: _controllers[field.name],
                  obscureText: field.type == 'password',
                  decoration: InputDecoration(
                    labelText: field.viewName ?? field.name,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _saving ? null : () => _login(fields),
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('登录'),
            ),
          ],
        );
      },
    ),
  );
}
