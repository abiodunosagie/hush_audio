import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hush_audio/hush_audio.dart';

import 'sound_state.dart';

/// Owns the [HushEngine] and keeps the screen in step with it.
class SoundCubit extends Cubit<SoundState> {
  SoundCubit({HushEngine? engine})
    : _engine = engine ?? HushEngine(),
      super(const SoundState()) {
    _engine
      ..toneFrequency = state.toneFrequency
      ..noiseLevel = state.noiseLevel;
  }

  static const _fadeIn = Duration(seconds: 2);
  static const _fadeOut = Duration(milliseconds: 1500);

  final HushEngine _engine;

  /// Samples the master gain for the level ring while sound is playing or fading.
  Timer? _meter;

  void play() {
    if (state.playback == Playback.playing) return;
    try {
      _engine.start();
    } on HushAudioException catch (e) {
      emit(state.copyWith(error: () => e.message));
      return;
    }
    _engine.play(fadeIn: _fadeIn);
    emit(state.copyWith(playback: Playback.playing, error: () => null));
    _startMeter();
  }

  /// Fades out, then closes the output once the engine reports silence.
  void stop() {
    if (state.playback != Playback.playing) return;
    _engine.fadeOut(_fadeOut);
    emit(state.copyWith(playback: Playback.stopping));
  }

  void toggle() => state.isPlaying ? stop() : play();

  void setToneFrequency(double hz) {
    _engine.toneFrequency = hz;
    emit(state.copyWith(toneFrequency: _engine.toneFrequency));
  }

  void setToneMode(ToneMode mode) {
    _engine.toneMode = mode;
    emit(state.copyWith(toneMode: mode));
  }

  void setBeat(double hz) {
    _engine.beatHz = hz;
    emit(state.copyWith(beatHz: _engine.beatHz));
  }

  void setNoiseEnabled(bool on) {
    _engine.noiseEnabled = on;
    emit(state.copyWith(noiseEnabled: on));
  }

  void setNoiseColor(NoiseColor color) {
    _engine.noiseColor = color;
    emit(state.copyWith(noiseColor: color));
  }

  void setNoiseLevel(double level) {
    _engine.noiseLevel = level;
    emit(state.copyWith(noiseLevel: _engine.noiseLevel));
  }

  void setRain(double level) {
    _engine.setAmbient(Ambient.rain, level);
    emit(state.copyWith(rain: _engine.ambientLevel(Ambient.rain)));
  }

  void _startMeter() {
    _meter?.cancel();
    _meter = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final level = _engine.masterGain;
      if (state.playback == Playback.stopping && level == 0) {
        _engine.stop();
        _meter?.cancel();
        emit(state.copyWith(playback: Playback.stopped, level: 0));
        return;
      }
      emit(state.copyWith(level: level));
    });
  }

  @override
  Future<void> close() {
    _meter?.cancel();
    _engine.dispose();
    return super.close();
  }
}
