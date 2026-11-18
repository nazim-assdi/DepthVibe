# DepthVibe Flutter migration

## Product direction

DepthVibe is moving to one Flutter application codebase for Android, iOS, Windows, macOS and Linux. The original Android implementation is retained under `legacy/android-native/` and remains available for reference while Flutter parity is developed. The Flutter app is the primary project from version 0.4.0.

## Current Flutter foundation

- Responsive dark studio UI with a central preview and inspector.
- Video file import using the native platform file chooser.
- Camera video recording through Flutter camera plugins on Android, iOS and desktop.
- Cross-platform playback through MediaKit.
- Trim in/out controls, split-marker metadata, speed control (0.25x–2x), quarter-turn rotation and original-audio mute.
- 16:9, 9:16, 1:1 and 4:5 output presets, fit and fill/crop.
- Title and caption preview plus generated transparent title overlay for export.
- MP4 export through FFmpegKit Extended, progress callbacks and share action.
- JSON-serializable editor project settings and controller tests.

## Export implementation notes

The first shared FFmpeg render path trims the selected source, adjusts video and audio tempo, rotates, scales/pads or crops, overlays title/caption pixels and writes an MP4 into the app's Documents/DepthVibe/Exports folder. It currently uses the built-in MPEG-4 video encoder to avoid enabling GPL-only libx264. Codec availability and playback quality still need verification on every target.

Split markers are currently persisted as edit markers; they do not yet create independent clip segments. Additional imported clips, music mixing, image overlays, transitions, multi-track compositing, color grading, masks and export-linked 3D effects remain planned.

## Build setup

The generated Flutter platform runners are created with:

```bash
bash tool/bootstrap_platforms.sh
```

The script creates Android, iOS, Windows, Linux and macOS runners, sets Android minSdk to 26, applies camera/microphone usage descriptions and configures Apple platform deployment targets. Then run:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build windows --release
flutter build linux --release
flutter build macos --release
flutter build ios --release --no-codesign
```

iOS App Store distribution requires Apple signing/provisioning configured separately. The CI iOS build is unsigned and is not an installable IPA.

## Runtime requirements

- Flutter 3.50 / Dart 3.14.
- Android API 26 or newer.
- iOS 13 or newer.
- macOS 13 or newer for the selected FFmpeg runtime bundle.
- Linux x86_64 with glibc 2.28 or newer for the selected FFmpeg runtime.
- Windows x86_64 / ARM64 depending on the chosen native bundle architecture.
- Linux desktop camera recording also requires GStreamer runtime plugins.

## Performance and licensing

The FFmpeg video bundle has a material binary-size cost. Keep GPL libraries disabled by default and review the effective FFmpeg/library licences before distributing signed store builds. Do not enable x264/x265 or other GPL-only codecs without a deliberate licensing decision.

The previous native Kotlin/Compose project is reference material, not a live Flutter rendering backend. AI depth, ARCore, Filament, OpenCV SLAM, OBJ/GLB rendering, particle simulation, node-graph execution and true 3D export must be ported or integrated behind cross-platform Dart/native-engine interfaces in later stages. Do not treat their prior Android previews as completed cross-platform capabilities.
