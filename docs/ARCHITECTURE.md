# DepthVibe architecture

## Application core

Flutter/Dart is the primary codebase for Android, iOS, Windows, macOS and Linux. Camera, file access, gallery writing, playback and export use service/plugin boundaries. The original Kotlin/Compose Android app is archived under legacy/android-native and remains a reference for MiDaS/LiteRT, ARCore, OpenCV, Filament, OBJ and particle features.

## Video Studio

- File Picker imports source media.
- MediaKit previews the edit.
- Camera/camera_desktop provide capture on supported targets.
- EditorProject stores trim, speed, rotation, mute, ratio and title/caption state.
- FFmpegKit Extended runs native export.
- Android exports also copy to Movies/DepthVibe; iOS saves to a Photos album; desktop keeps an app Documents copy.

## Native FFmpeg bundle

ffmpeg_kit_extended_flutter is configured with a full LGPL native bundle (type=full, gpl=false, small=false). Native FFmpeg libraries are part of the application package, so this composition renderer does not require a separate hosted rendering backend. The full package has a substantial binary-size cost. GPL-only codecs remain disabled; codec and third-party licence terms must be reviewed before commercial distribution.

## Composition document and layers

CompositionDocument owns composition name, width, height, frame rate, duration, layer list, transitions, playhead and selection. CompositionLayer stores:

- Video, image, Photoshop raster, text, shape, audio, Null, Adjustment, Camera, Light, 3D Model, Particle and Precomposition layer kinds.
- Media source URI, Photoshop source document URI, original layer index and source dimensions.
- Position, anchor, scale, rotation and opacity.
- Blend-mode metadata, masks, effects, keyframe tracks, shape style, camera settings and light settings.

CompositionController provides add/select/remove/reorder, visibility/lock, blend-mode state, masks, effect parameters, effect keyframes, transform keyframes, parenting and transition records. Parent links are checked for cycles.

## Transform and keyframe evaluation

KeyframeTrack samples HOLD, LINEAR, EASE_IN, EASE_OUT and EASE_IN_OUT interpolation. Transform and effect parameters can use keyframes. ParentTransformResolver evaluates a Null/parent hierarchy for the preview and initial compositor export. Its first transform resolver is simplified: parent positions, scales, rotations and opacities are combined, but it is not yet a complete matrix hierarchy with anchor-space rotation, skew, constraints and full 3D camera projection.

## Photoshop ingestion

PsdKit reads PSD/PSB. The importer decodes each visible raster layer into an app-support cached PNG while retaining source document, source index, layer name, bounds, opacity, visibility and blend metadata. Text and adjustment records are retained as editable metadata where available. Each extracted raster becomes its own CompositionLayer and can be transformed/keyframed.

This is not equivalent to Photoshop's complete renderer. Full group nesting/clipping, every adjustment filter, smart-object rendering, vector path semantics, live font substitution and every Photoshop blend mode require additional interpretation and renderer work.

## Effect registry and compiler

EffectCatalog defines effect identity, categories, parameter ranges/defaults and an FFmpeg filter family. FfmpegFilterCompiler maps a subset of conventional 2D effects to filter strings. Effect parameters can be keyframed in the data model; the current FFmpeg composition exporter samples effect parameters at the composition playhead, not as animated per-frame expressions.

Glow, Drop Shadow, advanced masks, rotoscoping, optical-flow effects and many 3D operations need multi-pass GPU/render nodes and are not yet export-complete.

## Current composition renderer

CompositionExportService renders a black composition background with ordered video, image and extracted PSD raster layers, static scale/rotation/position/opacity transforms, and the supported FFmpeg effect subset. It reports unsupported or missing layers instead of pretending they were rendered.

The first compositor export is silent. Audio tracks and source-video audio mixing, non-normal blend modes, masks, transition compositing, animated transform export, shape/text rasterisation and true 3D rendering are not yet wired to this output graph. The standalone CompositionWorkspace is therefore a composition foundation, not yet a complete After Effects replacement.

## Performance

- Keep FFmpeg, video decode and PSD extraction off the UI isolate.
- Cache PSD raster layers in app-support storage with lifecycle/size limits.
- Avoid decoding large PSDs repeatedly and guard large image dimensions.
- Use bounded frame/texture caches and release native/GPU resources.
- Detect platform capabilities before enabling AR/3D controls.
- Profile large PSD/PSB projects and full FFmpeg bundle size on target hardware.
