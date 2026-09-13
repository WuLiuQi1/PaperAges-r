import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/reader_document/domain/normalized_text_document.dart';
import 'package:paper_ages_reader/features/reader_document/presentation/viewport_paginator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const size = Size(320, 550);
  const style = TextStyle(fontSize: 18, height: 1.45);
  test('paragraphs flow across pages without losing or duplicating text', () {
    final raw = List.generate(
      100,
      (i) => '第$i段。中文正文与👨‍👩‍👧‍👦一起排版。',
    ).join('\n\n');
    final paginator = ViewportPaginator(const TextNormalizer().normalize(raw));
    final pages = <TextPage>[];
    var offset = 0;
    while (offset < raw.length) {
      final page = paginator.page(offset, size, style, TextScaler.noScaling);
      expect(page.end, greaterThan(offset));
      pages.add(page);
      offset = page.end;
    }
    expect(pages.map((p) => p.text).join(), raw);
    expect(pages.length, lessThan(100));
    expect(pages.first.text.split('\n').length, greaterThan(2));
    for (final page in pages) {
      final anchor = paginator.anchorFor(page.start);
      expect(paginator.offsetFor(anchor.block, anchor.offset), page.start);
    }
  });
  test('backwards pagination ends exactly at the current anchor', () {
    final paginator = ViewportPaginator(
      const TextNormalizer().normalize('文字内容。' * 3000),
    );
    final first = paginator.page(0, size, style, TextScaler.noScaling);
    final second = paginator.page(first.end, size, style, TextScaler.noScaling);
    final previous = paginator.previous(
      second.start,
      size,
      style,
      TextScaler.noScaling,
    );
    expect(previous.end, second.start);
    expect(previous.start, 0);
    expect(previous.text, first.text);
    final large = paginator.page(
      second.start,
      size,
      style.copyWith(fontSize: 30),
      TextScaler.noScaling,
    );
    expect(large.start, second.start);
    expect(large.text.length, lessThan(second.text.length));
  });
}
