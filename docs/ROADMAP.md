# DepthVibe roadmap

Status describes working source paths, not release-ready feature parity. A model or control does not count as complete until the feature is visible in preview and baked into an automated-test and platform-verified export.

## Stage 0 — Cross-platform Flutter foundation
- [x] Flutter app for Android, iOS, Windows, macOS and Linux.
- [x] Preserve the previous Android-native project under legacy/android-native.
- [x] Video import, preview, camera capture, trim, speed, rotate, mute and MP4 export path.
- [x] Configure the full LGPL FFmpeg native bundle (GPL disabled).
- [ ] Validate binary size, codecs, playback and export on every platform/device.

## Stage 1 — NLE and layer foundation
- [x] Composition document and video/image/PSD/text/shape/audio/Null/Adjustment/Camera/Light/3D/particle/precomposition layer registry.
- [x] Layer selection, visibility, solo, lock and ordering model.
- [x] Null/parent links with cycle checking and initial transform propagation.
- [x] Position, anchor, scale, rotation and opacity properties.
- [x] Hold, Linear, Ease In, Ease Out and Ease In/Out keyframe interpolation.
- [x] Dedicated Audio layer and embedded source-video audio probing/mixing.
- [x] Audio gain keyframes, pan, fade-in/out and sidechain ducking controls.
- [x] PSD/PSB visible raster extraction into independent PNG assets.
- [x] Timeline clip placement, drag-to-move, right-edge duration resize and source-in trim fields for video/audio layers.
- [ ] Ripple/roll/slip editing, source-out handles, snapping, waveforms, audio envelopes and nested sequences.
- [ ] Project save/open, autosave, undo/redo, crash recovery and relinking.
- [ ] Full matrix parenting, anchor-space transforms, skew and expression editor.

## Stage 2 — Composition render graph
- [x] FFmpeg compositor for video/image/PSD raster layers.
- [x] Per-frame transform expression export for position, scale, rotation and opacity.
- [x] Rectangle, ellipse and polygon alpha mattes with feather/expansion/invert and boolean operations.
- [x] Non-normal layer blending using native FFmpeg blend modes.
- [x] Fade/dissolve, wipe, slide, zoom and luma-style transition expressions.
- [x] Multi-track audio mix, audio gain animation, fades and sidechain ducking.
- [x] FFmpeg filter compiler for a subset of conventional 2D effects.
- [x] Per-frame parameter expressions for brightness, contrast, saturation and gamma.
- [x] CPU multi-pass thresholded glow and alpha-derived drop shadow export.
- [ ] Animated parameter expressions for all effects and GPU multi-pass nodes for high-end VFX.
- [ ] Shape/text rasterization and Photoshop adjustment layer rendering.
- [ ] Bezier mask curve editor, animated masks, tracking masks and rotoscoping.
- [ ] Render queue, proxy media, cache manager, waveform cache and deterministic realtime preview.
- [x] Bounded compositor preview decode queue with latest-frame-wins scheduling, shared in-flight requests, memory/disk frame cache, atomic frame writes and per-layer one-second chunk lookahead.
- [x] Adaptive preview resolution/FPS driven by native frame-decode and Flutter build/raster timings; isolate high-frequency playhead updates from inspector/panel rebuilds.
- [x] Realtime Compositor Play/Pause transport with stale-frame dropping, visible-last-frame fallback, bounded decoder concurrency and preview cache cleanup.
- [x] Active composition export cancellation, staged progress and incomplete-output cleanup; persistent multi-job scheduling, durable logs and retry remain open.
- [x] Low-spec live 3D preview presets for Compatibility, Balanced and Quality; final render quality is not reduced by the preview setting.

## Stage 3 — Colour and VFX
- [x] Basic exposure/contrast/saturation/blur/sharpen/keying effect mappings.
- [ ] GPU multi-pass glow, shadow, displacement, optical flow, denoise, motion vectors and advanced keying.
- [ ] Colour wheels, scopes, LUT library, HDR and 10-bit pipeline.
- [ ] Node-based compositing graph with renderable nodes and graph validation.

## Stage 4 — 3D and tracking
- [x] Camera and light layer data models and controls.
- [ ] Cross-platform GLB/OBJ scene renderer integrated with composition preview and export.
- [ ] Camera projection, depth of field, environment maps, real lights and shadow maps.
- [x] Basic 2D template matching from a manually entered ROI with translation keyframes for stabilization.
- [ ] Optical-flow/planar tracking, perspective/rotation/scale solve, track-to-null, occlusion handling and 3D camera solve.
- [ ] Camera-matched 3D composites and shadow catcher.
- [ ] Physics, mesh shatter, fluid/smoke/fire and particles rendered into final output.

## Stage 5 — Pro experience
- [ ] Draggable dockable panels, keyboard shortcuts, search/command palette and custom workspaces.
- [ ] Bezier graph editor, motion paths, expressions and reusable presets.
- [ ] Full project interchange, asset relinking and template/preset ecosystem.

## Release gate

A capability is complete only when it has a project model, working controls, real-time preview, final export implementation, automated tests and physical-device/platform validation. 2D filter-based compositing and true 3D scene rendering are treated as separate render backends.


## Extension system and editing reliability update — 20 November 2026

- [x] Declarative .dvext package validation, installation and local registry.
- [x] Extension enable/disable/uninstall controls.
- [x] Effect library registration backed by audited host renderer operations.
- [x] Bundled .cube LUT package assets with safe extraction rules.
- [x] Bounded composition Undo/Redo controls.
- [x] Signed extension marketplace model, publisher signatures and opt-in .dvext updates.
- [x] Initial TypeScript bridge SDK and Adobe host-adapter contract; native/GPU extension runtime remains open.
- [ ] Undo transaction grouping for continuous drag/slider gestures and durable history snapshots.


## Stage 6 — Extension marketplace and Adobe interoperability

- [x] Declarative .dvext package format with safe package extraction, extension registry, enable/disable/uninstall.
- [x] Signed marketplace catalog model and UI with Ed25519 publisher signature verification.
- [x] .dvpub publisher-key import, fingerprint verification, explicit trust and revoke controls.
- [x] Publisher key-generation and catalog-signing CLI tools; catalog template and publishing guide.
- [x] Opt-in automatic version checks; transactional automatic updates for DepthVibe .dvext packages only.
- [x] Premiere Pro 25.6+ UXP bridge panel source and Adobe local authenticated bridge.
- [x] After Effects CEP compatibility panel and After Effects Beta UXP bridge-panel source.
- [x] Bridge SDK protocol types, client and host-adapter contract.
- [ ] Premiere sequence/track/clip import and export translation with host DOM round-trip tests.
- [ ] After Effects project/comp/layer/keyframe/expression translation with host DOM round-trip tests.
- [ ] Effect capability mapping and render parity for individual Adobe host effects.
- [ ] Native .prm/.aex plugin integration through separate Adobe C++ SDK builds, platform signing and host certification.
- [ ] Marketplace backend hosting, publisher onboarding/review, key-rotation workflow and update rollback UI.

Adobe panels exchange DepthVibe composition JSON and effect descriptors through a paired loopback bridge. They are initial compatibility adapters, not general-purpose Premiere sequence or After Effects project translators. Marketplace feed hosting and publisher trust are operator/user managed; the repository does not include a production marketplace server or a pre-trusted publisher.
