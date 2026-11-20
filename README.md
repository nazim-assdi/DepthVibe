# DepthVibe

One creative studio. Five operating systems. One Flutter codebase.

DepthVibe is an AI-first video, motion-design and 3D creative studio from N Tech. The primary application is Flutter for Android, iOS, Windows, macOS and Linux.

## App appearance and DV branding

Settings now includes **View** presets for **Dark**, **White** and **Eye Comfort**. The selection is saved on the device and updates the Video Studio and Compositor interface immediately. The same gradient **DV** mark and DepthVibe wordmark are used in both workspaces.

Run the command bash tool/bootstrap_platforms.sh to generate the DV launcher assets for Android (including adaptive icons), iOS, macOS, Windows and Linux. The bootstrap also adds the Linux desktop entry and theme icon installation rules.

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
- Global Font Manager scans installed system fonts on Windows (including per-user installs), macOS, Linux and readable Android system font folders. It reads real font family/style names, provides a searchable Premiere-style font picker, and lists installed TTC collection faces. Licensed TTF/OTF files can be imported and applied globally or per Text layer; the same app font is used in Video Studio titles and Compositor. Ordered fallback families cover Bengali, Arabic, Devanagari, CJK, Thai, symbols and emoji where the glyph fonts are installed.
- Text layers have per-layer font family, embedded font asset, fallback list, size, weight, italic, colour, letter spacing, line height, alignment and text-box width. `.dvproj` embeds the selected layer font or active app-default font, and final composition export shapes text with Flutter's text engine before compositing it through FFmpeg.
- Portable `.dvproj` packages save the complete composition (layers, transforms, masks, effects, keyframes, transitions, audio buses and HDR output profile) with linked local media assets. Project autosave recovery snapshots run every 30 seconds when the document has unsaved changes; crash recovery offers a restore prompt, manual saves keep up to 10 previous versions, and missing local media can be relinked across all references. Recovery snapshots retain local asset paths; use `.dvproj` Save to embed assets for transfer to another device.
- GLB/GLTF scene import retains node hierarchy, UV0, normals, animation, metallic/roughness factors and decoded base-colour, metallic-roughness, normal, occlusion and emissive texture payloads. CPU preview samples base colour and applies KHR_texture_transform on UV0; auxiliary PBR maps are imported but not yet shaded.

## Extension system

DepthVibe includes a cross-platform Extension Manager for installing, enabling, disabling and uninstalling declarative .dvext packages. Version 1 packages add named effects backed by audited host renderer operations and may bundle validated .cube LUT assets. Extension effects appear in the Compositor effect library, keep their namespaced IDs and parameters in .dvproj projects, and use the same allow-listed FFmpeg implementation as their host renderer. Packages cannot execute third-party Dart/JavaScript/native code or inject arbitrary FFmpeg commands. See [docs/EXTENSIONS.md](docs/EXTENSIONS.md) and [the sample extension](examples/extensions/cinematic-starter/manifest.json).

Compositor editing also has bounded in-memory Undo/Redo history (80 document states). Playhead scrubbing and layer selection do not create history entries; opening a different project resets the history.

## Global font system

Open the searchable Font Manager from the Video Studio or Compositor toolbar. The picker uses actual installed family/style metadata (for example, family plus Bold/Italic), rather than displaying only font file names. Windows discovery covers both the machine Fonts folder and the current user's LocalAppData Fonts folder. macOS/Linux system and user font folders are scanned too. Installed TrueType Collection (.ttc) files are enumerated face-by-face and use the OS font family.

Import one licensed TTF/OTF file or bulk-import a folder (up to 2,000 candidate files and 1 GiB per operation). TTC is discovered as a system-installed font but is not copied into the app because Flutter's runtime FontLoader only accepts TTF/OTF. The app does not include every world's font and cannot bypass font licences. See the Global Font Manager guide (docs/FONTS.md).

Settings > View provides Dark, White and Eye Comfort appearance presets. The selected appearance applies to Video Studio and Compositor and is persisted on the device.

## Renderer boundaries

The current final-render path is a CPU/native FFmpeg 2D compositor, not a complete GPU scene renderer. It renders text layers rasterized by Flutter's text shaping engine, animated 2D transforms, basic layer mattes, blend compositing, supported transitions and audio tracks. Polygon Bézier handles are not yet a true vector path renderer. Audio effects racks, waveform editing, source clip trimming UI in the composition timeline, and animated effect parameter expressions remain to be built.

Color Studio now shows the selected video’s decoded frame at the playhead and applies a fast primary-grade matrix in the live canvas; this is frame-seeking preview, not continuous real-time playback or GPU/export pixel parity. The scopes are sampled from that current frame and currently include the primary-wheel approximation only (curves/LUT are not included in scope data). Curves and LUTs are export-only at present. HDR10 PQ and HLG output use a Rec.709-to-BT.2020 zscale conversion and ProRes 422 HQ 10-bit MOV tags; this is not scene-referred HDR grading, HDR source preservation, Dolby Vision, or mastering-metadata authoring. Shot matching, LUT authoring/management, GPU preview parity and full colour-managed 10/12-bit processing remain open. The 3D workspace now has a CPU mesh projector/shader and a WebGPU triangle raster backend with depth testing and MSAA. For opaque meshes sharing one base-colour image, the GPU path uploads RGBA textures and samples them in WGSL using UV0 and a repeat/linear sampler; multiple distinct base-colour images and MASK/BLEND materials use the CPU fallback. Geometry projection and scene-light shading remain CPU-evaluated before GPU upload. Metallic-roughness, normal, occlusion and emissive maps are decoded and retained but are not yet applied to lighting; the WebGPU path is not yet a complete PBR renderer. The 3D preview/export pipeline is not yet integrated into the final FFmpeg compositor. A basic 2D template tracker can track a manually selected rectangle and write translation keyframes; planar/perspective tracking, scale/rotation solving, occlusion handling and rotoscoping remain open work. Full PSD groups/clipping/smart objects and Photoshop-style adjustment rendering also remain open. Glow and Drop Shadow now have CPU multi-pass export paths, but there is no complete GPU VFX render graph yet. Optical-flow effects, advanced denoise, displacement, volumetrics and high-end VFX still need a dedicated GPU renderer. An effect-library entry does not mean that effect is complete in final export.

## Adobe editable interchange

Capture active Premiere Pro sequences and After Effects compositions as editable DepthVibe layers, preserve source IDs/unsupported effects, export FCP 7 XML for Premiere clip interchange, and generate an After Effects JSX layer-import script. See [Adobe Compatibility](docs/ADOBE_COMPATIBILITY.md) for supported effects and limitations.

## Extension ecosystem and Adobe interoperability

DepthVibe has a declarative `.dvext` installer and a signed marketplace client. Publisher public keys are imported from `.dvpub` files and explicitly trusted by SHA-256 fingerprint. Marketplace catalogs are Ed25519-signed; downloaded package bytes are checked against the SHA-256 digest covered by the catalog signature. Opt-in automatic updates apply only to DepthVibe `.dvext` packages. No production marketplace feed or publisher is pre-trusted in the repository; operators must host and sign their own HTTPS catalog using the scripts in `tool/`.

Adobe host adapters are provided as panel source:
- Premiere Pro 25.6+: UXP panel under `integrations/adobe/premiere-uxp/`.
- After Effects stable: CEP compatibility panel under `integrations/adobe/after-effects-cep/`.
- After Effects Beta: UXP panel source under `integrations/adobe/after-effects-uxp-beta/`, to be loaded into Adobe's generated AE Beta starter project.

The Adobe panels use an authenticated localhost bridge to list DepthVibe effects and exchange DepthVibe composition JSON. On macOS, Adobe UXP network access requires HTTPS; the local bridge supports a user-supplied trusted certificate. This initial adapter is not yet an arbitrary Premiere sequence or After Effects composition importer. Adobe native `.prm`/`.aex` plug-ins remain native code that must execute inside the appropriate Adobe host; they are not loaded into Flutter or `.dvext` packages.

See [Extension package format](docs/EXTENSIONS.md), [Marketplace publishing](docs/MARKETPLACE_AND_PUBLISHING.md), [Adobe compatibility](docs/ADOBE_COMPATIBILITY.md), and the [Adobe Bridge SDK](integrations/adobe/sdk/README.md).
 
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
- lib/features/extensions: .dvext install manager, signed marketplace, publisher trust store and Adobe localhost bridge.
- integrations/adobe: Premiere UXP, After Effects CEP/UXP Beta panels and TypeScript bridge SDK.
- docs/MARKETPLACE_AND_PUBLISHING.md and docs/ADOBE_COMPATIBILITY.md: publisher signing, updates and Adobe host compatibility.
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
