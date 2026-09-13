import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/audio/domain/audio_session_state_machine.dart';

void main() {
  test('creates normalized sentence anchors independent of layout', () {
    final segments = const SpeechTextNormalizer().segment(
      'chapter-1',
      ' 第一段。\nSecond sentence!  最后一段 ',
    );
    expect(segments.map((value) => value.text), [
      '第一段。',
      'Second sentence!',
      '最后一段',
    ]);
    expect(segments.map((value) => value.anchor.sentenceIndex), [0, 1, 2]);
    expect(
      segments.every((value) => value.anchor.chapterKey == 'chapter-1'),
      isTrue,
    );
  });

  test('bounds an unpunctuated long paragraph', () {
    final segments = const SpeechTextNormalizer(maximumSentenceLength: 3)
        .segment('chapter', 'abcdefg');
    expect(segments.map((value) => value.text), ['abc', 'def', 'g']);
  });
}
