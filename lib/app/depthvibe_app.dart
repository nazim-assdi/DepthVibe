import 'package:material_ui/material_ui.dart';

import '../features/editor/presentation/editor_screen.dart';
import '../features/fonts/data/font_manager_service.dart';

class DepthVibeApp extends StatelessWidget {
  const DepthVibeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: FontManagerService.instance,
      builder: (context, _) => _buildApplication(context),
    );
  }

  Widget _buildApplication(BuildContext context) {
    const background = Color(0xFF0A0D13);
    const surface = Color(0xFF121824);
    const accent = Color(0xFF7C8CFF);

    return MaterialApp(
      title: 'DepthVibe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: FontManagerService.instance.activeFamily,
        fontFamilyFallback: FontManagerService.instance.fallbackFamilies,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          surface: surface,
        ),
        cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFF263044)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0D131E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2B3548)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2B3548)),
          ),
        ),
      ),
      home: const EditorScreen(),
    );
  }
}
