import 'dart:async';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';

import 'app/depthvibe_app.dart';
import 'app/depthvibe_settings.dart';
import 'features/extensions/data/extension_manager_service.dart';
import 'features/extensions/data/adobe_bridge_service.dart';
import 'features/extensions/data/extension_marketplace_service.dart';
import 'features/fonts/data/font_manager_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await FFmpegKitExtended.initialize();
  await FontManagerService.instance.initialize();
  await DepthVibeSettingsService.instance.initialize();
  await ExtensionManagerService.instance.initialize();
  await AdobeBridgeService.instance.start();
  try {
    await ExtensionMarketplaceService.instance.startAutoUpdater();
  } catch (_) {
    // Marketplace is optional; a missing feed or settings file must not block app startup.
  }
  runApp(const DepthVibeApp());
  unawaited(FontManagerService.instance.refreshAvailableFonts());
}
