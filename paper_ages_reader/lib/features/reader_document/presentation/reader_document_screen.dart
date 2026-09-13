import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:path_provider/path_provider.dart';

import '../../../core/storage/app_database.dart';
import '../../library/data/file_selector_book_picker.dart';
import '../../library/data/local_library_repository.dart';
import '../../library/domain/library_book.dart';
import '../../statistics/application/reading_session_recorder.dart';
import '../../statistics/data/reading_statistics_repository.dart';
import '../domain/normalized_text_document.dart';

class ReaderDocumentScreen extends StatefulWidget {
  const ReaderDocumentScreen({
    super.key,
    required this.book,
    required this.repository,
  });

  final LibraryBook book;
  final LocalLibraryRepository repository;

  @override
  State<ReaderDocumentScreen> createState() => _ReaderDocumentScreenState();
}

class _ReaderDocumentScreenState extends State<ReaderDocumentScreen>
    with WidgetsBindingObserver {
  final _controller = PageController();
  NormalizedTextDocument? _document;
  String? _error;
  double _fontSize = 20;
  double _lineHeight = 1.7;
  String? _fontFamily;
  int _revision = 0;
  ReadingSessionRecorder? _statistics;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restore();
  }

  Future<void> _restore() async {
    try {
      final text = await widget.repository.readText(widget.book);
      final document = const TextNormalizer().normalize(text);
      final position = await widget.repository.readPosition(widget.book.id);
      final savedSize = await widget.repository.readPreference('textFontSize');
      final savedLineHeight = await widget.repository.readPreference(
        'textLineHeight',
      );
      final savedFontPath = await widget.repository.readPreference('fontPath');
      if (savedFontPath != null && await File(savedFontPath).exists()) {
        await _loadFont(savedFontPath, persist: false);
      }
      if (!mounted) return;
      setState(() {
        _document = document;
        _revision = position?.revision ?? 0;
        _fontSize = double.tryParse(savedSize ?? '') ?? _fontSize;
        _lineHeight = double.tryParse(savedLineHeight ?? '') ?? _lineHeight;
      });
      final database = await AppDatabase.defaults();
      _statistics = ReadingSessionRecorder(
        ReadingStatisticsRepository(database),
      )..resumeReading();
      final target = (position?.blockIndex ?? 0).clamp(
        0,
        document.blocks.length - 1,
      );
      if (target > 0) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _controller.jumpToPage(target),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '无法打开此书：$error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final recorder = _statistics;
    if (recorder == null) return;
    if (state == AppLifecycleState.resumed) {
      recorder.resumeReading();
    } else {
      unawaited(recorder.pauseReading());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final recorder = _statistics;
    if (recorder != null) unawaited(recorder.pauseReading());
    _controller.dispose();
    super.dispose();
  }

  Future<void> _savePage(int index) async {
    final document = _document;
    if (document == null || index >= document.blocks.length) return;
    final anchor = const TextAnchorResolver().create(
      editionId: widget.book.fingerprint,
      document: document,
      blockIndex: index,
      requestedOffsetUtf16: 0,
    );
    _revision += 1;
    await widget.repository.savePosition(
      bookId: widget.book.id,
      blockIndex: index,
      graphemeOffset: 0,
      contextHash: anchor.contextHash,
      revision: _revision,
      totalBlocks: document.blocks.length,
    );
  }

  Future<void> _openAppearance() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '阅读外观',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  const Text('字号'),
                  Expanded(
                    child: Slider(
                      value: _fontSize,
                      min: 14,
                      max: 32,
                      divisions: 18,
                      label: _fontSize.round().toString(),
                      onChanged: (value) {
                        setState(() => _fontSize = value);
                        setSheetState(() {});
                      },
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const Text('行距'),
                  Expanded(
                    child: Slider(
                      value: _lineHeight,
                      min: 1.2,
                      max: 2.4,
                      divisions: 12,
                      label: _lineHeight.toStringAsFixed(1),
                      onChanged: (value) {
                        setState(() => _lineHeight = value);
                        setSheetState(() {});
                      },
                    ),
                  ),
                ],
              ),
              ListTile(
                leading: const Icon(Icons.font_download_outlined),
                title: Text(
                  _fontFamily == null ? '导入 TTF / OTF 字体' : '当前字体：$_fontFamily',
                ),
                onTap: () async {
                  final selected = await const FileSelectorBookPicker()
                      .pickFont();
                  if (selected == null) return;
                  try {
                    final path = await _copyAndLoadFont(
                      selected.name,
                      selected.bytes,
                    );
                    await widget.repository.savePreference('fontPath', path);
                    if (context.mounted) Navigator.of(context).pop();
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('字体无法载入，已保持原有字体')),
                      );
                    }
                  }
                },
              ),
              FilledButton(
                onPressed: () async {
                  await widget.repository.savePreference(
                    'textFontSize',
                    _fontSize.toString(),
                  );
                  await widget.repository.savePreference(
                    'textLineHeight',
                    _lineHeight.toString(),
                  );
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('保存外观'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String> _copyAndLoadFont(String name, List<int> bytes) async {
    final docs = await getApplicationDocumentsDirectory();
    final fonts = Directory('${docs.path}${Platform.pathSeparator}fonts');
    await fonts.create(recursive: true);
    final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File(
      '${fonts.path}${Platform.pathSeparator}${widget.book.id}_$safeName',
    );
    await file.writeAsBytes(bytes, flush: true);
    await _loadFont(file.path);
    return file.path;
  }

  Future<void> _loadFont(String path, {bool persist = true}) async {
    final family = 'PaperAges_${widget.book.id.replaceAll('-', '')}';
    final loader = FontLoader(family)
      ..addFont(File(path).readAsBytes().then(ByteData.sublistView));
    await loader.load();
    if (mounted) setState(() => _fontFamily = family);
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title),
        actions: [
          IconButton(
            onPressed: _openAppearance,
            tooltip: '阅读外观',
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : document == null
          ? const Center(child: CircularProgressIndicator())
          : PageView.builder(
              controller: _controller,
              itemCount: document.blocks.length,
              onPageChanged: _savePage,
              itemBuilder: (context, index) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1} / ${document.blocks.length}',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            document.blocks[index].text,
                            style: TextStyle(
                              fontFamily: _fontFamily,
                              fontSize: _fontSize,
                              height: _lineHeight,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
