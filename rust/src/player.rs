//! Device playback. The audio callback only calls `Synth::render_interleaved`, which never
//! allocates, locks or blocks, so the callback is safe on a real-time audio thread.

use hush_core::{Params, Synth};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering::Relaxed};

#[cfg(not(target_os = "android"))]
pub use self::cpal_player::Player;

#[cfg(target_os = "android")]
pub use self::aaudio_player::Player;

/// Flags shared between a player and its audio callback.
struct Flags {
    /// Cleared when the device reports an error and stops pulling audio.
    healthy: AtomicBool,
    /// Set when the player is released on a thread that may not drop the stream; the callback
    /// then writes silence.
    silenced: AtomicBool,
}

impl Flags {
    fn new() -> Arc<Self> {
        Arc::new(Self {
            healthy: AtomicBool::new(true),
            silenced: AtomicBool::new(false),
        })
    }
}

/// Fills `out` from the synth, or with silence once the player was released elsewhere.
fn render(synth: &mut Synth, flags: &Flags, out: &mut [f32], channels: usize) {
    if flags.silenced.load(Relaxed) {
        out.fill(0.0);
    } else {
        synth.render_interleaved(out, channels);
    }
}

/// macOS and iOS through cpal over Core Audio (and any other cpal host when built for the
/// desktop, which the CI uses to test the crate), in whatever sample format the device prefers.
#[cfg(not(target_os = "android"))]
mod cpal_player {
    use super::*;
    use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
    use cpal::{FromSample, SampleFormat, SizedSample, StreamConfig};
    use std::thread::{self, ThreadId};

    /// Frames rendered per chunk; the scratch buffer is sized for this many.
    const MAX_BLOCK_FRAMES: usize = 4096;

    pub struct Player {
        stream: cpal::Stream,
        sample_rate: u32,
        flags: Arc<Flags>,
        /// Core Audio streams are not `Send`: only this thread may drop it.
        owner: ThreadId,
    }

    impl Player {
        pub fn open(params: Arc<Params>) -> Result<Self, String> {
            let device = cpal::default_host()
                .default_output_device()
                .ok_or("no audio output device")?;
            let supported = device
                .default_output_config()
                .map_err(|e| format!("could not read the output format: {e}"))?;
            let format = supported.sample_format();
            let config: StreamConfig = supported.into();
            let flags = Flags::new();
            let stream = match format {
                SampleFormat::F32 => build::<f32>(&device, &config, params, &flags),
                SampleFormat::F64 => build::<f64>(&device, &config, params, &flags),
                SampleFormat::I8 => build::<i8>(&device, &config, params, &flags),
                SampleFormat::I16 => build::<i16>(&device, &config, params, &flags),
                SampleFormat::I32 => build::<i32>(&device, &config, params, &flags),
                SampleFormat::U8 => build::<u8>(&device, &config, params, &flags),
                SampleFormat::U16 => build::<u16>(&device, &config, params, &flags),
                SampleFormat::U32 => build::<u32>(&device, &config, params, &flags),
                other => Err(format!("unsupported output sample format {other}")),
            }?;
            stream
                .play()
                .map_err(|e| format!("could not start the output: {e}"))?;
            Ok(Self {
                stream,
                sample_rate: config.sample_rate,
                flags,
                owner: thread::current().id(),
            })
        }

        pub fn sample_rate(&self) -> u32 {
            self.sample_rate
        }

        pub fn is_healthy(&self) -> bool {
            self.flags.healthy.load(Relaxed)
        }

        /// Drops the stream on its own thread; anywhere else, silences it and leaks it, since
        /// dropping a Core Audio stream off its thread is not allowed.
        pub fn release(self) {
            if thread::current().id() == self.owner {
                drop(self.stream);
            } else {
                self.flags.silenced.store(true, Relaxed);
                let _ = self.stream.pause();
                std::mem::forget(self.stream);
            }
        }
    }

    fn build<T>(
        device: &cpal::Device,
        config: &StreamConfig,
        params: Arc<Params>,
        flags: &Arc<Flags>,
    ) -> Result<cpal::Stream, String>
    where
        T: SizedSample + FromSample<f32>,
    {
        let channels = usize::from(config.channels);
        let mut synth = Synth::new(config.sample_rate as f32, params);
        // Sized once for the largest block Core Audio is likely to ask for, so the callback does
        // not allocate; a larger request is rendered in chunks. A whole number of frames, so
        // every chunk keeps the channels interleaved correctly.
        let mut scratch = vec![0.0f32; MAX_BLOCK_FRAMES * channels.max(1)];
        let (data_flags, error_flags) = (flags.clone(), flags.clone());
        device
            .build_output_stream(
                *config,
                move |data: &mut [T], _| {
                    for chunk in data.chunks_mut(scratch.len()) {
                        let buf = &mut scratch[..chunk.len()];
                        render(&mut synth, &data_flags, buf, channels);
                        for (out, s) in chunk.iter_mut().zip(buf.iter()) {
                            *out = T::from_sample(*s);
                        }
                    }
                },
                move |_err| error_flags.healthy.store(false, Relaxed),
                None,
            )
            .map_err(|e| format!("could not open the output stream: {e}"))
    }
}

/// Android: AAudio through the `ndk` crate (API 26+), stereo float at 48 kHz.
#[cfg(target_os = "android")]
mod aaudio_player {
    use super::*;
    use ndk::audio::{
        AudioCallbackResult, AudioDirection, AudioFormat, AudioPerformanceMode, AudioStream,
        AudioStreamBuilder,
    };

    const SAMPLE_RATE: i32 = 48_000;
    const CHANNELS: i32 = 2;

    pub struct Player {
        stream: AudioStream,
        flags: Arc<Flags>,
    }

    impl Player {
        pub fn open(params: Arc<Params>) -> Result<Self, String> {
            let mut synth = Synth::new(SAMPLE_RATE as f32, params);
            let flags = Flags::new();
            let (data_flags, error_flags) = (flags.clone(), flags.clone());
            let stream = AudioStreamBuilder::new()
                .map_err(|e| format!("AAudio is unavailable: {e}"))?
                .direction(AudioDirection::Output)
                .format(AudioFormat::PCM_Float)
                .channel_count(CHANNELS)
                .sample_rate(SAMPLE_RATE)
                .performance_mode(AudioPerformanceMode::LowLatency)
                .data_callback(Box::new(move |_stream, data, frames| {
                    if let Ok(frames) = usize::try_from(frames) {
                        // SAFETY: AAudio hands a buffer of `frames` frames in the format, channel
                        // count and rate checked below (stereo f32), valid for this call only.
                        let out = unsafe {
                            std::slice::from_raw_parts_mut(
                                data.cast::<f32>(),
                                frames * CHANNELS as usize,
                            )
                        };
                        render(&mut synth, &data_flags, out, CHANNELS as usize);
                    }
                    AudioCallbackResult::Continue
                }))
                .error_callback(Box::new(move |_stream, _error| {
                    error_flags.healthy.store(false, Relaxed);
                }))
                .open_stream()
                .map_err(|e| format!("could not open the AAudio stream: {e}"))?;
            // The callback writes stereo f32 for a 48 kHz synth; refuse a stream in another shape
            // rather than play at the wrong pitch.
            if stream.format() != AudioFormat::PCM_Float
                || stream.channel_count() != CHANNELS
                || stream.sample_rate() != SAMPLE_RATE
            {
                return Err("AAudio did not open a 48 kHz stereo float stream".into());
            }
            stream
                .request_start()
                .map_err(|e| format!("could not start the AAudio stream: {e}"))?;
            Ok(Self { stream, flags })
        }

        pub fn sample_rate(&self) -> u32 {
            u32::try_from(self.stream.sample_rate()).unwrap_or(0)
        }

        pub fn is_healthy(&self) -> bool {
            self.flags.healthy.load(Relaxed)
        }

        /// AAudio streams may be closed from any thread.
        pub fn release(self) {
            drop(self);
        }
    }

    impl Drop for Player {
        fn drop(&mut self) {
            let _ = self.stream.request_stop();
        }
    }
}
