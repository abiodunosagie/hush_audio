//! C ABI over [hush-core](https://github.com/abiodunosagie/hush-core) for the `hush_audio` Flutter
//! package. Dart calls these functions through `dart:ffi`.
//!
//! Three handles:
//! - **Params** (`hush_params_*`): the engine's controls, a set of atomics. Any thread may set them
//!   while audio plays. Shared by reference count, so a player or offline renderer keeps them
//!   alive even after Dart frees its own handle.
//! - **Player** (`hush_player_*`): plays through the device's default output.
//! - **Offline** (`hush_offline_*`): renders into a caller buffer with no device, for tests and
//!   for exporting audio.
//!
//! Every function accepts a null handle and does nothing (or returns a neutral value), so a Dart
//! bug produces silence, not a crash. Out-of-range values are clamped by hush-core and NaN is
//! ignored, so a bad slider value cannot break the audio.

mod player;

use hush_core::{AmbientKind, NoiseColor, Params, Synth, ToneMode};
use std::sync::Arc;

pub use player::Player;

// ---- params

/// Creates a set of controls with hush-core's defaults: an 852 Hz steady tone, silent until
/// `hush_params_play`. Free with `hush_params_free`.
#[unsafe(no_mangle)]
pub extern "C" fn hush_params_new() -> *const Params {
    Arc::into_raw(Arc::new(Params::default()))
}

/// Releases Dart's reference. Players and renderers built from these params keep their own.
///
/// # Safety
/// `params` must come from `hush_params_new` and not be used after this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hush_params_free(params: *const Params) {
    if !params.is_null() {
        // SAFETY: the caller hands back the reference `hush_params_new` gave out.
        drop(unsafe { Arc::from_raw(params) });
    }
}

/// Borrows the params behind a handle for the duration of one call.
///
/// # Safety
/// `params` is null or a live handle from `hush_params_new`.
unsafe fn with_params(params: *const Params, f: impl FnOnce(&Params)) {
    // SAFETY: guaranteed by the caller; the borrow does not outlive this call.
    if let Some(p) = unsafe { params.as_ref() } {
        f(p);
    }
}

/// A new owned reference to the params, for a player or renderer to keep.
///
/// # Safety
/// `params` is null or a live handle from `hush_params_new`.
unsafe fn clone_params(params: *const Params) -> Option<Arc<Params>> {
    if params.is_null() {
        return None;
    }
    // SAFETY: the handle is a live `Arc` pointer; adding a count then rebuilding gives an owned clone.
    unsafe {
        Arc::increment_strong_count(params);
        Some(Arc::from_raw(params))
    }
}

macro_rules! setter {
    ($(#[$doc:meta])* $name:ident, $ty:ty, |$p:ident, $v:ident| $body:expr) => {
        $(#[$doc])*
        ///
        /// # Safety
        /// `params` is null or a live handle from `hush_params_new`.
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $name(params: *const Params, $v: $ty) {
            // SAFETY: forwarded to the caller.
            unsafe { with_params(params, |$p| $body) }
        }
    };
}

setter!(
    /// Tone layer on or off.
    hush_params_set_tone_enabled, bool, |p, on| p.set_tone_enabled(on)
);
setter!(
    /// Tone frequency in Hz (20 to 2000).
    hush_params_set_tone_frequency, f32, |p, hz| p.set_tone_frequency(hz)
);
setter!(
    /// Tone volume, 0 to 1.
    hush_params_set_tone_level, f32, |p, level| p.set_tone_level(level)
);
setter!(
    /// 0 steady, 1 binaural, 2 isochronic. Other values are ignored.
    hush_params_set_tone_mode, u8, |p, mode| {
        if let Ok(m) = ToneMode::try_from(mode) {
            p.set_tone_mode(m)
        }
    }
);
setter!(
    /// Pulse rate in Hz for binaural and isochronic modes (0.5 to 40).
    hush_params_set_beat_hz, f32, |p, hz| p.set_beat_hz(hz)
);
setter!(
    /// Noise layer on or off.
    hush_params_set_noise_enabled, bool, |p, on| p.set_noise_enabled(on)
);
setter!(
    /// Noise colour by index: 0 brown, 1 pink, 2 white, 3 green, 4 blue, 5 violet, 6 grey.
    /// Other values are ignored.
    hush_params_set_noise_color, u8, |p, color| {
        if let Ok(c) = NoiseColor::try_from(color) {
            p.set_noise_color(c)
        }
    }
);
setter!(
    /// Noise volume, 0 to 1.
    hush_params_set_noise_level, f32, |p, level| p.set_noise_level(level)
);
setter!(
    /// Breathing swell on or off.
    hush_params_set_swell, bool, |p, on| p.set_swell(on)
);
setter!(
    /// Side-to-side movement of noise and nature sounds.
    hush_params_set_spatial, bool, |p, on| p.set_spatial(on)
);
setter!(
    /// Starts or resumes playback, fading in over this many seconds.
    hush_params_play, f32, |p, seconds| p.play(seconds)
);
setter!(
    /// Fades to silence over this many seconds.
    hush_params_fade_out, f32, |p, seconds| p.fade_out(seconds)
);

/// Volume of one nature sound by index (0 rain, 1 ocean, 2 wind, 3 fire, 4 stream), 0 to 1.
/// An unknown index is ignored.
///
/// # Safety
/// `params` is null or a live handle from `hush_params_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hush_params_set_ambient(params: *const Params, kind: u8, level: f32) {
    if let Some(&k) = AmbientKind::ALL.get(usize::from(kind)) {
        // SAFETY: forwarded to the caller.
        unsafe { with_params(params, |p| p.set_ambient(k, level)) }
    }
}

/// The master gain the engine last rendered, 0 to 1: rises during a fade-in, reaches exactly 0
/// once a fade-out ends. Returns 0 for a null handle.
///
/// # Safety
/// `params` is null or a live handle from `hush_params_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hush_params_master_gain(params: *const Params) -> f32 {
    let mut gain = 0.0;
    // SAFETY: forwarded to the caller.
    unsafe { with_params(params, |p| gain = p.master_gain()) };
    gain
}

// ---- offline rendering

/// A synth with no audio device, rendering on demand.
pub struct Offline {
    synth: Synth,
}

/// Creates an offline renderer at `sample_rate` Hz (48000 if the value is not a positive number).
/// Returns null for a null `params`. Free with `hush_offline_free`.
///
/// # Safety
/// `params` is null or a live handle from `hush_params_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hush_offline_new(params: *const Params, sample_rate: f32) -> *mut Offline {
    // SAFETY: forwarded to the caller.
    let Some(params) = (unsafe { clone_params(params) }) else {
        return std::ptr::null_mut();
    };
    let rate = if sample_rate.is_finite() && sample_rate > 0.0 {
        sample_rate
    } else {
        48_000.0
    };
    Box::into_raw(Box::new(Offline {
        synth: Synth::new(rate, params),
    }))
}

/// Renders `frames` stereo frames into `out`, interleaved left and right, so `out` must hold
/// `frames * 2` floats.
///
/// # Safety
/// `offline` is null or a live handle from `hush_offline_new`, and `out` is null or points to at
/// least `frames * 2` writable floats that nothing else accesses during the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hush_offline_render(offline: *mut Offline, out: *mut f32, frames: usize) {
    if offline.is_null() || out.is_null() || frames == 0 {
        return;
    }
    let Some(len) = frames.checked_mul(2) else {
        return;
    };
    // SAFETY: guaranteed by the caller as documented above.
    let (offline, out) = unsafe { (&mut *offline, std::slice::from_raw_parts_mut(out, len)) };
    offline.synth.render_interleaved(out, 2);
}

/// # Safety
/// `offline` is null or a handle from `hush_offline_new` that is not used afterwards.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hush_offline_free(offline: *mut Offline) {
    if !offline.is_null() {
        // SAFETY: the caller hands back the box `hush_offline_new` gave out.
        drop(unsafe { Box::from_raw(offline) });
    }
}

// ---- device playback

/// Opens the default output device and starts rendering. Sound is heard once `hush_params_play`
/// raises the master gain. Returns null if no output device could be opened. Free with
/// `hush_player_free`, from the same thread that created it (Core Audio streams are not `Send`).
///
/// # Safety
/// `params` is null or a live handle from `hush_params_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hush_player_new(params: *const Params) -> *mut Player {
    // SAFETY: forwarded to the caller.
    let Some(params) = (unsafe { clone_params(params) }) else {
        return std::ptr::null_mut();
    };
    match Player::open(params) {
        Ok(player) => Box::into_raw(Box::new(player)),
        Err(_) => std::ptr::null_mut(),
    }
}

/// The output sample rate in Hz, or 0 for a null handle.
///
/// # Safety
/// `player` is null or a live handle from `hush_player_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hush_player_sample_rate(player: *const Player) -> u32 {
    // SAFETY: guaranteed by the caller.
    unsafe { player.as_ref() }.map_or(0, Player::sample_rate)
}

/// Stops the stream and releases the device.
///
/// # Safety
/// `player` is null or a handle from `hush_player_new`, freed on the thread that created it and
/// not used afterwards.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hush_player_free(player: *mut Player) {
    if !player.is_null() {
        // SAFETY: the caller hands back the box `hush_player_new` gave out.
        drop(unsafe { Box::from_raw(player) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn render(params: *const Params, frames: usize) -> Vec<f32> {
        let mut out = vec![0.0; frames * 2];
        unsafe {
            let o = hush_offline_new(params, 48_000.0);
            hush_offline_render(o, out.as_mut_ptr(), frames);
            hush_offline_free(o);
        }
        out
    }

    #[test]
    fn null_handles_are_harmless() {
        unsafe {
            hush_params_set_tone_frequency(std::ptr::null(), 440.0);
            hush_params_set_ambient(std::ptr::null(), 0, 1.0);
            assert_eq!(hush_params_master_gain(std::ptr::null()), 0.0);
            assert!(hush_offline_new(std::ptr::null(), 48_000.0).is_null());
            hush_offline_render(std::ptr::null_mut(), std::ptr::null_mut(), 10);
            hush_offline_free(std::ptr::null_mut());
            assert!(hush_player_new(std::ptr::null()).is_null());
            assert_eq!(hush_player_sample_rate(std::ptr::null()), 0);
            hush_player_free(std::ptr::null_mut());
            hush_params_free(std::ptr::null());
        }
    }

    #[test]
    fn silent_until_play_then_audible() {
        let p = hush_params_new();
        assert!(render(p, 4_800).iter().all(|s| *s == 0.0));
        unsafe { hush_params_play(p, 0.01) };
        let out = render(p, 9_600);
        let peak = out.iter().fold(0.0f32, |m, s| m.max(s.abs()));
        assert!(peak > 0.1, "peak {peak}");
        unsafe { hush_params_free(p) };
    }

    #[test]
    fn the_renderer_keeps_params_alive_after_dart_frees_them() {
        let p = hush_params_new();
        unsafe {
            hush_params_play(p, 0.01);
            let o = hush_offline_new(p, 48_000.0);
            hush_params_free(p);
            let mut out = vec![0.0f32; 9_600];
            hush_offline_render(o, out.as_mut_ptr(), 4_800);
            assert!(out.iter().any(|s| *s != 0.0));
            hush_offline_free(o);
        }
    }

    #[test]
    fn unknown_enum_values_are_ignored() {
        let p = hush_params_new();
        unsafe {
            hush_params_set_tone_mode(p, 1);
            hush_params_set_tone_mode(p, 99);
            assert_eq!((*p).tone_mode(), ToneMode::Binaural);
            hush_params_set_noise_color(p, 1);
            hush_params_set_noise_color(p, 200);
            assert_eq!((*p).noise_color(), NoiseColor::Pink);
            hush_params_set_ambient(p, 0, 0.5);
            hush_params_set_ambient(p, 42, 0.9);
            assert_eq!((*p).ambient_level(AmbientKind::Rain), 0.5);
            hush_params_free(p);
        }
    }
}
