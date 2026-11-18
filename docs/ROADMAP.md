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
- [ ] Multi-track clip edit tools: source in/out, ripple/roll/slip, snapping, waveforms, audio envelopes, nested sequences.
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
- [ ] Animated effect-parameter expressions for every effect node.
- [ ] Shape/text rasterization and Photoshop adjustment layer rendering.
- [ ] Bezier mask curve editor, animated masks, tracking masks and rotoscoping.
- [ ] Render queue, proxy media, cache manager, waveform cache and deterministic realtime preview.

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
