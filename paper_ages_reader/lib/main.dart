import 'package:flutter/material.dart';

void main() => runApp(const PaperAgesApp());

/// Application root intentionally kept small during G0.
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
    home: const _BootstrapScreen(),
  );
}

class _BootstrapScreen extends StatelessWidget {
  const _BootstrapScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Paper Ages',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('阅读器基础工程已就绪'),
          ],
        ),
      ),
    ),
  );
}
