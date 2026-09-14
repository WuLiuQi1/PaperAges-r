import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/core/storage/app_database.dart';
import 'package:paper_ages_reader/features/library/data/local_library_repository.dart';
import 'package:paper_ages_reader/features/library/domain/library_book.dart';
import 'package:paper_ages_reader/features/reader_document/presentation/reader_document_screen.dart';
import 'package:paper_ages_reader/features/reader_document/domain/normalized_text_document.dart';

class _MemoryRepository extends LocalLibraryRepository {
  _MemoryRepository(super.database, this.text);
  final String text;
  final preferences = <String, String>{};

  @override
  Future<String> readText(LibraryBook book) async => text;

  @override
  Future<void> savePreference(String key, String value) async {
    preferences[key] = value;
  }

  @override
  Future<String?> readPreference(String key) async => preferences[key];

  @override
  Future<void> savePosition({
    required String bookId,
    required int blockIndex,
    required int graphemeOffset,
    required String contextHash,
    required int revision,
    int? totalBlocks,
  }) async {}
}

void main() {
  testWidgets('network text uses the shared reader and exposes source switch', (
    tester,
  ) async {
    final folder = Directory.systemTemp.createTempSync('paper-network-reader-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final db = await tester.runAsync(
      () => AppDatabase.openFile(File('${folder.path}/state.json')),
    );
    final repository = _MemoryRepository(db!, '不应读取本地文件');
    var switches = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderDocumentScreen(
          book: LibraryBook(
            id: 'network-book',
            kind: LibraryBookKind.text,
            title: '在线春秋',
            filePath: '',
            fingerprint: 'network-book',
            createdAt: DateTime(2026),
          ),
          repository: repository,
          loadText: () async => '这是在线章节正文。',
          normalize: (text) async => const TextNormalizer().normalize(text),
          onChangeSource: (_) async {
            switches += 1;
            return false;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('这是在线章节正文'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    await tester.tap(find.byTooltip('阅读菜单'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('换源'), findsOneWidget);
    expect(find.byTooltip('分享'), findsNothing);
    await tester.tap(find.byTooltip('换源'));
    await tester.pumpAndSettle();
    expect(switches, 1);
    await tester.runAsync(() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  });

  testWidgets(
    'reader flows paragraphs, turns, and opens theme panel without AppBar',
    (tester) async {
      final folder = Directory.systemTemp.createTempSync('paper-reader-test-');
      addTearDown(() => folder.deleteSync(recursive: true));
      final file = File('${folder.path}/book.txt')
        ..writeAsStringSync(
          List.generate(
            100,
            (i) => '　　清晨的光线穿过窗户，照在摊开的书页上。人们沿着河岸慢慢走过，远处传来钟声。这是第$i段。',
          ).join('\n\n'),
        );
      final db = await tester.runAsync(
        () => AppDatabase.openFile(File('${folder.path}/state.json')),
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await tester.runAsync(() async {
          final data = ByteData.sublistView(
            await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
          );
          await (FontLoader('ReaderTest')..addFont(Future.value(data))).load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
      }
      final boundary = GlobalKey();
      final repository = _MemoryRepository(db!, file.readAsStringSync());
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: const bool.fromEnvironment('CAPTURE_UI')
                  ? 'ReaderTest'
                  : null,
            ),
            home: ReaderDocumentScreen(
              book: LibraryBook(
                id: 'reader',
                kind: LibraryBookKind.text,
                title: '山海拾记',
                filePath: file.path,
                fingerprint: 'reader',
                createdAt: DateTime(2026),
              ),
              repository: repository,
              normalize: (text) async => const TextNormalizer().normalize(text),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(find.textContaining('这是第0段'), findsOneWidget);
      expect(find.textContaining('这是第1段'), findsOneWidget);
      expect(tester.takeException(), isNull);
      Future<void> capture(String name) async {
        if (!const bool.fromEnvironment('CAPTURE_UI')) return;
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/ui-review').create(recursive: true);
          await File('build/ui-review/$name-390.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('reader');
      await tester.runAsync(() => tester.tapAt(const Offset(350, 400)));
      await tester.pumpAndSettle();
      expect(find.textContaining('这是第0段'), findsNothing);
      await tester.tap(find.byTooltip('阅读菜单'));
      await tester.pumpAndSettle();
      expect(find.text('在图书中搜索'), findsOneWidget);
      final progressFinder = find.textContaining('目录 ·');
      final beforeDrag = tester.widget<Text>(progressFinder).data;
      final progressRect = tester.getRect(progressFinder);
      await tester.dragFrom(
        Offset(progressRect.left + 8, progressRect.center.dy),
        Offset(progressRect.width * .72, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(progressFinder).data, isNot(beforeDrag));
      await tester.tap(find.byTooltip('添加书签'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      expect(await repository.readPreference('bookmarks:reader'), isNotNull);
      await tester.tap(find.byTooltip('阅读菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('笔记'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '这里是一条阅读笔记');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      expect(await repository.readPreference('notes:reader'), contains('阅读笔记'));
      await tester.tap(find.byTooltip('阅读菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('目录 ·'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('书签'));
      await tester.pumpAndSettle();
      expect(find.textContaining('全书'), findsOneWidget);
      await tester.tap(find.text('笔记'));
      await tester.pumpAndSettle();
      expect(find.text('这里是一条阅读笔记'), findsOneWidget);
      await tester.tap(find.byTooltip('完成'));
      await tester.pumpAndSettle();
      await capture('reader-menu');
      await tester.tap(find.byTooltip('阅读菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('主题与设置'));
      await tester.pumpAndSettle();
      expect(find.text('纸张'), findsOneWidget);
      expect(find.text('滑动'), findsOneWidget);
      await tester.tap(find.text('滑动'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('淡入'));
      await tester.pumpAndSettle();
      expect(find.text('淡入'), findsOneWidget);
      await tester.tap(find.byTooltip('切换夜间模式'));
      await tester.pumpAndSettle();
      await capture('reader-theme');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      expect(await repository.readPreference('readerTurnMode'), 'fade');
      expect(await repository.readPreference('readerPaperTheme'), '1');
      expect(find.textContaining('目录 ·'), findsNothing);
      await tester.tap(find.byTooltip('阅读菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('目录 ·'));
      await tester.pumpAndSettle();
      expect(find.text('章节'), findsOneWidget);
      expect(find.text('书签'), findsOneWidget);
      expect(find.text('笔记'), findsOneWidget);
      await tester.tap(find.byTooltip('完成'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('阅读菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('在图书中搜索'));
      await tester.pumpAndSettle();
      expect(find.text('在此书中'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await db.close();
      });
    },
  );
}
