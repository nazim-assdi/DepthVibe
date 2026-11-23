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

The transition browser has a Flutter CustomPainter A/B preview tile. Mouse hover starts and stops the preview animation; its Apply action calls the same CompositionController transition-add operation used by the quick-add picker. It exposes all 61 TransitionKind values plus 38 named transition recipes with curated durations. Generated scenes demonstrate the direction and mask family; exact filter-specific pixel behaviour is still determined by FFmpeg at render time.

The unified Asset Library combines 39 original EffectPresetDefinition looks, 54 MotionPresetDefinition keyframe recipes, the 38 transition recipes and the 68 native effect registry entries. CompositionController.applyEffectPreset resolves every step against EffectCatalog, starts from registered defaults, validates parameter IDs and clamps values to the native parameter ranges before adding independent EffectInstance entries. Motion recipes are ordinary editable layer keyframes. The Library UI also links to the signed extension Marketplace, .dvmpreset transfer and locally imported Motion Bro packs; third-party paid pack files are not bundled or unlocked.

## Creative asset library

The Composition workspace's Library panel combines the native effect registry, 39 original multi-effect recipes, 54 motion keyframe recipes, 38 curated transition recipes, 72 overlay/sticker assets, 41 audio track presets, 39 title/lower-third styles and 48 primary color grades. The six user-facing categories are Overlays & Stickers, Motion, Audio Presets, Titles & Lower Thirds, Color Presets, and Video Effects & Filters; Transitions remain separately searchable.

Effect looks resolve each step through EffectCatalog, validate parameter names against registered schemas and clamp values before adding normal EffectInstance models. Motion recipes create normal KeyframeTrack values. Titles and text stickers create editable LayerKind.text layers, then apply a native motion recipe. Raster overlays and audio can be imported as regular image/audio layers. Color presets reuse ColorGradePreset and the existing color-grade compiler. Audio presets are intentionally limited to the project model's track gain, 3-band EQ, pan and fade values; advanced audio DSP such as reverb and de-essing remains unimplemented.

OpenAssetSourceCatalog links to public CC0/Creative Commons collections with per-source licence labels. It does not bundle those remote files: users open the original source and import media/LUTs into the project, retaining applicable credits. The signed .dvext publisher marketplace remains a separate verified package channel.

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

CompositionExportService renders a black composition background with ordered visual layers, Flutter-shaped text raster layers, editable vector shape layers, animated 2D position/scale/rotation/opacity, supported 2D masks, blend modes, transition mattes and multi-track audio. Primitive shapes and cubic Bezier paths are rasterized to transparent PNGs for the CPU/FFmpeg compositor; animated path vertices are rasterized per output frame, while static shapes use a single cached render for the export job. Adjustment layers process the accumulated lower-layer image and are blended according to their active timeline range and animated opacity. Color-grade adjustments also preview through the shared colour-matrix approximation; other supported native effects are currently guaranteed only in the FFmpeg export path and can differ from live preview. Unsupported or missing layers are reported instead of silently rendered. Full Photoshop adjustment semantics, true extruded 3D text, GPU PBR parity and some advanced 3D/effect operations remain outside this renderer.

This is a functional first NLE/compositor render path, not yet a complete After Effects/Premiere Pro replacement. A capability is only considered complete after automated tests, preview/export parity and target-device validation.

## Performance

- Keep FFmpeg, media probing and PSD extraction off the UI isolate.
- Cache PSD raster layers in app-support storage with lifecycle/size limits.
- Avoid decoding large PSDs repeatedly and guard large image dimensions.
- Use bounded frame/texture caches and release native/GPU resources.
- Detect platform capabilities before enabling AR/3D controls.
- Profile large projects, multitrack audio and full FFmpeg bundle size on target hardware.

## Downloadable offline asset packs

The Compositor's CreativeAssetPackService downloads selected open-licensed upstream ZIP packs to application-support storage; the payload is not embedded in the APK or desktop installer. Its catalog currently has 24 DAEDAL CC0 packs plus two CLR audio volumes (about 5.21 GB of archive data). The installer streams HTTPS downloads, verifies declared sizes where known, decodes ZIP CRCs, rejects path traversal, duplicate paths, symlinks/hardlinks and oversize entries, requires a licence file, extracts into a staging directory and atomically installs metadata and media. Installed packs are indexed for image, SVG, video/GIF, audio and LUT assets, which can be added to the active composition as editable media layers or LUT effects. Individual packs can be removed without uninstalling the app. AssetPolish's full 3,869-vector catalog is not represented by a single bulk archive; selected-assets ZIPs can be imported, retaining their source/licence notice.

CRC verification detects archive corruption; it is not a cryptographic publisher signature. These open media packs are separate from the signed .dvext extension marketplace. The 5.21 GB total is the download archive estimate before extraction, and the app installer size is not increased by that amount.

Portable .dvproj Save embeds the referenced media and, when a source file belongs to a locally installed/imported creative pack, also carries its source URL, declared licence label and matching licence/notice files in assets/_licenses/. Each credit entry identifies which embedded project assets came from that pack. Import validates and restores those notices; legacy .dvproj files without credit records remain supported. A manually imported file without an installed-pack pack.json is embedded as media but cannot have licence attribution inferred automatically.
