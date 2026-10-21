// Runs the real Rust engine through dart:ffi, rendering into memory (HushRenderer), so no test
// opens an audio device.
import 'dart:math';
import 'dart:typed_data';

import 'package:hush_audio/hush_audio.dart';
import 'package:test/test.dart';

const rate = 48000;

double rms(List<double> samples) =>
    sqrt(samples.fold<double>(0, (sum, s) => sum + s * s) / samples.length);

/// Upward zero crossings per second: higher for brighter noise.
double crossingRate(List<double> samples) => frequency(samples);

List<double> channel(Float32List interleaved, int which) => [
  for (var i = which; i < interleaved.length; i += 2) interleaved[i],
];

double peak(Iterable<double> samples) =>
    samples.fold(0, (m, s) => max(m, s.abs()));

/// Frequency from upward zero crossings over a span of samples.
double frequency(List<double> samples) {
  var crossings = 0;
  for (var i = 1; i < samples.length; i++) {
    if (samples[i - 1] < 0 && samples[i] >= 0) crossings++;
  }
  return crossings * rate / samples.length;
}

void main() {
  late HushEngine engine;
  late HushRenderer renderer;

  setUp(() {
    engine = HushEngine();
    renderer = HushRenderer(engine, sampleRate: rate);
  });

  tearDown(() {
    renderer.dispose();
    engine.dispose();
  });

  test('silent until play, then the default 852 Hz tone', () {
    expect(peak(renderer.render(rate ~/ 10)), 0);
    engine.play(fadeIn: const Duration(milliseconds: 10));
    renderer.render(rate ~/ 10); // let the fade-in finish
    final left = channel(renderer.render(rate), 0);
    expect(peak(left), greaterThan(0.2));
    expect(frequency(left), closeTo(852, 2));
    expect(engine.masterGain, closeTo(1, 1e-6));
  });

  test('the tone frequency control changes the pitch', () {
    engine
      ..toneFrequency = 432
      ..play(fadeIn: const Duration(milliseconds: 10));
    renderer.render(rate ~/ 2); // the frequency glides to its new value
    expect(frequency(channel(renderer.render(rate), 0)), closeTo(432, 2));
    expect(engine.toneFrequency, 432);
  });

  test('binaural puts a different frequency in each ear', () {
    engine
      ..toneFrequency = 200
      ..toneMode = ToneMode.binaural
      ..beatHz = 10
      ..play(fadeIn: const Duration(milliseconds: 10));
    renderer.render(rate ~/ 2);
    final block = renderer.render(rate);
    final difference =
        (frequency(channel(block, 1)) - frequency(channel(block, 0))).abs();
    expect(difference, closeTo(10, 2));
  });

  test('a fade-out ends in exact silence', () {
    engine.play(fadeIn: const Duration(milliseconds: 10));
    renderer.render(rate ~/ 10);
    engine.fadeOut(const Duration(milliseconds: 200));
    renderer.render(rate ~/ 2);
    expect(engine.masterGain, 0);
    expect(peak(renderer.render(rate ~/ 10)), 0);
  });

  test('noise and nature layers make sound with the tone off', () {
    engine
      ..toneEnabled = false
      ..noiseEnabled = true
      ..noiseColor = NoiseColor.pink
      ..setAmbient(Ambient.rain, 0.8)
      ..play(fadeIn: const Duration(milliseconds: 10));
    renderer.render(rate ~/ 2);
    final block = renderer.render(rate);
    expect(peak(block), greaterThan(0.05));
    expect(block.every((s) => s.isFinite && s.abs() <= 1), isTrue);
    expect(engine.ambientLevel(Ambient.rain), closeTo(0.8, 1e-6));
  });

  test('out-of-range and non-finite values are clamped or ignored, never break the audio', () {
    engine
      ..toneFrequency = 1e9
      ..toneLevel = -5
      ..beatHz = double.nan
      ..noiseLevel = double.infinity
      ..play(fadeIn: const Duration(milliseconds: 10));
    expect(engine.toneFrequency, 2000);
    expect(engine.toneLevel, 0);
    expect(engine.beatHz, 6, reason: 'NaN leaves the previous value');
    expect(engine.noiseLevel, closeTo(0.4, 1e-6));
    final block = renderer.render(rate);
    expect(block.every((s) => s.isFinite), isTrue);
  });

  test('getters report what the engine holds, even past the f32 range', () {
    // 1e39 fits a Dart double but overflows the f32 the engine stores, so it is ignored there.
    engine.toneFrequency = 1e39;
    expect(engine.toneFrequency, 852);
    engine
      ..swell = true
      ..spatial = true
      ..toneEnabled = false;
    expect(
      [engine.swell, engine.spatial, engine.toneEnabled],
      [true, true, false],
    );
  });

  test('every enum value round-trips through the engine', () {
    for (final mode in ToneMode.values) {
      engine.toneMode = mode;
      expect(engine.toneMode, mode);
    }
    for (final color in NoiseColor.values) {
      engine.noiseColor = color;
      expect(engine.noiseColor, color);
    }
    for (final kind in Ambient.values) {
      engine.setAmbient(kind, 0.3);
      expect(engine.ambientLevel(kind), closeTo(0.3, 1e-6));
    }
  });

  test('noise colours map to the right sound: brown, pink, white, blue, violet get brighter', () {
    engine
      ..toneEnabled = false
      ..noiseEnabled = true
      ..play(fadeIn: const Duration(milliseconds: 10));
    final rates = <NoiseColor, double>{};
    for (final color in [
      NoiseColor.brown,
      NoiseColor.pink,
      NoiseColor.white,
      NoiseColor.blue,
      NoiseColor.violet,
    ]) {
      engine.noiseColor = color;
      renderer.render(rate ~/ 2); // past the colour change dip
      rates[color] = crossingRate(channel(renderer.render(rate), 0));
    }
    final ordered = rates.values.toList();
    for (var i = 1; i < ordered.length; i++) {
      expect(ordered[i], greaterThan(ordered[i - 1]), reason: '$rates');
    }
  });

  test('every nature sound plays on its own', () {
    engine
      ..toneEnabled = false
      ..play(fadeIn: const Duration(milliseconds: 10));
    for (final kind in Ambient.values) {
      for (final other in Ambient.values) {
        engine.setAmbient(other, other == kind ? 1 : 0);
      }
      renderer.render(rate); // settle the level smoothing
      expect(peak(renderer.render(rate)), greaterThan(0.01), reason: kind.name);
    }
  });

  test('isochronic mode pulses the tone on and off; steady does not', () {
    engine
      ..toneFrequency = 400
      ..beatHz = 4
      ..play(fadeIn: const Duration(milliseconds: 10));
    renderer.render(rate ~/ 2);
    double quietestWindow() {
      final left = channel(renderer.render(rate), 0);
      const window = rate ~/ 100; // 10 ms
      var quietest = double.infinity;
      for (var i = 0; i + window <= left.length; i += window) {
        quietest = min(quietest, rms(left.sublist(i, i + window)));
      }
      return quietest;
    }

    final steady = quietestWindow();
    engine.toneMode = ToneMode.isochronic;
    renderer.render(rate ~/ 2);
    final pulsed = quietestWindow();
    expect(steady, greaterThan(0.1));
    expect(pulsed, lessThan(steady / 10));
  });

  test('the range constants match the engine', () {
    engine.toneFrequency = 0;
    expect(engine.toneFrequency, HushEngine.minToneHz);
    engine.toneFrequency = 1e6;
    expect(engine.toneFrequency, HushEngine.maxToneHz);
    engine.beatHz = 0;
    expect(engine.beatHz, HushEngine.minBeatHz);
    engine.beatHz = 1e6;
    expect(engine.beatHz, HushEngine.maxBeatHz);
  });

  test('a renderer needs a positive sample rate', () {
    expect(() => HushRenderer(engine, sampleRate: 0), throwsArgumentError);
    expect(() => HushRenderer(engine, sampleRate: -44100), throwsArgumentError);
    expect(renderer.render(0), isEmpty);
  });

  test('a disposed engine refuses further use', () {
    final other = HushEngine()..dispose();
    expect(() => other.toneFrequency = 440, throwsStateError);
    expect(() => HushRenderer(other), throwsStateError);
    other.dispose(); // twice is harmless
  });
}
