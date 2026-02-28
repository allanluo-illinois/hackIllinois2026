// Setup: run `flutter pub get` after adding provider: ^6.1.2 to pubspec.yaml
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_shell.dart';
import 'core/app_state.dart';
import 'core/mock_backend.dart';

// CAT brand colours
const _catYellow = Color(0xFFFFCD11);
const _catBlack = Color(0xFF1A1A1A);
const _catCharcoal = Color(0xFF2C2C2C);
const _catPaleYellow = Color(0xFFFFF3C4);

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(MockBackend()),
      child: const CatInspectorApp(),
    ),
  );
}

class CatInspectorApp extends StatelessWidget {
  const CatInspectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ColorScheme.fromSeed(
      seedColor: _catYellow,
      brightness: Brightness.light,
    ).copyWith(
      primary: _catYellow,
      onPrimary: _catBlack,
      primaryContainer: _catPaleYellow,
      onPrimaryContainer: _catBlack,
      secondary: _catBlack,
      onSecondary: Colors.white,
      secondaryContainer: _catCharcoal,
      onSecondaryContainer: Colors.white,
      surface: const Color(0xFFF7F7F7),
      onSurface: _catBlack,
      surfaceContainerHighest: const Color(0xFFE8E8E8),
      outline: const Color(0xFF8A8A8A),
    );

    return MaterialApp(
      title: 'CAT Inspector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: base,
        useMaterial3: true,

        // AppBar: black band, white text, yellow accents
        appBarTheme: const AppBarTheme(
          backgroundColor: _catBlack,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 2,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
          iconTheme: IconThemeData(color: Colors.white),
          actionsIconTheme: IconThemeData(color: Colors.white),
        ),

        // Bottom nav: white bg, yellow indicator, black selected icon
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: _catYellow,
          elevation: 4,
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),

        // Cards: crisp white, subtle shadow
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1.5,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          margin: EdgeInsets.zero,
        ),

        // Filled buttons: yellow + bold black text
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            foregroundColor: _catBlack,
            textStyle: const TextStyle(
                fontWeight: FontWeight.w700, letterSpacing: 0.3),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),

        // Outlined buttons: black border
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _catBlack,
            side: const BorderSide(color: _catBlack, width: 1.5),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),

        // Chips
        chipTheme: ChipThemeData(
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),

        // Inputs: rounded pill-friendly border
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _catYellow, width: 2),
          ),
        ),

        textTheme: const TextTheme(
          titleMedium: TextStyle(fontWeight: FontWeight.w700),
          titleSmall: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      home: const AppShell(),
    );
  }
}
