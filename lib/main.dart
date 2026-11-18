import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';

import 'app/depthvibe_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await FFmpegKitExtended.initialize();
  runApp(const DepthVibeApp());
}
