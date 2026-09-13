enum PlaybackPhase {
  idle,
  preparingVoice,
  preparingText,
  playing,
  paused,
  interrupted,
  unavailableOffline,
  failed,
  completed,
}

class VoiceDescriptor {
  const VoiceDescriptor({
    required this.engineId,
    required this.voiceId,
    required this.installed,
    required this.requiresNetwork,
    this.locale = 'und',
    this.availabilityReason,
  });

  final String engineId;
  final String voiceId;
  final bool installed;
  final bool requiresNetwork;
  final String locale;
  final String? availabilityReason;

  bool get isUsableOffline => installed && !requiresNetwork;
}

/// A stable text coordinate. It deliberately refers to normalized content,
/// never a rendered page, so appearance changes cannot restart narration.
class SpeechAnchor {
  const SpeechAnchor({required this.chapterKey, required this.sentenceIndex});

  final String chapterKey;
  final int sentenceIndex;
}

class SpeechSentence {
  const SpeechSentence(this.text, this.anchor);

  final String text;
  final SpeechAnchor anchor;
}

/// Small deterministic segmenter for the synthesis queue. It covers Chinese
/// punctuation, ordinary Latin sentence endings and bounds very long runs.
class SpeechTextNormalizer {
  const SpeechTextNormalizer({this.maximumSentenceLength = 280});

  final int maximumSentenceLength;

  List<SpeechSentence> segment(String chapterKey, String raw) {
    final normalized = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return const [];
    final chunks = <String>[];
    var start = 0;
    for (var index = 0; index < normalized.length; index++) {
      final character = normalized[index];
      final boundary = '。！？；.!?;'.contains(character);
      if (boundary || index - start + 1 >= maximumSentenceLength) {
        final value = normalized.substring(start, index + 1).trim();
        if (value.isNotEmpty) chunks.add(value);
        start = index + 1;
      }
    }
    final tail = normalized.substring(start).trim();
    if (tail.isNotEmpty) chunks.add(tail);
    return List.unmodifiable([
      for (var i = 0; i < chunks.length; i++)
        SpeechSentence(
          chunks[i],
          SpeechAnchor(chapterKey: chapterKey, sentenceIndex: i),
        ),
    ]);
  }
}

class AudioSessionState {
  const AudioSessionState({required this.generation, required this.phase});

  final int generation;
  final PlaybackPhase phase;
}

/// Platform-neutral guard for TTS callbacks.
///
/// Native Android/iOS adapters own actual synthesis and media sessions. This
/// state machine makes an old callback harmless after a user changes book,
/// stops playback, or begins a newer session.
class AudioSessionStateMachine {
  const AudioSessionStateMachine(this.state);

  final AudioSessionState state;

  factory AudioSessionStateMachine.idle() => const AudioSessionStateMachine(
    AudioSessionState(generation: 0, phase: PlaybackPhase.idle),
  );

  AudioSessionStateMachine start(VoiceDescriptor voice) {
    final phase = voice.isUsableOffline
        ? PlaybackPhase.preparingText
        : PlaybackPhase.unavailableOffline;
    return AudioSessionStateMachine(
      AudioSessionState(generation: state.generation + 1, phase: phase),
    );
  }

  AudioSessionStateMachine textPrepared(int callbackGeneration) =>
      _fromCurrentCallback(callbackGeneration, PlaybackPhase.playing);

  AudioSessionStateMachine pause() {
    if (state.phase != PlaybackPhase.playing) return this;
    return AudioSessionStateMachine(
      AudioSessionState(
        generation: state.generation,
        phase: PlaybackPhase.paused,
      ),
    );
  }

  AudioSessionStateMachine interrupted() {
    if (state.phase != PlaybackPhase.playing) return this;
    return AudioSessionStateMachine(
      AudioSessionState(
        generation: state.generation,
        phase: PlaybackPhase.interrupted,
      ),
    );
  }

  AudioSessionStateMachine completed(int callbackGeneration) =>
      _fromCurrentCallback(callbackGeneration, PlaybackPhase.completed);

  AudioSessionStateMachine stop() => AudioSessionStateMachine(
    AudioSessionState(
      generation: state.generation + 1,
      phase: PlaybackPhase.idle,
    ),
  );

  AudioSessionStateMachine _fromCurrentCallback(
    int callbackGeneration,
    PlaybackPhase nextPhase,
  ) {
    if (callbackGeneration != state.generation) return this;
    return AudioSessionStateMachine(
      AudioSessionState(generation: state.generation, phase: nextPhase),
    );
  }
}
