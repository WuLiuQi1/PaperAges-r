import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/themes/domain/theme_draft.dart';

void main() {
  const base = ReaderTheme(
    backgroundArgb: 0xff111111,
    textArgb: 0xffeeeeee,
    fontSize: 18,
    lineHeight: 1.5,
  );

  test('cancel returns the original theme after a draft preview', () {
    final draft = ThemeDraft.begin(base)
        .update(fontSize: 24, fontId: 'local-font');

    expect(draft.cancel(), same(base));
    expect(draft.confirm().fontSize, 24);
  });

  test('only layout-affecting changes advance layout generation', () {
    final draft = ThemeDraft.begin(base);

    expect(draft.update(textArgb: 0xffcccccc).layoutGeneration, 0);
    expect(draft.update(lineHeight: 1.8).layoutGeneration, 1);
  });
}
