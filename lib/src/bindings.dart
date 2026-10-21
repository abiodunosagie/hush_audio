/// Raw bindings to the Rust library. Not part of the public API; use `HushEngine`.
///
/// The library is a native asset built by `hook/build.dart` with this file's asset id, so the
/// `@Native` functions below resolve to it without any `DynamicLibrary.open` call.
// The Dart names match the exported C symbols exactly, so they are not lowerCamelCase.
// ignore_for_file: non_constant_identifier_names
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Opaque Rust handles.
final class Params extends Opaque {}

final class Offline extends Opaque {}

final class Player extends Opaque {}

@Native<Pointer<Params> Function()>(isLeaf: true)
external Pointer<Params> hush_params_new();

@Native<Void Function(Pointer<Params>)>(isLeaf: true)
external void hush_params_free(Pointer<Params> params);

@Native<Void Function(Pointer<Params>, Bool)>(isLeaf: true)
external void hush_params_set_tone_enabled(Pointer<Params> params, bool on);

@Native<Void Function(Pointer<Params>, Float)>(isLeaf: true)
external void hush_params_set_tone_frequency(Pointer<Params> params, double hz);

@Native<Void Function(Pointer<Params>, Float)>(isLeaf: true)
external void hush_params_set_tone_level(Pointer<Params> params, double level);

@Native<Void Function(Pointer<Params>, Uint8)>(isLeaf: true)
external void hush_params_set_tone_mode(Pointer<Params> params, int mode);

@Native<Void Function(Pointer<Params>, Float)>(isLeaf: true)
external void hush_params_set_beat_hz(Pointer<Params> params, double hz);

@Native<Void Function(Pointer<Params>, Bool)>(isLeaf: true)
external void hush_params_set_noise_enabled(Pointer<Params> params, bool on);

@Native<Void Function(Pointer<Params>, Uint8)>(isLeaf: true)
external void hush_params_set_noise_color(Pointer<Params> params, int color);

@Native<Void Function(Pointer<Params>, Float)>(isLeaf: true)
external void hush_params_set_noise_level(Pointer<Params> params, double level);

@Native<Void Function(Pointer<Params>, Uint8, Float)>(isLeaf: true)
external void hush_params_set_ambient(
  Pointer<Params> params,
  int kind,
  double level,
);

@Native<Void Function(Pointer<Params>, Bool)>(isLeaf: true)
external void hush_params_set_swell(Pointer<Params> params, bool on);

@Native<Void Function(Pointer<Params>, Bool)>(isLeaf: true)
external void hush_params_set_spatial(Pointer<Params> params, bool on);

@Native<Void Function(Pointer<Params>, Float)>(isLeaf: true)
external void hush_params_play(Pointer<Params> params, double seconds);

@Native<Void Function(Pointer<Params>, Float)>(isLeaf: true)
external void hush_params_fade_out(Pointer<Params> params, double seconds);

@Native<Float Function(Pointer<Params>)>(isLeaf: true)
external double hush_params_master_gain(Pointer<Params> params);

// Values the engine actually holds, after clamping.
@Native<Bool Function(Pointer<Params>)>(isLeaf: true)
external bool hush_params_tone_enabled(Pointer<Params> params);

@Native<Float Function(Pointer<Params>)>(isLeaf: true)
external double hush_params_tone_frequency(Pointer<Params> params);

@Native<Float Function(Pointer<Params>)>(isLeaf: true)
external double hush_params_tone_level(Pointer<Params> params);

@Native<Uint8 Function(Pointer<Params>)>(isLeaf: true)
external int hush_params_tone_mode(Pointer<Params> params);

@Native<Float Function(Pointer<Params>)>(isLeaf: true)
external double hush_params_beat_hz(Pointer<Params> params);

@Native<Bool Function(Pointer<Params>)>(isLeaf: true)
external bool hush_params_noise_enabled(Pointer<Params> params);

@Native<Uint8 Function(Pointer<Params>)>(isLeaf: true)
external int hush_params_noise_color(Pointer<Params> params);

@Native<Float Function(Pointer<Params>)>(isLeaf: true)
external double hush_params_noise_level(Pointer<Params> params);

@Native<Float Function(Pointer<Params>, Uint8)>(isLeaf: true)
external double hush_params_ambient_level(Pointer<Params> params, int kind);

@Native<Bool Function(Pointer<Params>)>(isLeaf: true)
external bool hush_params_swell(Pointer<Params> params);

@Native<Bool Function(Pointer<Params>)>(isLeaf: true)
external bool hush_params_spatial(Pointer<Params> params);

@Native<Pointer<Offline> Function(Pointer<Params>, Float)>(isLeaf: true)
external Pointer<Offline> hush_offline_new(
  Pointer<Params> params,
  double sampleRate,
);

@Native<Void Function(Pointer<Offline>, Pointer<Float>, Size)>(isLeaf: true)
external void hush_offline_render(
  Pointer<Offline> offline,
  Pointer<Float> out,
  int frames,
);

@Native<Void Function(Pointer<Offline>)>(isLeaf: true)
external void hush_offline_free(Pointer<Offline> offline);

// Opening a device can take tens of milliseconds, so these are not leaf calls.
@Native<Pointer<Player> Function(Pointer<Params>)>()
external Pointer<Player> hush_player_new(Pointer<Params> params);

@Native<Pointer<Utf8> Function()>(isLeaf: true)
external Pointer<Utf8> hush_last_error();

@Native<Uint32 Function(Pointer<Player>)>(isLeaf: true)
external int hush_player_sample_rate(Pointer<Player> player);

@Native<Bool Function(Pointer<Player>)>(isLeaf: true)
external bool hush_player_is_healthy(Pointer<Player> player);

@Native<Void Function(Pointer<Player>)>()
external void hush_player_free(Pointer<Player> player);
