# DepthVibe

One creative studio. Five operating systems. One Flutter codebase.

DepthVibe is an AI-first video, motion-design and 3D creative studio from N Tech. The primary application is Flutter for Android, iOS, Windows, macOS and Linux.

## Video Studio

- Video import, device-camera recording and MediaKit preview.
- Trim In / Out, split markers, playback speed 0.25x–2x, 90-degree rotation and mute.
- 16:9, 9:16, 1:1 and 4:5 canvases, Fit and Fill/Crop.
- Title/caption preview and burn-in, MP4 export and share.
- Android Movies/DepthVibe save, iOS Photos save and desktop Documents export.

## Composition / Motion Design

The new Composition workspace introduces an AE-style layer and animation model:

- Video, image, Photoshop raster, text, shape, audio, Null, Adjustment, Camera, Light, 3D Model, Particle and Precomposition layer types.
- Layer visibility/lock, parent links and cycle checking.
- Position, anchor, scale, rotation, opacity, blend-mode metadata, masks, effects and transitions.
- Keyframe interpolation: Hold, Linear, Ease In, Ease Out and Ease In/Out.
- Shape primitives and style controls; camera projection/DOF controls; light type/intensity/cone/shadow settings.
- Effect registry with categories and editable parameters. Effect parameter keyframes use the same keyframe system.
- PSD/PSB import extracts visible raster layers into individual cached PNGs and retains names, bounds, opacity, blend metadata, source index and text metadata where available.
- ParentTransformResolver evaluates simplified Null/parent chains for the preview.

The initial Compositor MP4 renderer uses the bundled FFmpeg engine for video/image/PSD raster layers, basic transform values and the subset of effects with an FFmpeg filter mapping. It is a first render pass, not a full nonlinear compositor: audio mixing, animated transform curves in export, masks, non-normal blend modes, adjustment-layer rendering, transitions, 3D scene rendering and GPU-only effects are not yet included in the final render.

## Effects registry

The initial catalog covers Brightness, Contrast, Saturation, Gamma, Gaussian/Box Blur, Sharpen, Vignette, Film Grain, Pixelate, Invert, Grayscale, Chromatic Aberration, Edge Detect, Mirror/Flip, Curves, Motion Blur, Lens Distortion, Chroma/Luma Key, Stabilize, Posterize and Color Balance.

Glow, Drop Shadow, optical-flow effects, rotoscoping, particle simulation and other advanced operators need multi-pass GPU/render-graph work. An entry in the effect library does not mean it is fully rendered in every platform.

## FFmpeg is bundled

The app configures ffmpeg_kit_extended_flutter with the full LGPL native bundle: type=full, gpl=false, small=false. FFmpeg native libraries are included in the application package; no hosted backend is needed for this local composition render path. The full bundle can substantially increase installer/APK size. GPL-only codecs are intentionally disabled; review all codec and third-party licence obligations before distribution.

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

- lib/features/editor: video studio and first export workflow.
- lib/features/composition: layer model, keyframes, effects, Photoshop importer, parent resolver, FFmpeg compositor and workspace.
- lib/features/media: platform file import, capture and gallery permissions.
- legacy/android-native: preserved Kotlin/Compose Android implementation and prior AI/AR/3D/VFX experiments.
- docs/ARCHITECTURE.md: renderer architecture and known export gaps.
- docs/ROADMAP.md: staged implementation and release quality gates.

## Product goal

DepthVibe aims to become a professional non-linear editor and compositor combining multi-track video/audio, colour finishing, Photoshop-aware animation, 2D/3D compositing, camera tracking, procedural VFX and a node graph. Matching or exceeding established creative suites is an ambition—not a present performance claim. A capability is complete only when it works in preview, is baked into final export and has been verified on supported devices and operating systems.

Product: DepthVibe
Developer: N Tech
Primary stack: Flutter / Dart
