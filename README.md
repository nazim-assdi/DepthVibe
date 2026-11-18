# DepthVibe

**One creative studio. Five operating systems. One Flutter codebase.**

DepthVibe is an AI-first video, motion-design and 3D creative studio from **N Tech**. Starting with 0.4.0, the primary app is Flutter and targets Android, iOS, Windows, macOS and Linux.

## Cross-platform editor foundation

- Import local video files and preview with MediaKit.
- Record video from supported device cameras on mobile and desktop.
- Trim In / Out and add split markers.
- Playback speed from 0.25x to 2x.
- 90-degree rotation and original-audio mute.
- 16:9, 9:16, 1:1 and 4:5 export canvases.
- Fit or Fill/Crop.
- Title and caption preview, with a generated image overlay in export.
- MP4 export with progress reporting.
- Save exports in the app Documents folder at `DepthVibe/Exports`, then share them.

The initial shared exporter processes a single source clip. Split markers are currently edit metadata, not separate renderable clips. Multi-clip timeline compositing, audio mixing, transitions, LUTs, image layers, AI depth and 3D scene rendering are on the roadmap; they are not claimed as complete.

## Platforms

| Platform | Target |
|---|---|
| Android | APK / App Bundle |
| iOS | Unsigned build in CI; signing required for distribution |
| Windows | Desktop application |
| macOS | Desktop application |
| Linux | Desktop application |

## Requirements

- Flutter 3.50 / Dart 3.14
- Android API 26+, iOS 13+, macOS 13+
- Desktop build toolchains for Windows, macOS and Linux
- Linux camera capture requires GStreamer runtime plugins

## Getting started

Install Flutter 3.50, then run:

```bash
bash tool/bootstrap_platforms.sh
flutter analyze
flutter test
flutter run
```

Build an Android APK:

```bash
flutter build apk --release --split-per-abi
```

Build desktop applications:

```bash
flutter build windows --release
flutter build linux --release
flutter build macos --release
```

Build iOS without signing:

```bash
flutter build ios --release --no-codesign
```

## Architecture

- `lib/features/editor`: timeline state, preview, inspector and export pipeline.
- `lib/features/media`: platform file import and camera recording.
- `tool/bootstrap_platforms.sh`: generate the Flutter platform runners.
- `legacy/android-native`: preserved Kotlin/Compose Android implementation from 0.3.0.
- `docs/FLUTTER_MIGRATION.md`: migration scope, requirements and known gaps.

## Media engine

- MediaKit for cross-platform video playback.
- FFmpegKit Extended for shared native FFmpeg processing.
- Flutter camera + camera_desktop for capture.
- File Picker for native file selection.

The selected FFmpeg build keeps GPL-only components disabled. Review all third-party codec licences and the final binary bundle before distributing store builds. Video bundle size can be substantial.

## Product goal

The long-term target is a high-end editor combining a non-linear multi-track timeline, color and audio finishing, AI-assisted media, 3D compositing, camera tracking, procedural effects and an executable node graph. Matching or exceeding established tools is an ambition, not a present performance claim. Quality will be measured by features that work in preview and export, platform tests, stability and real-world projects.

**Product:** DepthVibe  
**Developer:** N Tech  
**Primary stack:** Flutter / Dart
