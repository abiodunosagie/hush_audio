import 'package:hush_audio/hush_audio.dart';

/// Where playback is. `stopping` covers the short fade before the output closes.
enum Playback { stopped, playing, stopping }

/// Everything the screen shows, as one immutable value.
class SoundState {
  const SoundState({
    required this.toneFrequency,
    required this.toneMode,
    required this.beatHz,
    required this.noiseEnabled,
    required this.noiseColor,
    required this.noiseLevel,
    required this.rain,
    this.playback = Playback.stopped,
    this.level = 0,
    this.error,
  });

  /// The engine's current settings, so the screen starts from what the engine really holds.
  factory SoundState.of(HushEngine engine) => SoundState(
    toneFrequency: engine.toneFrequency,
    toneMode: engine.toneMode,
    beatHz: engine.beatHz,
    noiseEnabled: engine.noiseEnabled,
    noiseColor: engine.noiseColor,
    noiseLevel: engine.noiseLevel,
    rain: engine.ambientLevel(Ambient.rain),
  );

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

  /// Set when the audio output could not be opened or stopped working.
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

  // Equality lets the Cubit skip identical states, so a steady level does not rebuild the screen.
  @override
  bool operator ==(Object other) =>
      other is SoundState &&
      other.playback == playback &&
      other.toneFrequency == toneFrequency &&
      other.toneMode == toneMode &&
      other.beatHz == beatHz &&
      other.noiseEnabled == noiseEnabled &&
      other.noiseColor == noiseColor &&
      other.noiseLevel == noiseLevel &&
      other.rain == rain &&
      other.level == level &&
      other.error == error;

  @override
  int get hashCode => Object.hash(
    playback,
    toneFrequency,
    toneMode,
    beatHz,
    noiseEnabled,
    noiseColor,
    noiseLevel,
    rain,
    level,
    error,
  );
}
