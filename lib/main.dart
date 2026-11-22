import 'package:material_ui/material_ui.dart';

import 'app/depthvibe_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // In release builds Flutter's default ErrorWidget can look like a plain
  // grey surface. Keep a readable diagnostic view visible when a widget fails
  // during its first build instead of presenting an unexplained blank window.
  ErrorWidget.builder = (details) {
    final message = details.exceptionAsString();
    debugPrint('DepthVibe widget build failed: $message');
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF0B0E15),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DEPTHVIBE COULD NOT DRAW THIS SCREEN',
                    style: TextStyle(
                      color: Color(0xFFFFA0A0),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'The editor is still running, but a UI component failed. '
                    'Copy this diagnostic and share it with support.',
                    style: TextStyle(
                      color: Color(0xFFD8DEEA),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    message,
                    style: const TextStyle(
                      color: Color(0xFFFFD4D4),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  };

  // Native media services are started after Flutter has painted the editor.
  runApp(const DepthVibeApp());
}
