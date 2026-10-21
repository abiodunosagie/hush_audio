import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hush_audio/hush_audio.dart';

import 'level_ring.dart';
import 'sound_cubit.dart';
import 'sound_state.dart';
import 'widgets/labeled_slider.dart';
import 'widgets/play_bar.dart';
import 'widgets/section.dart';

/// Solfeggio frequencies plus 432 Hz.
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
          // The level ring updates every 50 ms while playing; it rebuilds on its own below, so the
          // rest of the screen only rebuilds when something else changes.
          buildWhen: (previous, next) =>
              previous.copyWith(level: next.level) != next,
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
                          state.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                PlayBar(state: state, onPressed: cubit.toggle),
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
        BlocSelector<SoundCubit, SoundState, double>(
          selector: (state) => state.level,
          builder: (context, level) => LevelRing(level: level, size: 76),
        ),
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
    return Section(
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
          LabeledSlider(
            label: 'Beat ${state.beatHz.toStringAsFixed(1)} Hz',
            value: state.beatHz,
            min: HushEngine.minBeatHz,
            max: HushEngine.maxBeatHz,
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
    return Section(
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
                onSelected: (_) => cubit.selectNoiseColor(color),
              ),
          ],
        ),
        LabeledSlider(
          label: 'Noise level',
          value: state.noiseLevel,
          onChanged: cubit.setNoiseLevel,
        ),
        LabeledSlider(
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
