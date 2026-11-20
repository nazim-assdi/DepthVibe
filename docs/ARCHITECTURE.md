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

CompositionDocument owns composition name, dimensions, frame rate, duration, layer list, transitions, playhead and selection. CompositionLayer stores video/image/PSD/text/shape/audio/Null/Adjustment/Camera/Light/3D/particle/precomposition kinds, source URIs and dimensions, transform properties, blend mode, masks, effects, keyframe tracks, text typography and font asset metadata, shape style, camera/light settings and audio settings.

CompositionController owns layer lifecycle, visibility/solo/lock, parent cycle checks, source-in/start/duration clip timing, masks, blend metadata, effect parameters/keyframes, transform keyframes, audio gain keyframes and audio controls.

The NLE timeline shows clip regions at their composition start/duration, supports dragging clips to reposition and resizing the right edge, and exposes source-in time separately from timeline position. Ripple/roll/slip editing, source-out handles, snapping, nested sequences and waveform editing are still open work.

## Global font library and multilingual text

`FontManagerService` discovers readable system `.ttf`/`.otf` files on Windows, macOS, Linux and Android; imports user-selected font files into application support; dynamically registers font bytes through Flutter `FontLoader`; and persists the global app family plus an ordered fallback family list. `ThemeData.fontFamily` and `fontFamilyFallback` apply the global choice across the app. The Compositor Typography panel can override family and fallback per text layer, plus content, size, weight, italic, colour, tracking, line height, alignment and box width. The `.dvproj` manifest stores these settings and embeds the selected font file, including the active global font when a text layer has no local override.

The final composition renderer lays out Unicode text with Flutter `TextPainter` (including shaping and paragraph bidi handling) and rasterizes it to temporary transparent PNGs before feeding the FFmpeg compositor. TTF/OTF runtime loading is supported; WOFF/WOFF2 and TTC collection import are not. System font folders are platform-dependent, iOS system fonts are accessed through normal system fallback rather than filesystem scanning, and no complete world-font bundle is shipped. Font licensing and glyph coverage remain dependent on the supplied fonts.

## Transform, mask and transition compilation

KeyframeTrack samples Hold, Linear, Ease In, Ease Out and Ease In/Out. FfmpegAnimationCompiler converts position, scale, rotation, opacity and audio gain tracks into FFmpeg expressions evaluated at frame/audio-frame time. The compiler also builds alpha expressions for rectangle, ellipse and polygon masks; combines mask operations; and generates wipe/fade/slide/zoom transition expressions.

The first resolver is not a complete matrix hierarchy: anchor-space rotations, skew, constraints and full 3D camera projection are not implemented. Bezier mask handles are not yet rasterized as true curves.

## Audio graph

Video files are inspected with FFprobe for an audio stream. Explicit Audio layers and embedded video audio are fed into a multi-input audio graph. Each track supports gain in dB, pan, fade-in/out, mute, timeline placement and optional Trigger/Background ducking roles. The background track is attenuated by FFmpeg sidechaincompress when the trigger stream is active. A final limiter is applied to mixed multi-track output.

The current graph does not yet provide a full DAW-style rack, EQ automation, waveform cache/editor, surround buses or audio clip envelope UI. Video source audio is mixed only when FFprobe detects the source stream.

## Blend and visual composition

The compositor combines video/image/PSD raster layers in timeline order. Supported non-normal modes use FFmpeg blend, with a separately extracted layer-alpha matte to preserve transparency. The current FFmpeg path is CPU/native 2D compositing; it is not a Vulkan/Metal/OpenGL render graph and it does not render camera/light layers as real 3D scenes.

## Basic motion tracking

MotionTrackingService extracts a grayscale template from a manually entered source-video rectangle, runs FFmpeg find_rect at a configurable sample rate and converts detected rectangle centres into inverse translation keyframes on the selected video layer. This can stabilize a mostly unchanged, high-contrast target. It is not optical flow, homography/planar tracking, rotation/scale solving, face/object recognition or occlusion-aware tracking; manual ROI selection and correct threshold tuning are required.

## Photoshop ingestion

PsdKit reads PSD/PSB. The importer decodes visible raster layers into cached PNGs while retaining source document, layer index, name, bounds, opacity, visibility and blend metadata. Text and adjustment records are retained as editable metadata where available.

This is not equivalent to Photoshop's complete renderer. Group nesting/clipping, every adjustment filter, smart-object rendering, vector paths, text layout/font substitution and all proprietary blend semantics require further renderer work.

## Effect registry

EffectCatalog defines effect identity, categories, parameter ranges/defaults and an FFmpeg filter family. FfmpegFilterCompiler maps a subset of conventional 2D effects to filter strings. Brightness, contrast, saturation and gamma parameter tracks compile to FFmpeg eq expressions evaluated on each frame. Other effect parameters currently sample values at the composition playhead unless a filter has a dedicated frame-evaluation path.

Glow uses a thresholded RGB split, blur and screen blend pass. Drop Shadow derives a blurred alpha matte, expands a transparent canvas and composites the original layer over the offset matte. These are CPU/native FFmpeg multi-pass effects, not GPU shaders. Advanced displacement, optical-flow processing, rotoscoping, particles and many 3D operations still need dedicated GPU or specialised render nodes.

## Current composition renderer

CompositionExportService renders a black composition background with ordered visual layers, Flutter-shaped text raster layers, animated 2D position/scale/rotation/opacity, supported 2D masks, blend modes, transition mattes and multi-track audio. It reports unsupported or missing layers instead of pretending they were rendered. Shape, some adjustment operations and true 3D rendering remain unsupported in this output graph.

This is a functional first NLE/compositor render path, not yet a complete After Effects/Premiere Pro replacement. A capability is only considered complete after automated tests, preview/export parity and target-device validation.

## Performance

- Keep FFmpeg, media probing and PSD extraction off the UI isolate.
- Cache PSD raster layers in app-support storage with lifecycle/size limits.
- Avoid decoding large PSDs repeatedly and guard large image dimensions.
- Use bounded frame/texture caches and release native/GPU resources.
- Detect platform capabilities before enabling AR/3D controls.
- Profile large projects, multitrack audio and full FFmpeg bundle size on target hardware.
