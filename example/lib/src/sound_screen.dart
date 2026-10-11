import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hush_audio/hush_audio.dart';

import 'level_ring.dart';
import 'sound_cubit.dart';
import 'sound_state.dart';

/// Solfeggio tones and 432 Hz, the presets the macOS app offers.
const _presets = [
  174.0,
  285.0,
  396.0,
  417.0,
  432.0,
  528.0,
  639.0,
  741.0,
  852.0,
  963.0,
];

class SoundScreen extends StatelessWidget {
  const SoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<SoundCubit, SoundState>(
          builder: (context, state) {
            final cubit = context.read<SoundCubit>();
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                    children: [
                      _Header(state: state),
                      const SizedBox(height: 28),
                      _ToneSection(state: state, cubit: cubit),
                      const SizedBox(height: 28),
                      _NoiseSection(state: state, cubit: cubit),
                      if (state.error != null) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Could not open the audio output: ${state.error}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _PlayBar(state: state, onPressed: cubit.toggle),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});
  final SoundState state;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.65);
    return Row(
      children: [
        LevelRing(level: state.level, size: 76),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${state.toneFrequency.round()} Hz',
                style: text.displaySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(switch (state.playback) {
                Playback.playing => 'Playing, synthesized live in Rust',
                Playback.stopping => 'Fading out',
                Playback.stopped => 'Ready',
              }, style: text.bodyLarge?.copyWith(color: muted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToneSection extends StatelessWidget {
  const _ToneSection({required this.state, required this.cubit});
  final SoundState state;
  final SoundCubit cubit;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Tone',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final hz in _presets)
              ChoiceChip(
                label: Text('${hz.round()}'),
                selected: state.toneFrequency.round() == hz.round(),
                onSelected: (_) => cubit.setToneFrequency(hz),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ToneMode>(
            segments: const [
              ButtonSegment(value: ToneMode.steady, label: Text('Steady')),
              ButtonSegment(value: ToneMode.binaural, label: Text('Binaural')),
              ButtonSegment(value: ToneMode.isochronic, label: Text('Pulse')),
            ],
            selected: {state.toneMode},
            onSelectionChanged: (s) => cubit.setToneMode(s.first),
            style: SegmentedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        if (state.toneMode != ToneMode.steady) ...[
          const SizedBox(height: 8),
          _LabeledSlider(
            label: 'Beat ${state.beatHz.toStringAsFixed(1)} Hz',
            value: state.beatHz,
            min: 0.5,
            max: 40,
            onChanged: cubit.setBeat,
          ),
          if (state.toneMode == ToneMode.binaural)
            Text(
              'Binaural beats need headphones.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
        ],
      ],
    );
  }
}

class _NoiseSection extends StatelessWidget {
  const _NoiseSection({required this.state, required this.cubit});
  final SoundState state;
  final SoundCubit cubit;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Noise and rain',
      trailing: Switch(
        value: state.noiseEnabled,
        onChanged: cubit.setNoiseEnabled,
      ),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final color in NoiseColor.values)
              ChoiceChip(
                label: Text(_label(color)),
                selected: state.noiseEnabled && state.noiseColor == color,
                onSelected: (_) {
                  cubit.setNoiseColor(color);
                  if (!state.noiseEnabled) cubit.setNoiseEnabled(true);
                },
              ),
          ],
        ),
        _LabeledSlider(
          label: 'Noise level',
          value: state.noiseLevel,
          onChanged: cubit.setNoiseLevel,
        ),
        _LabeledSlider(
          label: 'Rain',
          value: state.rain,
          onChanged: cubit.setRain,
        ),
      ],
    );
  }

  static String _label(NoiseColor c) =>
      c.name[0].toUpperCase() + c.name.substring(1);
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.trailing});
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.18);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          SizedBox(width: 118, child: Text(label)),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayBar extends StatelessWidget {
  const _PlayBar({required this.state, required this.onPressed});
  final SoundState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            state.isPlaying ? 'Stop' : 'Play',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
