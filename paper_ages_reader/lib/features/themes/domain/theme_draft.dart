class ReaderTheme {
  const ReaderTheme({
    required this.backgroundArgb,
    required this.textArgb,
    required this.fontSize,
    required this.lineHeight,
    this.fontId,
  });

  final int backgroundArgb;
  final int textArgb;
  final double fontSize;
  final double lineHeight;
  final String? fontId;
}

/// A theme edit never persists until [confirm]. Color-only changes should not
/// trigger a relayout; metric or font changes must advance the layout version.
class ThemeDraft {
  const ThemeDraft._({
    required this.original,
    required this.value,
    required this.layoutGeneration,
  });

  factory ThemeDraft.begin(ReaderTheme theme) =>
      ThemeDraft._(original: theme, value: theme, layoutGeneration: 0);

  final ReaderTheme original;
  final ReaderTheme value;
  final int layoutGeneration;

  ThemeDraft update({
    int? backgroundArgb,
    int? textArgb,
    double? fontSize,
    double? lineHeight,
    String? fontId,
    bool clearFont = false,
  }) {
    final next = ReaderTheme(
      backgroundArgb: backgroundArgb ?? value.backgroundArgb,
      textArgb: textArgb ?? value.textArgb,
      fontSize: fontSize ?? value.fontSize,
      lineHeight: lineHeight ?? value.lineHeight,
      fontId: clearFont ? null : fontId ?? value.fontId,
    );
    final affectsLayout =
        next.fontSize != value.fontSize ||
        next.lineHeight != value.lineHeight ||
        next.fontId != value.fontId;
    return ThemeDraft._(
      original: original,
      value: next,
      layoutGeneration: layoutGeneration + (affectsLayout ? 1 : 0),
    );
  }

  ReaderTheme confirm() => value;

  ReaderTheme cancel() => original;
}
