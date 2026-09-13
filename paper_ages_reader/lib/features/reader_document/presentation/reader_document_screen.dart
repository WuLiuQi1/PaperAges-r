import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:path_provider/path_provider.dart';

import '../../library/data/file_selector_book_picker.dart';
import '../../library/data/local_library_repository.dart';
import '../../library/domain/library_book.dart';
import '../../statistics/application/reading_session_recorder.dart';
import '../../statistics/data/reading_statistics_repository.dart';
import '../domain/normalized_text_document.dart';
import 'viewport_paginator.dart';

NormalizedTextDocument _normalizeForReader(String text) =>
    const TextNormalizer().normalize(text);
Future<NormalizedTextDocument> normalizeReaderDocument(String text) =>
    compute(_normalizeForReader, text);

class ReaderDocumentScreen extends StatefulWidget {
  const ReaderDocumentScreen({
    super.key,
    required this.book,
    required this.repository,
    this.normalize = normalizeReaderDocument,
  });

  final LibraryBook book;
  final LocalLibraryRepository repository;
  final Future<NormalizedTextDocument> Function(String) normalize;

  @override
  State<ReaderDocumentScreen> createState() => _ReaderDocumentScreenState();
}

class _ReaderDocumentScreenState extends State<ReaderDocumentScreen>
    with WidgetsBindingObserver {
  ViewportPaginator? _paginator;
  TextPage? _page;
  int _offset = 0;
  final _history = <int>[];
  bool _menu = false;
  int _theme = 0;
  static const _papers = [
    Color(0xFFFFFFFF),
    Color(0xFF242424),
    Color(0xFFF2E8D5),
    Color(0xFFFFFFFF),
    Color(0xFFE3E6DE),
    Color(0xFF191919),
  ];
  static const _themeNames = ['原始', '安静', '纸张', '粗体', '平静', '专注'];
  NormalizedTextDocument? _document;
  String? _error;
  double _fontSize = 18;
  double _lineHeight = 1.45;
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
      final document = await widget.normalize(text);
      final position = await widget.repository.readPosition(widget.book.id);
      final savedSize = await widget.repository.readPreference('textFontSize');
      final savedLineHeight = await widget.repository.readPreference(
        'textLineHeight',
      );
      final savedFontPath = await widget.repository.readPreference('fontPath');
      final savedTheme = await widget.repository.readPreference(
        'readerPaperTheme',
      );
      if (savedFontPath != null && await File(savedFontPath).exists()) {
        await _loadFont(savedFontPath, persist: false);
      }
      if (!mounted) return;
      setState(() {
        _document = document;
        _paginator = ViewportPaginator(document);
        _offset = _paginator!.offsetFor(
          position?.blockIndex ?? 0,
          position?.graphemeOffset ?? 0,
        );
        _revision = position?.revision ?? 0;
        _theme = (int.tryParse(savedTheme ?? '') ?? 0).clamp(0, 5);
        _fontSize = (double.tryParse(savedSize ?? '') ?? _fontSize).clamp(
          14,
          32,
        );
        _lineHeight = (double.tryParse(savedLineHeight ?? '') ?? _lineHeight)
            .clamp(1.2, 2.4);
      });
      final database = widget.repository.database;
      _statistics = ReadingSessionRecorder(
        ReadingStatisticsRepository(database),
      )..resumeReading();
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
    super.dispose();
  }

  Future<void> _savePage(int index) async {
    final document = _document;
    if (document == null) return;
    final location = _paginator!.anchorFor(index);
    final anchor = const TextAnchorResolver().create(
      editionId: widget.book.fingerprint,
      document: document,
      blockIndex: location.block,
      requestedOffsetUtf16: location.offset,
    );
    _revision += 1;
    await widget.repository.savePosition(
      bookId: widget.book.id,
      blockIndex: location.block,
      graphemeOffset: anchor.offsetUtf16,
      contextHash: anchor.contextHash,
      revision: _revision,
      totalBlocks: document.blocks.length,
    );
  }

  Future<void> _openAppearance() async {
    final oldSize = _fontSize;
    final oldHeight = _lineHeight;
    final oldTheme = _theme;
    var saved = false;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '主题与设置',
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
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: List.generate(
                    6,
                    (index) => Semantics(
                      selected: _theme == index,
                      button: true,
                      child: InkWell(
                        onTap: () {
                          setState(() => _theme = index);
                          setSheetState(() {});
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 88,
                          height: 72,
                          decoration: BoxDecoration(
                            color: _papers[index],
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _theme == index
                                  ? Colors.orange
                                  : Colors.grey,
                              width: _theme == index ? 2 : .5,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Aa',
                                style: TextStyle(
                                  fontSize: 23,
                                  color: index == 1 || index == 5
                                      ? Colors.white
                                      : Colors.black,
                                  fontWeight: index == 3
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              Text(
                                _themeNames[index],
                                style: TextStyle(
                                  fontSize: 11,
                                  color: index == 1 || index == 5
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
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
                    _fontFamily == null
                        ? '导入 TTF / OTF 字体'
                        : '当前字体：$_fontFamily',
                  ),
                  onTap: () async {
                    try {
                      final selected = await const FileSelectorBookPicker()
                          .pickFont();
                      if (selected == null) return;
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
                    await widget.repository.savePreference(
                      'readerPaperTheme',
                      _theme.toString(),
                    );
                    saved = true;
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('保存外观'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!saved && mounted) {
      setState(() {
        _fontSize = oldSize;
        _lineHeight = oldHeight;
        _theme = oldTheme;
      });
    }
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
      backgroundColor: _papers[_theme],
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('返回书库'),
                  ),
                ],
              ),
            )
          : document == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 64),
                          child: Text(
                            widget.book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: _theme == 1 || _theme == 5
                                  ? Colors.white70
                                  : Colors.black54,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 12,
                          child: IconButton.filledTonal(
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFFECECEC),
                              foregroundColor: Colors.black54,
                            ),
                            tooltip: '关闭图书',
                            icon: const Icon(Icons.close, size: 19),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final size = constraints.biggest;
                          final scaler = MediaQuery.textScalerOf(context);
                          final style = TextStyle(
                            fontFamily:
                                _fontFamily ??
                                Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.fontFamily,
                            fontSize: _fontSize,
                            height: _lineHeight,
                            fontWeight: _theme == 3
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: _theme == 1 || _theme == 5
                                ? const Color(0xFFECECEC)
                                : const Color(0xFF222222),
                          );
                          _page = _paginator!.page(
                            _offset,
                            size,
                            style,
                            scaler,
                          );
                          void turn(bool forward) {
                            final page = _page!;
                            if (forward &&
                                page.end >= _paginator!.text.length) {
                              return;
                            }
                            if (!forward && _offset == 0) return;
                            setState(() {
                              if (forward) {
                                _history.add(_offset);
                                _offset = page.end;
                              } else {
                                _offset = _history.isNotEmpty
                                    ? _history.removeLast()
                                    : _paginator!
                                          .previous(
                                            _offset,
                                            size,
                                            style,
                                            scaler,
                                          )
                                          .start;
                              }
                              _menu = false;
                            });
                            unawaited(_savePage(_offset));
                          }

                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragEnd: (details) {
                              final velocity = details.primaryVelocity ?? 0;
                              if (velocity.abs() > 80) turn(velocity < 0);
                            },
                            onTapUp: (details) {
                              final x = details.localPosition.dx / size.width;
                              if (x < .25) {
                                turn(false);
                              } else if (x > .75) {
                                turn(true);
                              } else {
                                setState(() => _menu = !_menu);
                              }
                            },
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                _page!.text,
                                textAlign: TextAlign.justify,
                                textScaler: scaler,
                                style: style,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (_menu)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: FilledButton.tonalIcon(
                          onPressed: _openAppearance,
                          icon: const Icon(Icons.text_fields),
                          label: const Text('主题与设置'),
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          _paginator!.text.isEmpty
                              ? '空白文档'
                              : '${(_offset / _paginator!.text.length * 100).floor()}% · 阅读进度',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        Positioned(
                          right: 12,
                          child: IconButton.filledTonal(
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFFECECEC),
                              foregroundColor: Colors.black54,
                            ),
                            tooltip: '阅读菜单',
                            icon: const Icon(Icons.menu, size: 20),
                            onPressed: () => setState(() => _menu = !_menu),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
