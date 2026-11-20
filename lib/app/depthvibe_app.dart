import 'package:material_ui/material_ui.dart';

import '../features/editor/presentation/editor_screen.dart';
import '../features/fonts/data/font_manager_service.dart';
import 'depthvibe_settings.dart';

class DepthVibeApp extends StatelessWidget {
  const DepthVibeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        FontManagerService.instance,
        DepthVibeSettingsService.instance,
      ]),
      builder: (context, _) => _buildApplication(),
    );
  }

  Widget _buildApplication() {
    final settings = DepthVibeSettingsService.instance;
    final fontManager = FontManagerService.instance;

    return MaterialApp(
      title: 'DepthVibe',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: DepthVibeTheme.build(
        appearance: settings.appearance,
        fontFamily: fontManager.activeFamily,
        fontFallback: fontManager.fallbackFamilies,
      ),
      home: const EditorScreen(),
    );
  }
}
