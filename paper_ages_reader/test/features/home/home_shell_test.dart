import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('phone tabs retain usable headers and library actions', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('paper-ages-ui-');
    addTearDown(() => directory.deleteSync(recursive: true));
    tester.view.physicalSize = const Size(390, 844);
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
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
              rootBundle.load(
                'packages/cupertino_icons/assets/CupertinoIcons.ttf',
              ),
            ))
            .load();
      });
    }
    await tester.pumpWidget(
      RepaintBoundary(key: boundary, child: const PaperAgesApp()),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('阅读目标'), findsOneWidget);
    expect(tester.takeException(), isNull);
    Future<void> capture(String name) async {
      if (!const bool.fromEnvironment('CAPTURE_UI')) return;
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/ui-review').create(recursive: true);
        await File('build/ui-review/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('home');
    await tester.tap(find.text('书库').last);
    await tester.pumpAndSettle();
    expect(find.text('导入书籍'), findsOneWidget);
    expect(find.byTooltip('交互样板'), findsNothing);
    expect(tester.takeException(), isNull);
    await capture('library');
    await tester.tap(find.byTooltip('书库更多操作'));
    await tester.pumpAndSettle();
    expect(find.text('书源管理'), findsOneWidget);
    await tester.tapAt(const Offset(20, 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索').last);
    await tester.pumpAndSettle();
    expect(find.text('搜索在线书源'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture('search');
    await tester.pumpWidget(const SizedBox());
  });
}
