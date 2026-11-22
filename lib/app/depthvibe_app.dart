import 'dart:async';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:material_ui/material_ui.dart';
import '../features/composition/presentation/composition_workspace.dart';
import '../features/extensions/data/adobe_bridge_service.dart';
import '../features/extensions/data/extension_manager_service.dart';
import '../features/extensions/data/extension_marketplace_service.dart';
import '../features/fonts/data/font_manager_service.dart';
import 'depthvibe_brand_mark.dart';
import 'depthvibe_settings.dart';

class DepthVibeApp extends StatefulWidget {
  const DepthVibeApp({super.key});

  @override
  State<DepthVibeApp> createState() => _DepthVibeAppState();
}

class _DepthVibeAppState extends State<DepthVibeApp> {
  bool _initializing = false;
  bool _ready = false;
  bool _ffmpegAvailable = false;
  String _startupStage = 'Preparing your creative workspace…';
  String? _startupError;
  List<String> _startupWarnings = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_initializeServices());
  }

  Future<void> _initializeServices() async {
    if (_initializing) return;

    // Render the real editor before loading optional native services. A slow
    // media codec, font scan or extension registry must never leave the app
    // trapped on a blank/grey startup window.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _initializing) return;

    setState(() {
      _initializing = true;
      _ready = true;
      _startupError = null;
      _startupStage = 'Loading optional services in the background…';
      _startupWarnings = const [];
      _ffmpegAvailable = false;
    });

    final warnings = <String>[];
    Future<void> optionalStep(
      String label,
      Future<void> Function() initialize, {
      void Function()? onSuccess,
    }) async {
      try {
        await initialize().timeout(const Duration(seconds: 25));
        onSuccess?.call();
      } catch (error, stackTrace) {
        warnings.add(label);
        debugPrint(
          'DepthVibe optional startup service "$label" failed or timed out: '
          '$error\\n$stackTrace',
        );
      }
    }

    // The full composition and NLE workspace is already visible. FFmpeg
    // enables preview decoding and final MP4 rendering when it is available.
    await optionalStep('video processing engine', () async {
      await FFmpegKitExtended.initialize();
    }, onSuccess: () {
      if (mounted) setState(() => _ffmpegAvailable = true);
    });

    // These local services are also non-blocking for the basic editor.
    await optionalStep('font manager', FontManagerService.instance.initialize);
    await optionalStep(
      'appearance settings',
      DepthVibeSettingsService.instance.initialize,
    );
    await optionalStep(
      'extension manager',
      ExtensionManagerService.instance.initialize,
    );
    await optionalStep(
      'Adobe connection service',
      AdobeBridgeService.instance.start,
    );
    await optionalStep(
      'extension marketplace updates',
      ExtensionMarketplaceService.instance.startAutoUpdater,
    );

    if (!mounted) return;
    setState(() {
      _initializing = false;
      _startupWarnings = List.unmodifiable(warnings);
      _startupStage = warnings.isEmpty
          ? 'DepthVibe is ready.'
          : 'Editor ready; optional services need attention.';
    });
    unawaited(_refreshFontsSafely());
  }

  Future<void> _refreshFontsSafely() async {
    try {
      await FontManagerService.instance.refreshAvailableFonts();
    } catch (error, stackTrace) {
      debugPrint('DepthVibe font refresh failed: $error\n$stackTrace');
    }
  }

  Widget _buildStartupScreen(BuildContext context) {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    final hasError = _startupError != null;
    return Scaffold(
      backgroundColor: palette.appBackground,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DepthVibeBrandMark(size: 76),
                const SizedBox(height: 28),
                Text(
                  hasError ? 'DEPTHVIBE COULD NOT START' : 'PREPARING YOUR STUDIO',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.primaryText,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _startupStage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.secondaryText, fontSize: 13),
                ),
                const SizedBox(height: 24),
                if (hasError) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: palette.panel,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: palette.border),
                    ),
                    child: SelectableText(
                      _startupError!,
                      style: TextStyle(color: palette.primaryText, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _initializing
                        ? null
                        : () => unawaited(_initializeServices()),
                    icon: const Icon(Icons.refresh),
                    label: const Text('RETRY STARTUP'),
                  ),
                ] else ...[
                  SizedBox(
                    width: 280,
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(8),
                      backgroundColor: palette.border,
                      color: palette.accent,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Initialising local media and studio services',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.secondaryText,
                      fontSize: 10,
                      letterSpacing: 0.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
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
      home: _ready
          ? CompositionWorkspace(
              startupWarning: _startupWarnings.isEmpty
                  ? null
                  : 'Some optional services did not start: ' +
                      _startupWarnings.join(', '),
              mediaProcessingAvailable: _ffmpegAvailable,
            )
          : Builder(builder: _buildStartupScreen),
    );
  }

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
}
