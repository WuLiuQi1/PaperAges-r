import 'dart:async';
import 'dart:io';
import 'dart:ui';

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
  bool _chromeVisible = true;
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
                          children: const [
                            Icon(Icons.chrome_reader_mode_outlined),
                            Icon(Icons.contrast_rounded),
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
                          value: (_fontSize - 14) / 18,
                          onChanged: (value) {
                            setState(() => _fontSize = 14 + value * 18);
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black26,
      builder: (sheetContext) => FractionallySizedBox(
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
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Center(
                            child: Text(
                              '章节',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                      const Expanded(child: Center(child: Text('书签'))),
                      const Expanded(child: Center(child: Text('高亮标记'))),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
                    itemCount: chapters.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final chapter = chapters[index];
                      final page =
                          (chapter.offset / (_page?.text.length ?? 500))
                              .floor() +
                          1;
                      return Material(
                        color: Colors.transparent,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 5,
                          ),
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
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
        _menuAction('目录 · $progress%', Icons.format_list_bulleted_rounded, () {
          setState(() => _menu = false);
          _openContents();
        }, dark: true),
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
              Icons.ios_share_rounded,
              () => _showUnavailable('分享'),
              tooltip: '分享',
            ),
            const SizedBox(width: 8),
            _roundButton(
              Icons.play_circle_outline_rounded,
              () => _showUnavailable('听书'),
              tooltip: '听书',
            ),
            const SizedBox(width: 8),
            _roundButton(
              Icons.notes_rounded,
              () => _showUnavailable('笔记'),
              tooltip: '笔记',
            ),
            const SizedBox(width: 8),
            _roundButton(
              Icons.bookmark_border_rounded,
              () => _showUnavailable('书签'),
              tooltip: '书签',
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

  void _showUnavailable(String feature) {
    setState(() => _menu = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text('$feature功能尚未完成'),
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
                                  _chromeVisible = true;
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
                ],
              ),
            ),
    );
  }
}
