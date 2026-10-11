/// Calm and sleep sound engine for Flutter, powered by Rust.
///
/// Pure tones, binaural and isochronic beats, seven colours of noise and five procedural nature
/// sounds, synthesized live by [hush-core](https://github.com/abiodunosagie/hush-core) on the
/// device's audio thread. Nothing is a recording, so nothing loops.
///
/// ```dart
/// final engine = HushEngine()
///   ..toneFrequency = 852
///   ..toneMode = ToneMode.binaural
///   ..beatHz = 6;
/// engine.start();                                   // opens the speaker, still silent
/// engine.play(fadeIn: const Duration(seconds: 2));  // fades in
/// // later
/// engine.fadeOut(const Duration(minutes: 10));      // sleep fade
/// engine.dispose();
/// ```
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'src/bindings.dart' as native;

/// How the tone is presented.
enum ToneMode {
  /// One clean tone, the same in both ears.
  steady,

  /// A slightly different frequency in each ear, beating at [HushEngine.beatHz]. Headphones only.
  binaural,

  /// The tone pulses on and off at [HushEngine.beatHz]. Works on speakers.
  isochronic,
}

/// Noise colours, level-matched so switching colour does not change the loudness.
enum NoiseColor { brown, pink, white, green, blue, violet, grey }

/// Procedural nature sounds; any number can play at once.
enum Ambient { rain, ocean, wind, fire, stream }

/// Thrown when the device's audio output cannot be opened.
class HushAudioException implements Exception {
  const HushAudioException(this.message);
  final String message;
  @override
  String toString() => 'HushAudioException: $message';
}

final _paramsFinalizer = NativeFinalizer(
  Native.addressOf<NativeFunction<Void Function(Pointer<native.Params>)>>(
    native.hush_params_free,
  ).cast(),
);

/// The sound engine: its controls, and optionally a live output to the speaker.
///
/// Controls can be changed at any time, playing or not, and take effect within one audio block;
/// every change is smoothed by the engine, so sliders never click. Values outside a control's
/// range are clamped and non-finite values are ignored.
///
/// Create, [start], [stop] and [dispose] an engine on the same isolate (normally the main one):
/// the macOS and iOS audio stream must be released on the thread that opened it.
final class HushEngine implements Finalizable {
  HushEngine() : _params = native.hush_params_new() {
    _paramsFinalizer.attach(this, _params.cast(), detach: this);
  }

  final Pointer<native.Params> _params;
  Pointer<native.Player> _player = nullptr;
  bool _disposed = false;

  double _toneFrequency = 852;
  double _toneLevel = 0.6;
  ToneMode _toneMode = ToneMode.steady;
  double _beatHz = 6;
  bool _toneEnabled = true;
  bool _noiseEnabled = false;
  NoiseColor _noiseColor = NoiseColor.brown;
  double _noiseLevel = 0.4;
  bool _swell = false;
  bool _spatial = false;
  final _ambient = <Ambient, double>{};

  Pointer<native.Params> get _live {
    if (_disposed) throw StateError('HushEngine was disposed');
    return _params;
  }

  // ---- output

  /// Whether the speaker output is open.
  bool get isStarted => _player != nullptr;

  /// The output sample rate in Hz, or null before [start].
  int? get sampleRate =>
      isStarted ? native.hush_player_sample_rate(_player) : null;

  /// Opens the default audio output. The engine stays silent until [play]. Does nothing if
  /// already started.
  ///
  /// Throws [HushAudioException] if no output device could be opened.
  void start() {
    if (isStarted) return;
    final player = native.hush_player_new(_live);
    if (player == nullptr) {
      throw const HushAudioException('could not open the audio output');
    }
    _player = player;
  }

  /// Closes the audio output at once. To end gently, call [fadeOut] first and stop once
  /// [masterGain] reaches 0.
  void stop() {
    if (!isStarted) return;
    native.hush_player_free(_player);
    _player = nullptr;
  }

  /// Fades in over [fadeIn] (default two seconds).
  void play({Duration fadeIn = const Duration(seconds: 2)}) =>
      native.hush_params_play(_live, _seconds(fadeIn));

  /// Fades to silence over [duration], for example ten minutes at the end of a sleep timer.
  void fadeOut(Duration duration) =>
      native.hush_params_fade_out(_live, _seconds(duration));

  /// The master gain the engine last rendered, 0 to 1. Rises during a fade-in and is exactly 0
  /// once a fade-out has finished.
  double get masterGain => native.hush_params_master_gain(_live);

  // ---- tone

  bool get toneEnabled => _toneEnabled;
  set toneEnabled(bool on) {
    native.hush_params_set_tone_enabled(_live, on);
    _toneEnabled = on;
  }

  /// Tone frequency in Hz, 20 to 2000. The default is 852 Hz.
  double get toneFrequency => _toneFrequency;
  set toneFrequency(double hz) {
    native.hush_params_set_tone_frequency(_live, hz);
    if (hz.isFinite) _toneFrequency = hz.clamp(20, 2000).toDouble();
  }

  /// Tone volume, 0 to 1.
  double get toneLevel => _toneLevel;
  set toneLevel(double level) {
    native.hush_params_set_tone_level(_live, level);
    if (level.isFinite) _toneLevel = level.clamp(0, 1).toDouble();
  }

  ToneMode get toneMode => _toneMode;
  set toneMode(ToneMode mode) {
    native.hush_params_set_tone_mode(_live, mode.index);
    _toneMode = mode;
  }

  /// Pulse rate in Hz for binaural and isochronic modes, 0.5 to 40.
  double get beatHz => _beatHz;
  set beatHz(double hz) {
    native.hush_params_set_beat_hz(_live, hz);
    if (hz.isFinite) _beatHz = hz.clamp(0.5, 40).toDouble();
  }

  // ---- noise and nature

  bool get noiseEnabled => _noiseEnabled;
  set noiseEnabled(bool on) {
    native.hush_params_set_noise_enabled(_live, on);
    _noiseEnabled = on;
  }

  NoiseColor get noiseColor => _noiseColor;
  set noiseColor(NoiseColor color) {
    native.hush_params_set_noise_color(_live, color.index);
    _noiseColor = color;
  }

  /// Noise volume, 0 to 1.
  double get noiseLevel => _noiseLevel;
  set noiseLevel(double level) {
    native.hush_params_set_noise_level(_live, level);
    if (level.isFinite) _noiseLevel = level.clamp(0, 1).toDouble();
  }

  /// Volume of one nature sound, 0 to 1; 0 turns it off.
  double ambientLevel(Ambient kind) => _ambient[kind] ?? 0;
  void setAmbient(Ambient kind, double level) {
    native.hush_params_set_ambient(_live, kind.index, level);
    if (level.isFinite) _ambient[kind] = level.clamp(0, 1).toDouble();
  }

  /// A slow breathing swell in the volume, six breaths a minute.
  bool get swell => _swell;
  set swell(bool on) {
    native.hush_params_set_swell(_live, on);
    _swell = on;
  }

  /// Noise and nature sounds sweep slowly from side to side; the tone stays centred.
  bool get spatial => _spatial;
  set spatial(bool on) {
    native.hush_params_set_spatial(_live, on);
    _spatial = on;
  }

  // ---- lifecycle

  /// Stops the output and frees the engine. The engine cannot be used afterwards.
  void dispose() {
    if (_disposed) return;
    stop();
    _paramsFinalizer.detach(this);
    native.hush_params_free(_params);
    _disposed = true;
  }

  static double _seconds(Duration d) =>
      d.inMicroseconds / Duration.microsecondsPerSecond;
}

final _offlineFinalizer = NativeFinalizer(
  Native.addressOf<NativeFunction<Void Function(Pointer<native.Offline>)>>(
    native.hush_offline_free,
  ).cast(),
);

/// Renders an engine's sound into memory instead of the speaker: for tests, previews and
/// exporting audio. It follows the engine's controls like a live output would.
final class HushRenderer implements Finalizable {
  /// Creates a renderer for [engine] at [sampleRate] Hz.
  HushRenderer(HushEngine engine, {this.sampleRate = 48000})
    : _offline = native.hush_offline_new(engine._live, sampleRate.toDouble()) {
    _offlineFinalizer.attach(this, _offline.cast(), detach: this);
  }

  final int sampleRate;
  final Pointer<native.Offline> _offline;
  bool _disposed = false;

  /// Renders the next [frames] frames as interleaved stereo: left, right, left, right.
  Float32List render(int frames) {
    if (_disposed) throw StateError('HushRenderer was disposed');
    if (frames <= 0) return Float32List(0);
    final buffer = calloc<Float>(frames * 2);
    try {
      native.hush_offline_render(_offline, buffer, frames);
      return Float32List.fromList(buffer.asTypedList(frames * 2));
    } finally {
      calloc.free(buffer);
    }
  }

  void dispose() {
    if (_disposed) return;
    _offlineFinalizer.detach(this);
    native.hush_offline_free(_offline);
    _disposed = true;
  }
}
