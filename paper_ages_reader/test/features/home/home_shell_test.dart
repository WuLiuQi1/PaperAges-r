import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/main.dart';
import 'package:paper_ages_reader/core/storage/app_database.dart';
import 'package:paper_ages_reader/core/ui/books_navigation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final variant in [(390.0, Brightness.light), (320.0, Brightness.dark)]) {
    testWidgets('phone ${variant.$1} ${variant.$2} tabs, search and menus', (
      tester,
    ) async {
      final directory = Directory.systemTemp.createTempSync('paper-ages-ui-');
      addTearDown(() => directory.deleteSync(recursive: true));
      File('${directory.path}/paper_ages_state.json').writeAsStringSync(
        jsonEncode({
          'schemaVersion': 5,
          'books': [
            for (var i = 0; i < 2; i++)
              {
                'id': 'test-$i',
                'kind': 'text',
                'title': ['山海拾记', '沿着河流走'][i],
                'filePath': '${directory.path}/test-$i.txt',
                'fingerprint': 'test-$i',
                'createdAtMillis': i,
                'encoding': 'UTF-8',
              },
          ],
          'positions': {
            'test-0': {
              'blockIndex': 2,
              'totalBlocks': 100,
              'revision': 1,
              'updatedAtMillis': 100,
            },
          },
          'preferences': {},
          'sources': [],
          'networkBooks': [
            {
              'title': '云端春秋',
              'author': '测试作者',
              'sourceUrl': 'https://source.example',
              'locator': 'https://source.example/book/1',
            },
          ],
          'readingStatistics': {},
        }),
      );
      tester.view.physicalSize = Size(variant.$1, 844);
      tester.platformDispatcher.platformBrightnessTestValue = variant.$2;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => directory.path,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final boundary = GlobalKey();
      const captureFont = String.fromEnvironment('CAPTURE_FONT');
      if (captureFont.isNotEmpty) {
        await tester.runAsync(() async {
          final bytes = ByteData.sublistView(
            await File(captureFont).readAsBytes(),
          );
          for (final family in ['Roboto', 'Ahem']) {
            await (FontLoader(family)..addFont(Future.value(bytes))).load();
          }
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
                rootBundle.load(
                  'packages/cupertino_icons/assets/CupertinoIcons.ttf',
                ),
              ))
              .load();
        });
      }
      final database = await tester.runAsync(
        () => AppDatabase.openFile(
          File('${directory.path}/paper_ages_state.json'),
        ),
      );
      addTearDown(() => database!.close());
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: PaperAgesApp(database: database),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.runAsync(() => tester.pumpAndSettle());
      expect(find.text('继续阅读'), findsWidgets);
      expect(find.text('阅读目标'), findsWidgets);
      expect(find.text('之前读过'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ListView && widget.scrollDirection == Axis.horizontal,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      Future<void> capture(String name) async {
        if (!const bool.fromEnvironment('CAPTURE_UI')) return;
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/ui-review').create(recursive: true);
          await File(
            'build/ui-review/$name-${variant.$1.toInt()}-${variant.$2.name}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('home');
      await tester.tap(find.text('书库').last);
      await tester.runAsync(() => tester.pumpAndSettle());
      expect(find.byTooltip('交互样板'), findsNothing);
      expect(tester.takeException(), isNull);
      await capture('library');
      await tester.tap(find.byTooltip('列表视图'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(3));
      expect(find.text('云端春秋'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('网格视图'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('书库更多操作'));
      await tester.runAsync(() => tester.pumpAndSettle());
      expect(find.text('书源管理'), findsOneWidget);
      expect(find.text('导入书籍'), findsOneWidget);
      await tester.tapAt(const Offset(20, 300));
      await tester.runAsync(() => tester.pumpAndSettle());
      await tester.tap(find.text('搜索').last);
      await tester.runAsync(() => tester.pumpAndSettle());
      expect(find.text('搜索'), findsWidgets);
      expect(find.text('请先从右上角导入并启用书源。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture('search');
      expect(find.byKey(const Key('online-search-field')), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(find.byType(BooksNavigation), findsNothing);
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpWidget(const SizedBox());
    });
  }
}
