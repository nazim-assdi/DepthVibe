import 'package:material_ui/material_ui.dart';

import 'app/depthvibe_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Paint the app window immediately. Native media services are initialised
  // by DepthVibeApp after the first frame so startup failures are visible.
  runApp(const DepthVibeApp());
}
