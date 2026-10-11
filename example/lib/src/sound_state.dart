import 'package:hush_audio/hush_audio.dart';

/// Where playback is. `stopping` covers the short fade before the output closes.
enum Playback { stopped, playing, stopping }

/// Everything the screen shows, as one immutable value.
class SoundState {
  const SoundState({
    this.playback = Playback.stopped,
    this.toneFrequency = 852,
    this.toneMode = ToneMode.steady,
    this.beatHz = 6,
    this.noiseEnabled = false,
    this.noiseColor = NoiseColor.brown,
    this.noiseLevel = 0.4,
    this.rain = 0,
    this.level = 0,
    this.error,
  });

  final Playback playback;
  final double toneFrequency;
  final ToneMode toneMode;
  final double beatHz;
  final bool noiseEnabled;
  final NoiseColor noiseColor;
  final double noiseLevel;
  final double rain;

  /// The engine's master gain, 0 to 1, for the level ring.
  final double level;

  /// Set when the audio output could not be opened.
  final String? error;

  bool get isPlaying => playback == Playback.playing;

  SoundState copyWith({
    Playback? playback,
    double? toneFrequency,
    ToneMode? toneMode,
    double? beatHz,
    bool? noiseEnabled,
    NoiseColor? noiseColor,
    double? noiseLevel,
    double? rain,
    double? level,
    String? Function()? error,
  }) {
    return SoundState(
      playback: playback ?? this.playback,
      toneFrequency: toneFrequency ?? this.toneFrequency,
      toneMode: toneMode ?? this.toneMode,
      beatHz: beatHz ?? this.beatHz,
      noiseEnabled: noiseEnabled ?? this.noiseEnabled,
      noiseColor: noiseColor ?? this.noiseColor,
      noiseLevel: noiseLevel ?? this.noiseLevel,
      rain: rain ?? this.rain,
      level: level ?? this.level,
      error: error != null ? error() : this.error,
    );
  }
}
