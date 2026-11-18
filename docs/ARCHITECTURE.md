# DepthVibe application architecture

## Primary application

Starting with 0.4.0, Flutter/Dart is the primary product codebase for Android, iOS, Windows, macOS and Linux. Platform-specific camera, file access and media-runtime code is isolated behind plugin/service boundaries. The original Kotlin Android app is preserved in `legacy/android-native`.

## Shared editor model

`EditorProject` is the serializable edit-decision model. It stores the source path, duration, in/out points, playback speed, rotation, mute state, output aspect, fit/fill mode, title/caption and split-marker positions. `EditorController` validates and publishes changes to the UI.

The next architecture step is a true non-destructive timeline graph: ordered clip instances, separate video/audio/overlay tracks, effect stacks, keyframes, and deterministic project serialization. Split markers currently remain timeline metadata rather than renderable cuts.

## Media pipeline

- **Import:** File Picker returns a platform-local media path.
- **Preview:** MediaKit provides the same Dart playback API on Android, iOS, Windows, macOS and Linux.
- **Capture:** Flutter camera provides capture on Android/iOS; camera_desktop provides Windows/Linux/macOS capture.
- **Export:** FFmpegKit Extended executes an asynchronous FFmpeg filter graph. The current shared render handles one source clip, trim, playback-rate change, 90-degree rotations, fit/pad or fill/crop, audio mute or tempo correction, title/caption overlay burn-in and MP4 output.
- **Output:** MP4 files are saved to the app's Documents/DepthVibe/Exports folder and can be shared through the OS share sheet.

The first export profile uses FFmpeg's built-in MPEG-4 video encoder to avoid turning on GPL-only codecs by default. Per-platform codec availability and decoded quality must still be verified. The selected video bundle is significantly larger than a UI-only Flutter application.

## Rendering principles

1. One project model drives preview and export settings.
2. Preview-only settings must be clearly distinguished from effects baked into output.
3. Keep original source media read-only; exports and proxies go into managed folders.
4. Do not run video decode, AI inference or export work on the Flutter UI isolate.
5. Use bounded frame caches and explicit disposal for native handles and GPU textures.
6. Detect platform/device capabilities and provide fallbacks rather than assuming every renderer exists.

## Cross-platform 3D engine boundary

Future AI depth, AR, camera tracking, GLB/OBJ, lighting, particles and node-graph execution will be behind explicit render-engine interfaces. The old Android MiDaS/LiteRT, ARCore, Filament and OpenCV implementations are reference implementations only; they are not automatically available on the desktop or iOS. Each capability must be ported to a compatible shared engine or implemented through platform-specific backends and proven by a rendered export.

## Known gaps in 0.4.0

- Multi-clip and overlapping multi-track composition.
- Split-to-clip editing, transitions, audio mixing and ducking.
- Image/text/logo layers beyond the title/caption overlay.
- LUTs, masks, color curves, scopes and HDR pipeline.
- Persistent project library, autosave, undo/redo and crash recovery.
- AI depth, AR session, global SLAM, 3D model render-to-video and particle compositing in the Flutter renderer.
- Full node graph execution and keyframe binding to exported objects/camera.

A control, model or preview does not count as complete until the effect is present in the export and validated on the target platforms.
