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
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'src/bindings.dart' as native;

/// How the tone is presented. The order matches hush-core's `ToneMode`.
enum ToneMode {
  /// One clean tone, the same in both ears.
  steady,

  /// A slightly different frequency in each ear, beating at [HushEngine.beatHz]. Headphones only.
  binaural,

  /// The tone pulses on and off at [HushEngine.beatHz]. Works on speakers.
  isochronic,
}

/// Noise colours, level-matched so switching colour does not change the loudness. The order
/// matches hush-core's `NoiseColor`.
enum NoiseColor { brown, pink, white, green, blue, violet, grey }

/// Procedural nature sounds; any number can play at once. The order matches hush-core's
/// `AmbientKind`.
enum Ambient { rain, ocean, wind, fire, stream }

/// Thrown when the device's audio output cannot be opened.
class HushAudioException implements Exception {
  const HushAudioException(this.message);

  /// Why the output could not be opened, for example "no audio output device".
  final String message;

  @override
  String toString() => 'HushAudioException: $message';
}

final _paramsFinalizer = NativeFinalizer(
  Native.addressOf<NativeFunction<Void Function(Pointer<native.Params>)>>(
    native.hush_params_free,
  ).cast(),
);

// A forgotten engine's output is released by this finalizer. Off the thread that opened it,
// Rust silences the stream instead of dropping it, so a lost engine goes quiet rather than
// playing on.
final _playerFinalizer = NativeFinalizer(
  Native.addressOf<NativeFunction<Void Function(Pointer<native.Player>)>>(
    native.hush_player_free,
  ).cast(),
);

/// The sound engine: its controls, and optionally a live output to the speaker.
///
/// Controls can be changed at any time, playing or not, and take effect within one audio block;
/// every change is smoothed by the engine, so sliders never click. Values outside a control's
/// range are clamped and non-finite values are ignored; the getters always return what the
/// engine actually holds.
///
/// Create, [start], [stop] and [dispose] an engine on the main isolate: it stays on one thread,
/// and the macOS and iOS audio stream must be released on the thread that opened it (released
/// anywhere else, it is silenced instead of freed). Using another isolate throws. Always call
/// [dispose]; an engine that is garbage-collected while started falls silent, but its stream is
/// only reclaimed when the app exits.
final class HushEngine implements Finalizable {
  HushEngine() : _params = native.hush_params_new() {
    _paramsFinalizer.attach(this, _params.cast(), detach: this);
  }

  /// Accepted tone frequencies in Hz. Mirrors hush-core's `TONE_RANGE`; a test checks it.
  static const double minToneHz = 20, maxToneHz = 2000;

  /// Accepted pulse rates in Hz. Mirrors hush-core's `BEAT_RANGE`; a test checks it.
  static const double minBeatHz = 0.5, maxBeatHz = 40;

  final Pointer<native.Params> _params;
  final SendPort _ownerPort = Isolate.current.controlPort;
  Pointer<native.Player> _player = nullptr;

  /// Detach token for the player finalizer, separate from the params one.
  final Object _playerToken = Object();
  bool _disposed = false;

  Pointer<native.Params> get _live {
    if (_disposed) throw StateError('HushEngine was disposed');
    return _params;
  }

  void _checkIsolate() {
    if (Isolate.current.controlPort != _ownerPort) {
      throw StateError(
        'start and stop a HushEngine on the isolate that created it',
      );
    }
  }

  // ---- output

  /// Whether the speaker output is open.
  bool get isStarted => _player != nullptr;

  /// False once the audio device has reported an error, for example when headphones are
  /// unplugged mid-play. Call [stop] and [start] again to recover. Null before [start].
  bool? get isHealthy =>
      isStarted ? native.hush_player_is_healthy(_player) : null;

  /// The output sample rate in Hz, or null before [start].
  int? get sampleRate =>
      isStarted ? native.hush_player_sample_rate(_player) : null;

  /// Opens the default audio output. The engine stays silent until [play]. Does nothing if
  /// already started.
  ///
  /// Throws [HushAudioException] if no output device could be opened.
  void start() {
    if (isStarted) return;
    _checkIsolate();
    final player = native.hush_player_new(_live);
    if (player == nullptr) {
      throw HushAudioException(native.hush_last_error().toDartString());
    }
    _player = player;
    _playerFinalizer.attach(this, player.cast(), detach: _playerToken);
  }

  /// Closes the audio output at once. To end gently, call [fadeOut] first and stop once
  /// [masterGain] reaches 0.
  void stop() {
    if (!isStarted) return;
    _checkIsolate();
    _playerFinalizer.detach(_playerToken);
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

  /// Whether the tone plays.
  bool get toneEnabled => native.hush_params_tone_enabled(_live);
  set toneEnabled(bool on) => native.hush_params_set_tone_enabled(_live, on);

  /// Tone frequency in Hz, 20 to 2000. The default is 852 Hz.
  double get toneFrequency => native.hush_params_tone_frequency(_live);
  set toneFrequency(double hz) =>
      native.hush_params_set_tone_frequency(_live, hz);

  /// Tone volume, 0 to 1.
  double get toneLevel => native.hush_params_tone_level(_live);
  set toneLevel(double level) =>
      native.hush_params_set_tone_level(_live, level);

  /// How the tone reaches the ears: steady, binaural or isochronic.
  ToneMode get toneMode => ToneMode.values[native.hush_params_tone_mode(_live)];
  set toneMode(ToneMode mode) =>
      native.hush_params_set_tone_mode(_live, mode.index);

  /// Pulse rate in Hz for binaural and isochronic modes, 0.5 to 40.
  double get beatHz => native.hush_params_beat_hz(_live);
  set beatHz(double hz) => native.hush_params_set_beat_hz(_live, hz);

  // ---- noise and nature

  /// Whether the noise layer plays.
  bool get noiseEnabled => native.hush_params_noise_enabled(_live);
  set noiseEnabled(bool on) => native.hush_params_set_noise_enabled(_live, on);

  /// Colour of the noise layer, brown through grey.
  NoiseColor get noiseColor =>
      NoiseColor.values[native.hush_params_noise_color(_live)];
  set noiseColor(NoiseColor color) =>
      native.hush_params_set_noise_color(_live, color.index);

  /// Noise volume, 0 to 1.
  double get noiseLevel => native.hush_params_noise_level(_live);
  set noiseLevel(double level) =>
      native.hush_params_set_noise_level(_live, level);

  /// Volume of one nature sound, 0 to 1; 0 turns it off.
  double ambientLevel(Ambient kind) =>
      native.hush_params_ambient_level(_live, kind.index);

  /// Sets the volume of one nature sound, 0 to 1; 0 turns it off.
  void setAmbient(Ambient kind, double level) =>
      native.hush_params_set_ambient(_live, kind.index, level);

  /// A slow breathing swell in the volume, six breaths a minute.
  bool get swell => native.hush_params_swell(_live);
  set swell(bool on) => native.hush_params_set_swell(_live, on);

  /// Noise and nature sounds sweep slowly from side to side; the tone stays centred.
  bool get spatial => native.hush_params_spatial(_live);
  set spatial(bool on) => native.hush_params_set_spatial(_live, on);

  // ---- lifecycle

  /// Stops the output and frees the engine. The engine cannot be used afterwards. Safe to call
  /// more than once.
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
  /// Creates a renderer for [engine] at [sampleRate] Hz, which must be positive.
  HushRenderer(HushEngine engine, {this.sampleRate = 48000})
    : _offline = _open(engine, sampleRate) {
    _offlineFinalizer.attach(this, _offline.cast(), detach: this);
  }

  static Pointer<native.Offline> _open(HushEngine engine, int sampleRate) {
    if (sampleRate <= 0) {
      throw ArgumentError.value(sampleRate, 'sampleRate', 'must be positive');
    }
    return native.hush_offline_new(engine._live, sampleRate.toDouble());
  }

  /// The rate the audio is rendered at, in Hz.
  final int sampleRate;
  final Pointer<native.Offline> _offline;
  bool _disposed = false;

  /// Renders the next [frames] frames as interleaved stereo: left, right, left, right.
  Float32List render(int frames) {
    if (_disposed) throw StateError('HushRenderer was disposed');
    if (frames <= 0) return Float32List(0);
    // The engine writes every sample, so the buffer need not be zeroed first.
    final buffer = malloc<Float>(frames * 2);
    try {
      native.hush_offline_render(_offline, buffer, frames);
      return Float32List.fromList(buffer.asTypedList(frames * 2));
    } finally {
      malloc.free(buffer);
    }
  }

  /// Frees the renderer. It cannot be used afterwards. Safe to call more than once.
  void dispose() {
    if (_disposed) return;
    _offlineFinalizer.detach(this);
    native.hush_offline_free(_offline);
    _disposed = true;
  }
}
