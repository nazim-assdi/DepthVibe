# DepthVibe

One creative studio. Five operating systems. One Flutter codebase.

DepthVibe is an AI-first video, motion-design and 3D creative studio from N Tech. The primary application is Flutter for Android, iOS, Windows, macOS and Linux.

## Video Studio

- Video import, device-camera recording and MediaKit preview.
- Trim In / Out, split markers, playback speed 0.25x–2x, 90-degree rotation and mute.
- 16:9, 9:16, 1:1 and 4:5 canvases, Fit and Fill/Crop.
- Title/caption preview and burn-in, MP4 export and share.
- Android Movies/DepthVibe save, iOS Photos save and desktop Documents export.

## Composition and timeline

DepthVibe is being developed as a combined nonlinear editor (NLE) and layer compositor—not as an After Effects-only imitation.

- Video, image, Photoshop raster, text, shape, audio, Null, Adjustment, Camera, Light, 3D Model, Particle and Precomposition layer models.
- Layer ordering, visibility, solo, lock, parent links and cycle checking.
- NLE timeline clip placement, drag-to-move, edge resize, clip duration and source-in trimming for video/audio layers.
- Position, scale, rotation and opacity transform curves compile into FFmpeg per-frame expressions with Hold, Linear and Ease interpolation.
- Rectangle, ellipse and polygon alpha masks support inversion, opacity, feather, expansion and Add/Subtract/Intersect/Difference operations in the render graph.
- Non-normal layer compositing uses FFmpeg blend modes with the layer alpha preserved.
- Dissolve/fade, wipe, slide, zoom and luma transition models are evaluated in the final 2D compositor.
- Dedicated audio layers and embedded video audio streams are probed and mixed. Gain keyframes, pan, fade-in/out, trigger/background roles and sidechain ducking are available.
- Brightness, contrast, saturation and gamma effect keyframes are evaluated per frame. Glow and Drop Shadow use CPU FFmpeg multi-pass compositing; other effect parameters are still sampled at the playhead unless their filter has a dedicated animated path.
- PSD/PSB import extracts visible raster layers to independent cached PNGs and keeps source metadata where available.

## Renderer boundaries

The current final-render path is a CPU/native FFmpeg 2D compositor, not a complete GPU scene renderer. It renders animated 2D transforms, basic layer mattes, blend compositing, supported transitions and audio tracks. Polygon Bézier handles are not yet a true vector path renderer. Audio effects racks, waveform editing, source clip trimming UI in the composition timeline, and animated effect parameter expressions remain to be built.

Camera and Light are currently parameter models/controls; real mesh-based 3D rendering, camera projection, depth of field, environment lighting and shadow maps are not wired to the final compositor. A basic 2D template tracker can track a manually selected rectangle and write translation keyframes; planar/perspective tracking, scale/rotation solving, occlusion handling and rotoscoping remain open work. Full PSD groups/clipping/smart objects and Photoshop-style adjustment rendering also remain open. Glow and Drop Shadow now have CPU multi-pass export paths, but there is no GPU render graph yet. Optical-flow effects, advanced denoise, displacement, volumetrics and high-end VFX still need a dedicated GPU renderer. An effect-library entry does not mean that effect is complete in final export.

## FFmpeg bundle

The app configures ffmpeg_kit_extended_flutter with the full LGPL native bundle: type=full, gpl=false, small=false. Native FFmpeg libraries are included in the application package; no hosted rendering backend is needed for the local render path. The full bundle can substantially increase installer/APK size. GPL-only codecs are intentionally disabled; review all codec and third-party licence obligations before distribution.

## Platforms

| Platform | Build target |
|---|---|
| Android | APK / App Bundle |
| iOS | Unsigned CI build; Apple signing required for distribution |
| Windows | Desktop application |
| macOS | Desktop application |
| Linux | Desktop application |

## Build

Install Flutter 3.50 and Dart 3.12+, then run:

- bash tool/bootstrap_platforms.sh
- flutter pub get
- dart format lib test
- flutter analyze
- flutter test

Build commands:
- Android: flutter build apk --release --split-per-abi
- Windows: flutter build windows --release
- Linux: flutter build linux --release
- macOS: flutter build macos --release
- iOS unsigned: flutter build ios --release --no-codesign

## Source layout

- lib/features/editor: Video Studio and first export workflow.
- lib/features/composition: layer/timeline model, keyframes, effects, Photoshop importer, transform compiler, FFmpeg compositor and workspace.
- lib/features/media: platform file import, capture and gallery permissions.
- legacy/android-native: preserved Kotlin/Compose Android implementation and prior AI/AR/3D/VFX experiments.
- docs/ARCHITECTURE.md: renderer architecture and known export gaps.
- docs/ROADMAP.md: staged implementation and release quality gates.

## Product goal

DepthVibe aims to become a professional NLE and compositor combining multi-track video/audio, colour finishing, Photoshop-aware animation, 2D/3D compositing, camera tracking, procedural VFX and a node graph. Matching or exceeding established creative suites is an ambition—not a present performance claim. A capability is complete only when it works in preview, is baked into final export and is verified on supported devices and operating systems.

Product: DepthVibe
Developer: N Tech
Primary stack: Flutter / Dart
