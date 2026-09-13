import 'package:flutter/material.dart';

import '../../reader_document/domain/normalized_text_document.dart';
import '../../reader_layout/presentation/page_turn_spike.dart';
import '../application/text_import_service.dart';
import '../data/file_selector_text_file_picker.dart';

class LocalLibraryScreen extends StatefulWidget {
  const LocalLibraryScreen({super.key, this.importService});

  final TextImportService? importService;

  @override
  State<LocalLibraryScreen> createState() => _LocalLibraryScreenState();
}

class _LocalLibraryScreenState extends State<LocalLibraryScreen> {
  late final TextImportService _importService =
      widget.importService ??
      TextImportService(picker: const FileSelectorTextFilePicker());
  var _importing = false;
  String? _message;

  Future<void> _pickText() async {
    setState(() {
      _importing = true;
      _message = null;
    });
    final result = await _importService.pickAndNormalize();
    if (!mounted) return;
    setState(() => _importing = false);
    switch (result) {
      case TextImportCancelled():
        setState(() => _message = '未选择文件');
      case TextImportUnsupportedEncoding(:final fileName):
        setState(() => _message = '$fileName 不是可识别的 UTF-8 文本');
      case TextImportSucceeded(:final fileName, :final document):
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                TextDocumentPreview(title: fileName, document: document),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Paper Ages'),
      actions: [
        IconButton(
          tooltip: '交互样板',
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const PageTurnSpike())),
          icon: const Icon(Icons.science_outlined),
        ),
      ],
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_stories_outlined, size: 56),
            const SizedBox(height: 16),
            Text(
              '导入一本 TXT 开始阅读',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('当前支持 UTF-8；导入内容在本次会话中可读。'),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('pick-txt-button'),
              onPressed: _importing ? null : _pickText,
              icon: _importing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_outlined),
              label: const Text('选择 TXT 文件'),
            ),
            if (_message case final message?) ...[
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    ),
  );
}

class TextDocumentPreview extends StatelessWidget {
  const TextDocumentPreview({
    super.key,
    required this.title,
    required this.document,
  });

  final String title;
  final NormalizedTextDocument document;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: PageView.builder(
      itemCount: document.blocks.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('段落 ${index + 1}/${document.blocks.length}'),
            const SizedBox(height: 24),
            Text(
              document.blocks[index].text,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    ),
  );
}
