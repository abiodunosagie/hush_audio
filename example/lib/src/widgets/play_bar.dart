import 'package:flutter/material.dart';

import '../sound_state.dart';

/// The full-width play and stop button pinned to the bottom of the screen.
class PlayBar extends StatelessWidget {
  const PlayBar({super.key, required this.state, required this.onPressed});
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
