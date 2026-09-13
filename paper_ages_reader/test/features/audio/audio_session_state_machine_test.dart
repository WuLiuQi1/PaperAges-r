import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/audio/domain/audio_session_state_machine.dart';

void main() {
  const offlineVoice = VoiceDescriptor(
    engineId: 'system',
    voiceId: 'zh-offline',
    installed: true,
    requiresNetwork: false,
  );

  test('only an installed offline voice can enter text preparation', () {
    const onlineVoice = VoiceDescriptor(
      engineId: 'system',
      voiceId: 'zh-online',
      installed: true,
      requiresNetwork: true,
    );

    expect(
      AudioSessionStateMachine.idle().start(onlineVoice).state.phase,
      PlaybackPhase.unavailableOffline,
    );
    expect(
      AudioSessionStateMachine.idle().start(offlineVoice).state.phase,
      PlaybackPhase.preparingText,
    );
  });

  test('only the current generation can turn prepared text into playback', () {
    final session = AudioSessionStateMachine.idle().start(offlineVoice);

    expect(session.textPrepared(session.state.generation - 1), same(session));
    expect(
      session.textPrepared(session.state.generation).state.phase,
      PlaybackPhase.playing,
    );
  });

  test('stop invalidates old completion callbacks', () {
    final playing = AudioSessionStateMachine.idle()
        .start(offlineVoice)
        .textPrepared(1);
    final stopped = playing.stop();

    expect(stopped.completed(playing.state.generation), same(stopped));
    expect(stopped.state.phase, PlaybackPhase.idle);
  });

  test(
    'interruption pauses a playing session without accepting stale callbacks',
    () {
      final playing = AudioSessionStateMachine.idle()
          .start(offlineVoice)
          .textPrepared(1);
      final interrupted = playing.interrupted();

      expect(interrupted.state.phase, PlaybackPhase.interrupted);
      expect(interrupted.completed(0), same(interrupted));
    },
  );
}
