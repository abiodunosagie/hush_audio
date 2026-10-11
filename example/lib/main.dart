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
  runApp(const HushExampleApp());
}

class HushExampleApp extends StatelessWidget {
  const HushExampleApp({super.key});

  static const _ink = Color(0xFFE9E6DF);
  static const _night = Color(0xFF0E1118);
  static const _accent = Color(0xFFE0A15E);

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
      home: BlocProvider(
        create: (_) => SoundCubit(),
        child: const SoundScreen(),
      ),
    );
  }
}
