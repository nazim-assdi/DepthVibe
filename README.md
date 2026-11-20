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
- Brightness, contrast, saturation and gamma effect keyframes are evaluated per frame. The Color page includes per-layer Lift/Gamma/Gain/Offset wheels (including animated RGB wheel channels), Temperature/Tint, Contrast, Exposure, Master Gamma, Saturation, draggable Master/RGB curves, validated 3D `.cube` LUT import with Nearest/Trilinear/Tetrahedral/Pyramid/Prism interpolation, current-frame Luma Waveform/RGB Parade/Vectorscope, and Rec.709/HDR10 PQ/HLG output profiles. Primary wheel and curve operations compile to FFmpeg filters; the current live viewer grades decoded playhead frames with a fast matrix approximation. The export path uses FFmpeg colorbalance/geq/eq/curves/lut3d filters.
- PSD/PSB import extracts visible raster layers to independent cached PNGs and keeps source metadata where available.
- Portable `.dvproj` packages save the complete composition (layers, transforms, masks, effects, keyframes, transitions, audio buses and HDR output profile) with linked local media assets. Project autosave recovery snapshots run every 30 seconds when the document has unsaved changes; crash recovery offers a restore prompt, manual saves keep up to 10 previous versions, and missing local media can be relinked across all references. Recovery snapshots retain local asset paths; use `.dvproj` Save to embed assets for transfer to another device.
- GLB/GLTF scene import retains node hierarchy, UV0, normals, animation, metallic/roughness factors and decoded base-colour, metallic-roughness, normal, occlusion and emissive texture payloads. CPU preview samples base colour and applies KHR_texture_transform on UV0; auxiliary PBR maps are imported but not yet shaded.

## Renderer boundaries

The current final-render path is a CPU/native FFmpeg 2D compositor, not a complete GPU scene renderer. It renders animated 2D transforms, basic layer mattes, blend compositing, supported transitions and audio tracks. Polygon Bézier handles are not yet a true vector path renderer. Audio effects racks, waveform editing, source clip trimming UI in the composition timeline, and animated effect parameter expressions remain to be built.

Color Studio now shows the selected video’s decoded frame at the playhead and applies a fast primary-grade matrix in the live canvas; this is frame-seeking preview, not continuous real-time playback or GPU/export pixel parity. The scopes are sampled from that current frame and currently include the primary-wheel approximation only (curves/LUT are not included in scope data). Curves and LUTs are export-only at present. HDR10 PQ and HLG output use a Rec.709-to-BT.2020 zscale conversion and ProRes 422 HQ 10-bit MOV tags; this is not scene-referred HDR grading, HDR source preservation, Dolby Vision, or mastering-metadata authoring. Shot matching, LUT authoring/management, GPU preview parity and full colour-managed 10/12-bit processing remain open. The 3D workspace now has a CPU mesh projector/shader and a WebGPU triangle raster backend with depth testing and MSAA. For opaque meshes sharing one base-colour image, the GPU path uploads RGBA textures and samples them in WGSL using UV0 and a repeat/linear sampler; multiple distinct base-colour images and MASK/BLEND materials use the CPU fallback. Geometry projection and scene-light shading remain CPU-evaluated before GPU upload. Metallic-roughness, normal, occlusion and emissive maps are decoded and retained but are not yet applied to lighting; the WebGPU path is not yet a complete PBR renderer. The 3D preview/export pipeline is not yet integrated into the final FFmpeg compositor. A basic 2D template tracker can track a manually selected rectangle and write translation keyframes; planar/perspective tracking, scale/rotation solving, occlusion handling and rotoscoping remain open work. Full PSD groups/clipping/smart objects and Photoshop-style adjustment rendering also remain open. Glow and Drop Shadow now have CPU multi-pass export paths, but there is no complete GPU VFX render graph yet. Optical-flow effects, advanced denoise, displacement, volumetrics and high-end VFX still need a dedicated GPU renderer. An effect-library entry does not mean that effect is complete in final export.

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
- docs/PRO_STUDIO_ROADMAP.md: professional NLE, motion-design, audio, colour, GPU VFX and 3D engineering plan.

## Product goal

DepthVibe aims to become a professional NLE and compositor combining multi-track video/audio, colour finishing, Photoshop-aware animation, 2D/3D compositing, camera tracking, procedural VFX and a node graph. Matching or exceeding established creative suites is an ambition—not a present performance claim. A capability is complete only when it works in preview, is baked into final export and is verified on supported devices and operating systems.

Product: DepthVibe
Developer: N Tech
Primary stack: Flutter / Dart
