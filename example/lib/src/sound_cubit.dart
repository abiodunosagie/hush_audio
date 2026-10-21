import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hush_audio/hush_audio.dart';

import 'sound_state.dart';

/// Owns the [HushEngine] (unless one is passed in) and keeps the screen in step with it.
class SoundCubit extends Cubit<SoundState> {
  SoundCubit({HushEngine? engine})
    : this._(engine ?? HushEngine(), engine == null);

  SoundCubit._(this._engine, this._ownsEngine) : super(SoundState.of(_engine));

  static const _fadeIn = Duration(seconds: 2);
  static const _fadeOut = Duration(milliseconds: 1500);

  /// If the device stops pulling audio mid-fade, the gain never reaches 0; close anyway by then.
  static const _stopGrace = Duration(milliseconds: 750);

  final HushEngine _engine;
  final bool _ownsEngine;

  /// Samples the master gain for the level ring while sound is playing or fading.
  Timer? _meter;
  DateTime? _stopDeadline;

  void play() {
    if (state.playback == Playback.playing) return;
    try {
      _engine.start();
    } on HushAudioException catch (e) {
      emit(state.copyWith(error: () => e.message));
      return;
    }
    _engine.play(fadeIn: _fadeIn);
    _stopDeadline = null;
    emit(state.copyWith(playback: Playback.playing, error: () => null));
    _startMeter();
  }

  /// Fades out, then closes the output once the engine reports silence.
  void stop() {
    if (state.playback != Playback.playing) return;
    _engine.fadeOut(_fadeOut);
    _stopDeadline = DateTime.now().add(_fadeOut + _stopGrace);
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

  /// Picks a colour and switches the noise layer on, as tapping a colour suggests.
  void selectNoiseColor(NoiseColor color) {
    _engine
      ..noiseColor = color
      ..noiseEnabled = true;
    emit(state.copyWith(noiseColor: color, noiseEnabled: true));
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
    _meter = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
  }

  void _tick() {
    if (_engine.isHealthy == false) {
      _close(error: 'the audio output stopped (was the device disconnected?)');
      return;
    }
    final level = _engine.masterGain;
    final deadline = _stopDeadline;
    final fadeDone =
        level == 0 || (deadline != null && DateTime.now().isAfter(deadline));
    if (state.playback == Playback.stopping && fadeDone) {
      _close();
      return;
    }
    emit(state.copyWith(level: level));
  }

  void _close({String? error}) {
    _meter?.cancel();
    _engine.stop();
    _stopDeadline = null;
    emit(
      state.copyWith(playback: Playback.stopped, level: 0, error: () => error),
    );
  }

  @override
  Future<void> close() {
    _meter?.cancel();
    if (_ownsEngine) {
      _engine.dispose();
    } else {
      // Hand a borrowed engine back silent, so its next start() does not resume at full volume.
      _engine
        ..fadeOut(Duration.zero)
        ..stop();
    }
    return super.close();
  }
}
