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
  });

  final String engineId;
  final String voiceId;
  final bool installed;
  final bool requiresNetwork;

  bool get isUsableOffline => installed && !requiresNetwork;
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
