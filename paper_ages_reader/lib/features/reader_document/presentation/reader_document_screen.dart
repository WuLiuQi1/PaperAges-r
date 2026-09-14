import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../library/data/file_selector_book_picker.dart';
import '../../library/data/local_library_repository.dart';
import '../../library/domain/library_book.dart';
import '../../statistics/application/reading_session_recorder.dart';
import '../../statistics/data/reading_statistics_repository.dart';
import '../../reader_layout/domain/page_turn_policy.dart';
import '../domain/normalized_text_document.dart';
import 'viewport_paginator.dart';

NormalizedTextDocument _normalizeForReader(String text) =>
    const TextNormalizer().normalize(text);
Future<NormalizedTextDocument> normalizeReaderDocument(String text) =>
    compute(_normalizeForReader, text);

enum ReaderTurnMode { slide, curl, fade, scroll }

class ReaderChapterItem {
  const ReaderChapterItem({required this.title, required this.key});
  final String title;
  final String key;
}

extension on ReaderTurnMode {
  String get label => switch (this) {
    ReaderTurnMode.slide => '滑动',
    ReaderTurnMode.curl => '翻页',
    ReaderTurnMode.fade => '淡入',
    ReaderTurnMode.scroll => '滚动',
  };
}

class ReaderDocumentScreen extends StatefulWidget {
  const ReaderDocumentScreen({
    super.key,
    required this.book,
    required this.repository,
    this.normalize = normalizeReaderDocument,
    this.loadText,
    this.onChangeSource,
    this.chapters = const [],
    this.initialChapterIndex = 0,
    this.loadChapter,
    this.persistReadingPosition = true,
  });

  final LibraryBook book;
  final LocalLibraryRepository repository;
  final Future<NormalizedTextDocument> Function(String) normalize;
  final Future<String> Function()? loadText;
  final Future<bool> Function(BuildContext context)? onChangeSource;
  final List<ReaderChapterItem> chapters;
  final int initialChapterIndex;
  final Future<String> Function(int index)? loadChapter;
  final bool persistReadingPosition;

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
  bool _chromeVisible = true;
  final FlutterTts _tts = FlutterTts();
  bool _speaking = false;
  final Set<int> _bookmarks = {};
  final Map<int, String> _notes = {};
  double _brightness = 1;
  ReaderTurnMode _turnMode = ReaderTurnMode.slide;
  double _turnDirection = 1;
  double _pageDragDistance = 0;
  double? _pageDragStartX;
  final ScrollController _scrollController = ScrollController();
  bool _restoreScrollOffset = true;
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
  late int _activeChapterIndex = widget.initialChapterIndex;
  ReadingSessionRecorder? _statistics;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _speaking = false);
    });
    _restore();
  }

  Future<void> _restore() async {
    try {
      final text =
          await (widget.loadText?.call() ??
              widget.repository.readText(widget.book));
      final document = await widget.normalize(text);
      final position = widget.persistReadingPosition
          ? await widget.repository.readPosition(widget.book.id)
          : null;
      final savedSize = await widget.repository.readPreference('textFontSize');
      final savedLineHeight = await widget.repository.readPreference(
        'textLineHeight',
      );
      final savedFontPath = await widget.repository.readPreference('fontPath');
      final savedTheme = await widget.repository.readPreference(
        'readerPaperTheme',
      );
      final savedBrightness = await widget.repository.readPreference(
        'readerBrightness',
      );
      final savedTurnMode = await widget.repository.readPreference(
        'readerTurnMode',
      );
      final savedBookmarks = await widget.repository.readPreference(
        'bookmarks:${widget.book.id}',
      );
      final savedNotes = await widget.repository.readPreference(
        'notes:${widget.book.id}',
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
        _brightness = (double.tryParse(savedBrightness ?? '') ?? 1).clamp(
          .25,
          1,
        );
        _turnMode =
            ReaderTurnMode.values
                .where((mode) => mode.name == savedTurnMode)
                .firstOrNull ??
            ReaderTurnMode.slide;
        _bookmarks
          ..clear()
          ..addAll(_decodeBookmarks(savedBookmarks));
        _notes
          ..clear()
          ..addAll(_decodeNotes(savedNotes));
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

  Iterable<int> _decodeBookmarks(String? raw) {
    try {
      final value = jsonDecode(raw ?? '[]');
      return value is List ? value.whereType<int>() : const <int>[];
    } catch (_) {
      return const <int>[];
    }
  }

  Map<int, String> _decodeNotes(String? raw) {
    try {
      final value = jsonDecode(raw ?? '{}');
      if (value is! Map) return const {};
      final notes = <int, String>{};
      for (final entry in value.entries) {
        final offset = int.tryParse(entry.key.toString());
        if (offset != null) notes[offset] = entry.value.toString();
      }
      return notes;
    } catch (_) {
      return const {};
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
    if (_speaking) unawaited(_stopTtsSilently());
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _stopTtsSilently() async {
    try {
      await _tts.stop();
    } catch (_) {
      // The platform channel may already be detached during app/test teardown.
    }
  }

  Future<void> _savePage(int index) async {
    if (!widget.persistReadingPosition) return;
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
    final oldBrightness = _brightness;
    final oldTurnMode = _turnMode;
    var saved = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black26,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
            decoration: BoxDecoration(
              color: const Color(0xEBEEEEEE),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white70),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _roundButton(
                        Icons.close,
                        () => Navigator.pop(context),
                        tooltip: '关闭主题与设置',
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        '主题与设置',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _controlPill(
                          children: [
                            TextButton(
                              onPressed: () {
                                setState(
                                  () =>
                                      _fontSize = (_fontSize - 1).clamp(14, 32),
                                );
                                setSheetState(() {});
                              },
                              child: const Text('小'),
                            ),
                            const VerticalDivider(indent: 10, endIndent: 10),
                            TextButton(
                              onPressed: () {
                                setState(
                                  () =>
                                      _fontSize = (_fontSize + 1).clamp(14, 32),
                                );
                                setSheetState(() {});
                              },
                              child: const Text(
                                '大',
                                style: TextStyle(fontSize: 20),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _controlPill(
                          children: [
                            TextButton.icon(
                              onPressed: () async {
                                await _chooseTurnMode();
                                setSheetState(() {});
                              },
                              icon: const Icon(
                                Icons.chrome_reader_mode_outlined,
                              ),
                              label: Text(_turnMode.label),
                            ),
                            IconButton(
                              tooltip: darkPaperForTheme(_theme)
                                  ? '切换日间模式'
                                  : '切换夜间模式',
                              onPressed: () {
                                setState(
                                  () => _theme = darkPaperForTheme(_theme)
                                      ? 0
                                      : 1,
                                );
                                setSheetState(() {});
                              },
                              icon: Icon(
                                darkPaperForTheme(_theme)
                                    ? Icons.light_mode_rounded
                                    : Icons.dark_mode_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.light_mode_outlined, size: 20),
                      Expanded(
                        child: Slider(
                          value: _brightness,
                          min: .25,
                          max: 1,
                          onChanged: (value) {
                            setState(() => _brightness = value);
                            setSheetState(() {});
                          },
                        ),
                      ),
                      const Icon(Icons.light_mode, size: 24),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 1.12,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: 6,
                    itemBuilder: (_, index) => Semantics(
                      selected: _theme == index,
                      button: true,
                      child: InkWell(
                        onTap: () {
                          setState(() => _theme = index);
                          setSheetState(() {});
                        },
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _papers[index],
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: _theme == index
                                  ? Colors.black
                                  : Colors.black12,
                              width: _theme == index ? 2.5 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '大小',
                                style: TextStyle(
                                  fontSize: 23,
                                  fontWeight: index == 3
                                      ? FontWeight.bold
                                      : FontWeight.w400,
                                  color: index == 1 || index == 5
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              ),
                              Text(
                                _themeNames[index],
                                style: TextStyle(
                                  fontSize: 13,
                                  color: index == 1 || index == 5
                                      ? Colors.white70
                                      : Colors.black87,
                                ),
                              ),
                            ],
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
                  Material(
                    color: Colors.transparent,
                    child: ListTile(
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
                          await widget.repository.savePreference(
                            'fontPath',
                            path,
                          );
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
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                    ),
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
                      await widget.repository.savePreference(
                        'readerBrightness',
                        _brightness.toString(),
                      );
                      await widget.repository.savePreference(
                        'readerTurnMode',
                        _turnMode.name,
                      );
                      saved = true;
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: const Text('完成'),
                  ),
                ],
              ),
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
        _brightness = oldBrightness;
        _turnMode = oldTurnMode;
      });
    }
  }

  bool darkPaperForTheme(int theme) => theme == 1 || theme == 5;

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

  Widget _roundButton(
    IconData icon,
    VoidCallback onPressed, {
    required String tooltip,
    bool dark = false,
  }) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: dark ? const Color(0xFF252525) : const Color(0xFFEAEAEA),
      foregroundColor: dark ? Colors.white : Colors.black,
      minimumSize: const Size(48, 48),
    ),
    icon: Icon(icon, size: 25),
  );

  Widget _controlPill({required List<Widget> children}) => Container(
    height: 54,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(27),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: children
          .map((child) => Expanded(child: Center(child: child)))
          .toList(),
    ),
  );

  ({int current, int total, int remaining}) _pageMetrics() {
    final paginator = _paginator!;
    final length = (_page?.text.length ?? 500).clamp(1, 1000000);
    final total = (paginator.text.length / length).ceil().clamp(1, 999999);
    final current = (_offset / length).floor().clamp(0, total - 1) + 1;
    return (current: current, total: total, remaining: total - current);
  }

  void _jumpTo(int offset) {
    setState(() {
      _offset = offset.clamp(0, _paginator!.text.length);
      _history.clear();
      _menu = false;
      _chromeVisible = true;
    });
    unawaited(_savePage(_offset));
  }

  List<({String title, int offset})> _chapters() {
    final text = _paginator!.text;
    final matches = RegExp(
      r'^\s*((?:第.{1,16}[章节卷部篇回]|序章|楔子|前言|后记)[^\n]{0,40})\s*$',
      multiLine: true,
    ).allMatches(text).take(500).toList();
    if (matches.isEmpty) return [(title: '正文', offset: 0)];
    return matches
        .map((match) => (title: match.group(1)!.trim(), offset: match.start))
        .toList();
  }

  Future<void> _openContents() async {
    final metrics = _pageMetrics();
    final chapters = _chapters();
    var tab = 0;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black26,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => FractionallySizedBox(
          heightFactor: .92,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF7F7F7),
              borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 18, 18, 8),
                    child: Row(
                      children: [
                        const SizedBox(width: 48),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                widget.book.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '第 ${metrics.current} 页（共约 ${metrics.total} 页）',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _roundButton(
                          Icons.check,
                          () => Navigator.pop(sheetContext),
                          tooltip: '完成',
                          dark: true,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    height: 42,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7E7E9),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      children: [
                        for (final (index, label) in const [
                          (0, '章节'),
                          (1, '书签'),
                          (2, '笔记'),
                        ])
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => setSheetState(() => tab = index),
                              child: Container(
                                margin: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: tab == index
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Center(
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontWeight: tab == index
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: switch (tab) {
                      0 => _chapterList(sheetContext, chapters),
                      1 => _bookmarkList(sheetContext),
                      _ => _noteList(sheetContext),
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chapterList(
    BuildContext sheetContext,
    List<({String title, int offset})> chapters,
  ) {
    if (widget.chapters.isNotEmpty && widget.loadChapter != null) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
        itemCount: widget.chapters.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final chapter = widget.chapters[index];
          final selected = index == _activeChapterIndex;
          return Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 5),
              title: Text(
                chapter.title,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              trailing: selected
                  ? const Icon(Icons.check_rounded, size: 20)
                  : Text(
                      '${index + 1}',
                      style: const TextStyle(color: Colors.black45),
                    ),
              onTap: () {
                Navigator.pop(sheetContext);
                _selectChapter(index);
              },
            ),
          );
        },
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
      itemCount: chapters.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final chapter = chapters[index];
        final page = (chapter.offset / (_page?.text.length ?? 500)).floor() + 1;
        return Material(
          color: Colors.transparent,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 5),
            title: Text(
              chapter.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            trailing: Text(
              '$page',
              style: const TextStyle(color: Colors.black45),
            ),
            onTap: () {
              Navigator.pop(sheetContext);
              _jumpTo(chapter.offset);
            },
          ),
        );
      },
    );
  }

  Future<void> _selectChapter(int index) async {
    final loader = widget.loadChapter;
    if (loader == null || index == _activeChapterIndex) return;
    setState(() {
      _document = null;
      _paginator = null;
      _page = null;
      _error = null;
      _history.clear();
    });
    try {
      final document = await widget.normalize(await loader(index));
      if (!mounted) return;
      setState(() {
        _activeChapterIndex = index;
        _document = document;
        _paginator = ViewportPaginator(document);
        _offset = 0;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '章节加载失败：$error');
    }
  }

  Widget _bookmarkList(BuildContext sheetContext) {
    final offsets = _bookmarks.toList()..sort();
    if (offsets.isEmpty) return const Center(child: Text('还没有书签'));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
      itemCount: offsets.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final offset = offsets[index];
        return Material(
          color: Colors.transparent,
          child: ListTile(
            leading: const Icon(Icons.bookmark_rounded),
            title: Text(_excerptAt(offset)),
            subtitle: Text('全书 ${_percentAt(offset)}%'),
            onTap: () {
              Navigator.pop(sheetContext);
              _jumpTo(offset);
            },
          ),
        );
      },
    );
  }

  Widget _noteList(BuildContext sheetContext) {
    final entries = _notes.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) return const Center(child: Text('还没有笔记'));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final entry = entries[index];
        return Material(
          color: Colors.transparent,
          child: ListTile(
            leading: const Icon(Icons.notes_rounded),
            title: Text(entry.value),
            subtitle: Text(
              '${_excerptAt(entry.key)} · ${_percentAt(entry.key)}%',
            ),
            onTap: () {
              Navigator.pop(sheetContext);
              _jumpTo(entry.key);
            },
          ),
        );
      },
    );
  }

  String _excerptAt(int offset) {
    final text = _paginator!.text;
    final start = offset.clamp(0, text.length);
    final end = (start + 42).clamp(0, text.length);
    return text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  int _percentAt(int offset) => _paginator!.text.isEmpty
      ? 0
      : (offset * 100 / _paginator!.text.length).round().clamp(0, 100);

  Future<void> _openBookSearch() async {
    final controller = TextEditingController();
    var results = <int>[];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black26,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => FractionallySizedBox(
          heightFactor: .92,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF7F7F7),
              borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 30, 24, 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '在图书中搜索',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            controller.clear();
                            setSheetState(() => results = []);
                          },
                          child: const Text('清除'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: results.isEmpty
                        ? const Center(
                            child: Text(
                              '输入内容，在本书中查找',
                              style: TextStyle(color: Colors.black45),
                            ),
                          )
                        : ListView.separated(
                            itemCount: results.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (_, index) {
                              final offset = results[index];
                              final start = (offset - 24).clamp(
                                0,
                                _paginator!.text.length,
                              );
                              final end = (offset + controller.text.length + 42)
                                  .clamp(0, _paginator!.text.length);
                              return Material(
                                color: Colors.transparent,
                                child: ListTile(
                                  leading: const Icon(Icons.search),
                                  title: Text(
                                    _paginator!.text.substring(start, end),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () {
                                    Navigator.pop(sheetContext);
                                    _jumpTo(offset);
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      10,
                      24,
                      MediaQuery.viewInsetsOf(context).bottom + 12,
                    ),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: const Icon(Icons.mic_none),
                        hintText: '在此书中',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (query) {
                        final found = <int>[];
                        if (query.isNotEmpty) {
                          var from = 0;
                          while (found.length < 100) {
                            final next = _paginator!.text.indexOf(query, from);
                            if (next < 0) break;
                            found.add(next);
                            from = next + query.length;
                          }
                        }
                        setSheetState(() => results = found);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    controller.dispose();
  }

  Widget _readerMenu() {
    final progress = _paginator!.text.isEmpty
        ? 0
        : (_offset / _paginator!.text.length * 100).floor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        _progressAction(progress),
        const SizedBox(height: 7),
        _menuAction('在图书中搜索', Icons.search_rounded, () {
          setState(() => _menu = false);
          _openBookSearch();
        }),
        const SizedBox(height: 7),
        _menuAction('主题与设置', Icons.text_fields_rounded, () {
          setState(() => _menu = false);
          _openAppearance();
        }),
        const SizedBox(height: 9),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _roundButton(
              widget.onChangeSource == null
                  ? Icons.ios_share_rounded
                  : Icons.swap_horiz_rounded,
              widget.onChangeSource == null ? _shareCurrentPage : _changeSource,
              tooltip: widget.onChangeSource == null ? '分享' : '换源',
            ),
            const SizedBox(width: 8),
            _roundButton(
              _speaking
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outline_rounded,
              _toggleListening,
              tooltip: _speaking ? '停止听书' : '听书',
            ),
            const SizedBox(width: 8),
            _roundButton(Icons.notes_rounded, _editNote, tooltip: '笔记'),
            const SizedBox(width: 8),
            _roundButton(
              _bookmarks.contains(_offset)
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              _toggleBookmark,
              tooltip: _bookmarks.contains(_offset) ? '移除书签' : '添加书签',
            ),
          ],
        ),
      ],
    );
  }

  Widget _menuAction(
    String label,
    IconData icon,
    VoidCallback action, {
    bool dark = false,
  }) => Material(
    color: dark ? const Color(0xFF282828) : const Color(0xF2F4F4F4),
    borderRadius: BorderRadius.circular(24),
    elevation: 0,
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: action,
      child: SizedBox(
        width: 226,
        height: 46,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: dark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(icon, color: dark ? Colors.white : Colors.black, size: 22),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _progressAction(int progress) => GestureDetector(
    onHorizontalDragUpdate: (details) {
      final fraction = (details.localPosition.dx / 226).clamp(0.0, 1.0);
      final raw = (_paginator!.text.length * fraction).round();
      final location = _paginator!.anchorFor(
        raw.clamp(0, _paginator!.text.length),
      );
      final anchor = const TextAnchorResolver().create(
        editionId: widget.book.fingerprint,
        document: _document!,
        blockIndex: location.block,
        requestedOffsetUtf16: location.offset,
      );
      setState(() {
        _offset = _paginator!.offsetFor(location.block, anchor.offsetUtf16);
        _history.clear();
      });
    },
    onHorizontalDragEnd: (_) => unawaited(_savePage(_offset)),
    child: _menuAction(
      '目录 · $progress%',
      Icons.format_list_bulleted_rounded,
      () {
        setState(() => _menu = false);
        _openContents();
      },
      dark: true,
    ),
  );

  Future<void> _toggleBookmark() async {
    setState(() {
      if (!_bookmarks.add(_offset)) _bookmarks.remove(_offset);
      _menu = false;
    });
    await widget.repository.savePreference(
      'bookmarks:${widget.book.id}',
      jsonEncode(_bookmarks.toList()..sort()),
    );
  }

  Future<void> _editNote() async {
    setState(() => _menu = false);
    var draft = _notes[_offset] ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('添加笔记'),
        content: TextFormField(
          initialValue: draft,
          autofocus: true,
          maxLines: 6,
          onChanged: (value) => draft = value,
          decoration: const InputDecoration(hintText: '记录这一页的想法'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, draft.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null) return;
    setState(() {
      if (result.isEmpty) {
        _notes.remove(_offset);
      } else {
        _notes[_offset] = result;
      }
    });
    await widget.repository.savePreference(
      'notes:${widget.book.id}',
      jsonEncode(_notes.map((key, value) => MapEntry('$key', value))),
    );
  }

  Future<void> _toggleListening() async {
    setState(() => _menu = false);
    try {
      if (_speaking) {
        await _tts.stop();
        if (mounted) setState(() => _speaking = false);
        return;
      }
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(.5);
      await _tts.setVolume(1);
      final result = await _tts.speak(_page?.text ?? '');
      if (mounted) setState(() => _speaking = result == 1);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('系统语音不可用，请先安装中文离线语音')));
      }
    }
  }

  Future<void> _shareCurrentPage() async {
    setState(() => _menu = false);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      await SharePlus.instance.share(
        ShareParams(
          subject: widget.book.title,
          text: '${_page?.text ?? ''}\n\n——《${widget.book.title}》',
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('暂时无法打开系统分享')));
      }
    }
  }

  Future<void> _changeSource() async {
    final change = widget.onChangeSource;
    if (change == null) return;
    setState(() => _menu = false);
    final changed = await change(context);
    if (!changed || !mounted) return;
    setState(() {
      _document = null;
      _paginator = null;
      _page = null;
      _offset = 0;
      _history.clear();
      _error = null;
    });
    await _restore();
  }

  Future<void> _chooseTurnMode() async {
    final selected = await showModalBottomSheet<ReaderTurnMode>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                '翻页方式',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            for (final mode in ReaderTurnMode.values)
              ListTile(
                leading: Icon(
                  mode == _turnMode
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(mode.label),
                onTap: () => Navigator.pop(context, mode),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    setState(() {
      _turnMode = selected;
      _pageDragDistance = 0;
      if (selected == ReaderTurnMode.scroll) _restoreScrollOffset = true;
    });
    await widget.repository.savePreference('readerTurnMode', selected.name);
  }

  Widget _pageTransition(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return switch (_turnMode) {
      ReaderTurnMode.fade => FadeTransition(opacity: curved, child: child),
      ReaderTurnMode.scroll => SlideTransition(
        position: Tween(
          begin: Offset(0, _turnDirection * .18),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
      ReaderTurnMode.curl => FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: .88, end: 1.0).animate(curved),
          alignment: _turnDirection > 0
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: child,
        ),
      ),
      ReaderTurnMode.slide => SlideTransition(
        position: Tween(
          begin: Offset(_turnDirection * .18, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    };
  }

  void _restoreContinuousScroll() {
    if (!_restoreScrollOffset) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final extent = _scrollController.position.maxScrollExtent;
      final length = _paginator?.text.length ?? 0;
      final fraction = length == 0 ? 0.0 : _offset / length;
      _scrollController.jumpTo((extent * fraction).clamp(0, extent));
      _restoreScrollOffset = false;
    });
  }

  void _commitContinuousScroll() {
    if (!_scrollController.hasClients || _paginator == null) return;
    final extent = _scrollController.position.maxScrollExtent;
    final fraction = extent <= 0
        ? 0.0
        : (_scrollController.offset / extent).clamp(0.0, 1.0);
    final nextOffset = (_paginator!.text.length * fraction).round();
    setState(() => _offset = nextOffset.clamp(0, _paginator!.text.length));
    unawaited(_savePage(_offset));
  }

  Widget _continuousScrollSurface(TextStyle style, TextScaler scaler) {
    _restoreContinuousScroll();
    return NotificationListener<ScrollEndNotification>(
      onNotification: (_) {
        _commitContinuousScroll();
        return false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => setState(() {
          _chromeVisible = !_chromeVisible;
          _menu = false;
        }),
        child: SingleChildScrollView(
          key: const Key('reader-continuous-scroll-surface'),
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 36),
          child: SizedBox(
            width: double.infinity,
            child: Text(
              _paginator!.text,
              textAlign: TextAlign.justify,
              textScaler: scaler,
              style: style,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    final darkPaper = _theme == 1 || _theme == 5;
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
              child: Stack(
                children: [
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 64,
                        child: AnimatedOpacity(
                          opacity: _chromeVisible ? 1 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: IgnorePointer(
                            ignoring: !_chromeVisible,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 72,
                                  ),
                                  child: Text(
                                    _pageMetrics().remaining > 0
                                        ? '本章还剩 ${_pageMetrics().remaining} 页'
                                        : widget.book.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: darkPaper
                                          ? Colors.white54
                                          : Colors.black45,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 16,
                                  child: _roundButton(
                                    Icons.close,
                                    () => Navigator.of(context).pop(),
                                    tooltip: '关闭图书',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(32, 14, 32, 8),
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
                                color: darkPaper
                                    ? const Color(0xFFECECEC)
                                    : const Color(0xFF222222),
                              );
                              if (_turnMode == ReaderTurnMode.scroll) {
                                return _continuousScrollSurface(style, scaler);
                              }
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
                                  _turnDirection = forward ? 1 : -1;
                                  _pageDragDistance = 0;
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
                                  _chromeVisible = true;
                                });
                                unawaited(_savePage(_offset));
                              }

                              return GestureDetector(
                                key: Key(
                                  _turnMode == ReaderTurnMode.curl
                                      ? 'reader-curl-surface'
                                      : 'reader-paged-surface',
                                ),
                                behavior: HitTestBehavior.opaque,
                                onHorizontalDragDown: (details) =>
                                    _pageDragStartX = details.globalPosition.dx,
                                onHorizontalDragUpdate: (details) => setState(
                                  () => _pageDragDistance =
                                      (_pageDragStartX == null
                                              ? _pageDragDistance +
                                                    details.delta.dx
                                              : details.globalPosition.dx -
                                                    _pageDragStartX!)
                                          .clamp(-size.width, size.width),
                                ),
                                onHorizontalDragCancel: () => setState(() {
                                  _pageDragDistance = 0;
                                  _pageDragStartX = null;
                                }),
                                onHorizontalDragEnd: (details) {
                                  final outcome = const PageTurnPolicy()
                                      .resolve(
                                        dragDistance: _pageDragDistance,
                                        horizontalVelocity:
                                            details.primaryVelocity ?? 0,
                                        viewportWidth: size.width,
                                      );
                                  if (outcome == PageTurnOutcome.next) {
                                    turn(true);
                                  } else if (outcome ==
                                      PageTurnOutcome.previous) {
                                    turn(false);
                                  } else {
                                    setState(() => _pageDragDistance = 0);
                                  }
                                  _pageDragStartX = null;
                                },
                                onTapUp: (details) {
                                  final x =
                                      details.localPosition.dx / size.width;
                                  if (x < .25) {
                                    turn(false);
                                  } else if (x > .75) {
                                    turn(true);
                                  } else {
                                    setState(() {
                                      _chromeVisible = !_chromeVisible;
                                      _menu = false;
                                    });
                                  }
                                },
                                child: Transform.translate(
                                  offset: _turnMode == ReaderTurnMode.slide
                                      ? Offset(_pageDragDistance, 0)
                                      : Offset.zero,
                                  child: CustomPaint(
                                    foregroundPainter:
                                        _turnMode == ReaderTurnMode.curl
                                        ? _ReaderCurlPainter(
                                            progress:
                                                (_pageDragDistance.abs() /
                                                        size.width)
                                                    .clamp(0, .96),
                                            fromRight: _pageDragDistance <= 0,
                                            paper: _papers[_theme],
                                          )
                                        : null,
                                    child: Align(
                                      alignment: Alignment.topLeft,
                                      child: AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 240,
                                        ),
                                        transitionBuilder: _pageTransition,
                                        child: Text(
                                          _page!.text,
                                          key: ValueKey(_offset),
                                          textAlign: TextAlign.justify,
                                          textScaler: scaler,
                                          style: style,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        height: 64,
                        child: AnimatedOpacity(
                          opacity: _chromeVisible ? 1 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: IgnorePointer(
                            ignoring: !_chromeVisible,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Text(
                                  _paginator!.text.isEmpty
                                      ? '空白文档'
                                      : '${_pageMetrics().current}/约${_pageMetrics().total}页',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                Positioned(
                                  right: 16,
                                  child: _roundButton(
                                    Icons.toc_rounded,
                                    () => setState(() => _menu = !_menu),
                                    tooltip: '阅读菜单',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_menu)
                    Positioned(
                      right: 16,
                      bottom: 70,
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: _readerMenu(),
                      ),
                    ),
                  if (_brightness < 1)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: Colors.black.withValues(
                            alpha: (1 - _brightness) * .68,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _ReaderCurlPainter extends CustomPainter {
  const _ReaderCurlPainter({
    required this.progress,
    required this.fromRight,
    required this.paper,
  });

  final double progress;
  final bool fromRight;
  final Color paper;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final foldWidth = size.width * progress;
    final edge = fromRight ? size.width - foldWidth : foldWidth;
    final fold = Path()
      ..moveTo(edge, 0)
      ..quadraticBezierTo(
        fromRight ? size.width + foldWidth * .14 : -foldWidth * .14,
        size.height * .48,
        edge,
        size.height,
      )
      ..lineTo(fromRight ? size.width : 0, size.height)
      ..lineTo(fromRight ? size.width : 0, 0)
      ..close();
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawPath(
      fold,
      Paint()
        ..shader = LinearGradient(
          begin: fromRight ? Alignment.centerLeft : Alignment.centerRight,
          end: fromRight ? Alignment.centerRight : Alignment.centerLeft,
          colors: [
            Colors.black.withValues(alpha: .24),
            Color.lerp(paper, Colors.white, .18)!,
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      fold,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: .18),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ReaderCurlPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      fromRight != oldDelegate.fromRight ||
      paper != oldDelegate.paper;
}
