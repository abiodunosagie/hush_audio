// Runs the real Rust engine through dart:ffi, rendering into memory (HushRenderer), so no test
// opens an audio device.
import 'dart:math';
import 'dart:typed_data';

import 'package:hush_audio/hush_audio.dart';
import 'package:test/test.dart';

const rate = 48000;

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
    expect(engine.ambientLevel(Ambient.rain), 0.8);
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
    expect(engine.noiseLevel, 0.4);
    final block = renderer.render(rate);
    expect(block.every((s) => s.isFinite), isTrue);
  });

  test('a disposed engine refuses further use', () {
    final other = HushEngine()..dispose();
    expect(() => other.toneFrequency = 440, throwsStateError);
    expect(() => HushRenderer(other), throwsStateError);
    other.dispose(); // twice is harmless
  });
}
