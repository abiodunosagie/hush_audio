import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'src/sound_cubit.dart';
import 'src/sound_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Plays as music: not muted by the iPhone ring switch, and ducks other apps politely.
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  final cubit = SoundCubit();
  // A phone call or Siri stops the output without a device error, and pulling out headphones
  // should not move the sound to the speaker: fade out in both cases.
  session.interruptionEventStream.listen((event) {
    if (event.begin) cubit.stop();
  });
  session.becomingNoisyEventStream.listen((_) => cubit.stop());
  runApp(HushExampleApp(cubit: cubit));
}

class HushExampleApp extends StatelessWidget {
  const HushExampleApp({super.key, required this.cubit});

  final SoundCubit cubit;

  // Hush brand colours: Lamp on Night (see the Hush repo's brand/BRAND.md).
  static const _ink = Color(0xFFE9E5DC);
  static const _night = Color(0xFF12141C);
  static const _accent = Color(0xFFF2B66B);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _accent,
      brightness: Brightness.dark,
    ).copyWith(primary: _accent, surface: _night, onSurface: _ink);
    return MaterialApp(
      title: 'Hush',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: _night,
        useMaterial3: true,
      ),
      home: BlocProvider.value(value: cubit, child: const SoundScreen()),
    );
  }
}
