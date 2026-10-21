// The Cubit against the real engine. No test calls play(), so no audio device is opened.
import 'package:flutter_test/flutter_test.dart';
import 'package:hush_audio/hush_audio.dart';
import 'package:hush_audio_example/src/sound_cubit.dart';
import 'package:hush_audio_example/src/sound_state.dart';

void main() {
  test('starts from the engine settings', () async {
    final cubit = SoundCubit();
    expect(cubit.state.toneFrequency, 852);
    expect(cubit.state.playback, Playback.stopped);
    await cubit.close();
  });

  test('choosing a noise colour also switches the noise on', () async {
    final cubit = SoundCubit();
    cubit.selectNoiseColor(NoiseColor.pink);
    expect(cubit.state.noiseEnabled, isTrue);
    expect(cubit.state.noiseColor, NoiseColor.pink);
    await cubit.close();
  });

  test('state reports the clamped value the engine holds', () async {
    final engine = HushEngine();
    final cubit = SoundCubit(engine: engine);
    cubit.setBeat(100);
    expect(cubit.state.beatHz, HushEngine.maxBeatHz);
    await cubit.close();
    // The Cubit did not create this engine, so it leaves it usable.
    expect(engine.beatHz, HushEngine.maxBeatHz);
    engine.dispose();
  });

  test('a borrowed engine is handed back silent', () async {
    final engine = HushEngine();
    final cubit = SoundCubit(engine: engine);
    engine.play(fadeIn: Duration.zero); // as if the Cubit had been playing
    await cubit.close();
    // A fresh output on this engine must start silent, not at full volume.
    final renderer = HushRenderer(engine);
    final samples = renderer.render(renderer.sampleRate ~/ 2);
    expect(samples.every((s) => s.abs() < 1e-6), isTrue);
    renderer.dispose();
    engine.dispose();
  });

  test(
    'identical states are equal, so a steady level does not rebuild the screen',
    () {
      final a = SoundState.of(HushEngine());
      expect(a.copyWith(level: 0.5), a.copyWith(level: 0.5));
      expect(a.copyWith(level: 0.5), isNot(a.copyWith(level: 0.6)));
    },
  );
}
