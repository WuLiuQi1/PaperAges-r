import 'package:flutter/material.dart';

import 'features/library/presentation/local_library_screen.dart';

void main() => runApp(const PaperAgesApp());

/// Application root. G1 temporarily hosts an isolated interaction harness.
class PaperAgesApp extends StatelessWidget {
  const PaperAgesApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Paper Ages',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8A6842)),
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFC9A878),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: const LocalLibraryScreen(),
  );
}
