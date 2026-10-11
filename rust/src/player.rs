//! Device playback. The audio callback only calls `Synth::render_interleaved`, which never
//! allocates, locks or blocks, so the callback is safe on a real-time audio thread.

use hush_core::{Params, Synth};
use std::sync::Arc;

#[cfg(not(target_os = "android"))]
pub use self::coreaudio::Player;

#[cfg(target_os = "android")]
pub use self::aaudio::Player;

/// macOS and iOS: cpal over Core Audio, in whatever sample format the device prefers.
#[cfg(not(target_os = "android"))]
mod coreaudio {
    use super::*;
    use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
    use cpal::{FromSample, SampleFormat, SizedSample, StreamConfig};

    pub struct Player {
        _stream: cpal::Stream,
        sample_rate: u32,
    }

    impl Player {
        pub fn open(params: Arc<Params>) -> Result<Self, String> {
            let device = cpal::default_host()
                .default_output_device()
                .ok_or("no output device")?;
            let supported = device.default_output_config().map_err(|e| e.to_string())?;
            let format = supported.sample_format();
            let config: StreamConfig = supported.into();
            let sample_rate = config.sample_rate;
            let stream = match format {
                SampleFormat::F32 => build::<f32>(&device, &config, params),
                SampleFormat::I16 => build::<i16>(&device, &config, params),
                SampleFormat::I32 => build::<i32>(&device, &config, params),
                SampleFormat::U16 => build::<u16>(&device, &config, params),
                other => Err(format!("unsupported sample format {other}")),
            }?;
            stream.play().map_err(|e| e.to_string())?;
            Ok(Self {
                _stream: stream,
                sample_rate,
            })
        }

        pub fn sample_rate(&self) -> u32 {
            self.sample_rate
        }
    }

    fn build<T>(
        device: &cpal::Device,
        config: &StreamConfig,
        params: Arc<Params>,
    ) -> Result<cpal::Stream, String>
    where
        T: SizedSample + FromSample<f32>,
    {
        let channels = usize::from(config.channels);
        let mut synth = Synth::new(config.sample_rate as f32, params);
        // Sized once for the largest block Core Audio is likely to ask for, so the callback does
        // not allocate; a larger request is rendered in chunks.
        let mut scratch = vec![0.0f32; 4096 * channels.max(1)];
        device
            .build_output_stream(
                *config,
                move |data: &mut [T], _| {
                    for chunk in data.chunks_mut(scratch.len()) {
                        let buf = &mut scratch[..chunk.len()];
                        synth.render_interleaved(buf, channels);
                        for (out, s) in chunk.iter_mut().zip(buf.iter()) {
                            *out = T::from_sample(*s);
                        }
                    }
                },
                |_err| {},
                None,
            )
            .map_err(|e| e.to_string())
    }
}

/// Android: AAudio through the `ndk` crate (API 26+), stereo float at 48 kHz.
#[cfg(target_os = "android")]
mod aaudio {
    use super::*;
    use ndk::audio::{
        AudioCallbackResult, AudioDirection, AudioFormat, AudioPerformanceMode, AudioStream,
        AudioStreamBuilder,
    };

    const SAMPLE_RATE: i32 = 48_000;
    const CHANNELS: i32 = 2;

    pub struct Player {
        stream: AudioStream,
    }

    impl Player {
        pub fn open(params: Arc<Params>) -> Result<Self, String> {
            let mut synth = Synth::new(SAMPLE_RATE as f32, params);
            let stream = AudioStreamBuilder::new()
                .map_err(|e| e.to_string())?
                .direction(AudioDirection::Output)
                .format(AudioFormat::PCM_Float)
                .channel_count(CHANNELS)
                .sample_rate(SAMPLE_RATE)
                .performance_mode(AudioPerformanceMode::LowLatency)
                .data_callback(Box::new(move |_stream, data, frames| {
                    if let Ok(frames) = usize::try_from(frames) {
                        // SAFETY: AAudio hands a buffer of `frames` frames in the format and
                        // channel count requested above (stereo f32), valid for this call only.
                        let out = unsafe {
                            std::slice::from_raw_parts_mut(data.cast::<f32>(), frames * 2)
                        };
                        synth.render_interleaved(out, 2);
                    }
                    AudioCallbackResult::Continue
                }))
                .open_stream()
                .map_err(|e| e.to_string())?;
            // The callback writes stereo f32; refuse a stream that came back in another shape.
            if stream.format() != AudioFormat::PCM_Float || stream.channel_count() != CHANNELS {
                return Err("AAudio did not open a stereo float stream".into());
            }
            stream.request_start().map_err(|e| e.to_string())?;
            Ok(Self { stream })
        }

        pub fn sample_rate(&self) -> u32 {
            u32::try_from(self.stream.sample_rate()).unwrap_or(0)
        }
    }

    impl Drop for Player {
        fn drop(&mut self) {
            let _ = self.stream.request_stop();
        }
    }
}
