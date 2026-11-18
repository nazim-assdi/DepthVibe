# DepthVibe architecture

## Application core

Flutter/Dart is the primary codebase for Android, iOS, Windows, macOS and Linux. Camera, file access, gallery writing, playback and export use service/plugin boundaries. The original Kotlin/Compose Android app is archived under legacy/android-native and remains a reference for prior MiDaS/LiteRT, ARCore, OpenCV, Filament, OBJ and particle experiments.

## Video Studio

- File Picker imports source media.
- MediaKit previews edits.
- Camera/camera_desktop provide capture on supported targets.
- EditorProject stores trim, speed, rotation, mute, ratio and title/caption state.
- FFmpegKit Extended runs native export.
- Android exports also copy to Movies/DepthVibe; iOS saves to a Photos album; desktop keeps an app Documents copy.

## Native FFmpeg bundle

ffmpeg_kit_extended_flutter is configured with a full LGPL native bundle (type=full, gpl=false, small=false). Native FFmpeg libraries are part of the application package, so the composition renderer does not require a hosted rendering backend. The full package has a substantial binary-size cost. GPL-only codecs remain disabled; codec and third-party licence terms must be reviewed before commercial distribution.

## Composition document and layers

CompositionDocument owns composition name, dimensions, frame rate, duration, layer list, transitions, playhead and selection. CompositionLayer stores video/image/PSD/text/shape/audio/Null/Adjustment/Camera/Light/3D/particle/precomposition kinds, source URIs and dimensions, transform properties, blend mode, masks, effects, keyframe tracks, shape style, camera/light settings and audio settings.

CompositionController owns layer lifecycle, visibility/solo/lock, parent cycle checks, masks, blend metadata, effect parameters/keyframes, transform keyframes, audio gain keyframes and audio controls.

## Transform, mask and transition compilation

KeyframeTrack samples Hold, Linear, Ease In, Ease Out and Ease In/Out. FfmpegAnimationCompiler converts position, scale, rotation, opacity and audio gain tracks into FFmpeg expressions evaluated at frame/audio-frame time. The compiler also builds alpha expressions for rectangle, ellipse and polygon masks; combines mask operations; and generates wipe/fade/slide/zoom transition expressions.

The first resolver is not a complete matrix hierarchy: anchor-space rotations, skew, constraints and full 3D camera projection are not implemented. Bezier mask handles are not yet rasterized as true curves.

## Audio graph

Video files are inspected with FFprobe for an audio stream. Explicit Audio layers and embedded video audio are fed into a multi-input audio graph. Each track supports gain in dB, pan, fade-in/out, mute, timeline placement and optional Trigger/Background ducking roles. The background track is attenuated by FFmpeg sidechaincompress when the trigger stream is active. A final limiter is applied to mixed multi-track output.

The current graph does not yet provide a full DAW-style rack, EQ automation, waveform cache/editor, surround buses or audio clip envelope UI. Video source audio is mixed only when FFprobe detects the source stream.

## Blend and visual composition

The compositor combines video/image/PSD raster layers in timeline order. Supported non-normal modes use FFmpeg blend, with a separately extracted layer-alpha matte to preserve transparency. The current FFmpeg path is CPU/native 2D compositing; it is not a Vulkan/Metal/OpenGL render graph and it does not render camera/light layers as real 3D scenes.

## Photoshop ingestion

PsdKit reads PSD/PSB. The importer decodes visible raster layers into cached PNGs while retaining source document, layer index, name, bounds, opacity, visibility and blend metadata. Text and adjustment records are retained as editable metadata where available.

This is not equivalent to Photoshop's complete renderer. Group nesting/clipping, every adjustment filter, smart-object rendering, vector paths, text layout/font substitution and all proprietary blend semantics require further renderer work.

## Effect registry

EffectCatalog defines effect identity, categories, parameter ranges/defaults and an FFmpeg filter family. FfmpegFilterCompiler maps a subset of conventional 2D effects to filter strings. Effect parameters can be keyframed in the data model, but current FFmpeg export samples effect values at the composition playhead rather than evaluating every effect parameter as a per-frame expression.

Glow, Drop Shadow, advanced keying, optical-flow processing, rotoscoping, particles and many 3D operations still need dedicated multi-pass or GPU nodes.

## Current composition renderer

CompositionExportService renders a black composition background with ordered visual layers, animated 2D position/scale/rotation/opacity, supported 2D masks, blend modes, transition mattes and multi-track audio. It reports unsupported or missing layers instead of pretending they were rendered. Text, shape, adjustment and true 3D rendering remain unsupported in this output graph.

This is a functional first NLE/compositor render path, not yet a complete After Effects/Premiere Pro replacement. A capability is only considered complete after automated tests, preview/export parity and target-device validation.

## Performance

- Keep FFmpeg, media probing and PSD extraction off the UI isolate.
- Cache PSD raster layers in app-support storage with lifecycle/size limits.
- Avoid decoding large PSDs repeatedly and guard large image dimensions.
- Use bounded frame/texture caches and release native/GPU resources.
- Detect platform capabilities before enabling AR/3D controls.
- Profile large projects, multitrack audio and full FFmpeg bundle size on target hardware.
