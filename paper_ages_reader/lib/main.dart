import 'package:flutter/material.dart';

import 'features/home/presentation/home_shell.dart';
import 'core/storage/app_database.dart';

void main() => runApp(const PaperAgesApp());

/// Application root; reading surfaces keep their own document themes.
class PaperAgesApp extends StatelessWidget {
  const PaperAgesApp({super.key, this.database});
  final AppDatabase? database;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Paper Ages',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: HomeShell(database: database),
  );

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    final surface = dark ? const Color(0xFF242424) : const Color(0xFFF2F2F7);
    final foreground = dark ? Colors.white : const Color(0xFF1C1C1E);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: const Color(0xFFB65B24),
            brightness: brightness,
          ).copyWith(
            surface: background,
            surfaceContainerLow: surface,
            surfaceContainer: surface,
            onSurface: foreground,
            onSurfaceVariant: const Color(0xFF8E8E93),
            secondaryContainer: surface,
            onSecondaryContainer: foreground,
            primary: foreground,
            onPrimary: background,
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 32,
        toolbarHeight: 84,
        titleTextStyle: TextStyle(
          color: foreground,
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: -.8,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: surface,
        foregroundColor: foreground,
        elevation: 0,
        shape: const StadiumBorder(),
      ),
    );
  }
}
