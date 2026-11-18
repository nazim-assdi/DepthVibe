# DepthVibe roadmap

Status describes source foundations, not release-ready feature parity. A model, parameter or UI control does not count as complete until the feature is visible in preview and baked into a tested export.

## Stage 0 — Cross-platform Flutter foundation
- [x] Flutter app for Android, iOS, Windows, macOS and Linux.
- [x] Preserve the previous Android-native project under legacy/android-native.
- [x] Video import, preview, camera capture, trim, speed, rotate, mute and MP4 export path.
- [x] Configure the full LGPL FFmpeg native bundle (GPL disabled).
- [ ] Validate actual binary size, codecs, playback and export on every platform/device.

## Stage 1 — AE-style layer and animation foundation
- [x] Composition document and layer registry: video, image, PSD raster, text, shape, audio, Null, Adjustment, Camera, Light, 3D model, particles and precomposition.
- [x] Layer selection, visibility, lock and basic layer stack.
- [x] Null/parent links with cycle checking and initial transform propagation.
- [x] Position, anchor, scale, rotation and opacity properties.
- [x] Keyframes with Hold, Linear, Ease In, Ease Out and Ease In/Out interpolation.
- [x] Shape primitives/style controls and camera/light settings.
- [x] PSD/PSB visible raster extraction into independent PNG assets.
- [ ] Full PSD groups, clipping masks, smart objects, text formatting, vector paths and all adjustment layers.
- [ ] Project save/open, autosave, undo/redo and crash recovery.
- [ ] Full matrix parenting, anchors, skew, 3D constraints and expression engine.

## Stage 2 — Effect, mask and transition systems
- [x] Effect catalog, categories, parameters and default ranges.
- [x] Keyframe model and UI for effect parameters.
- [x] FFmpeg filter compiler for a subset of common 2D effects.
- [x] Mask model for rectangle, ellipse, polygon and Bezier, with operation/feather/expansion/invert controls.
- [x] Transition model for dissolve, wipe, slide, zoom, blur and luma.
- [ ] Bezier mask editor, animated paths, feather handles and rotoscoping.
- [ ] Shared GPU effects runtime for glow, shadows, displacement, advanced keying, optical flow and deep blur.
- [ ] Per-frame animated effect rendering, masks and every blend mode in final export.
- [ ] Full transition timeline, handles and clip-aware crossfade output.
- [ ] Colour wheels, curves, scopes, LUT library, HDR and 10-bit pipeline.

## Stage 3 — Composition render graph
- [x] Initial FFmpeg compositor for video/image/PSD raster layers.
- [x] Static position/scale/rotation/opacity and a subset of FFmpeg effects in the first export pass.
- [ ] Multi-track video overlaps, audio tracks, volume/keyframes, ducking and waveforms.
- [ ] Render shape/text layers and adjustment layers.
- [ ] PSD blend modes, non-normal blending and mask operations in export.
- [ ] Keyframe transform curves rendered for every frame.
- [ ] Shared deterministic real-time preview and export graph.
- [ ] Render queue, proxy media, cache manager and background rendering.

## Stage 4 — 3D, tracking and simulation
- [x] Camera and light layer data models and controls.
- [x] 3D transform fields and keyframe-capable layer model.
- [ ] Cross-platform GLB/OBJ render backend in the composition canvas.
- [ ] Camera projection, depth-of-field, lights, environment maps and real shadow passes.
- [ ] Planar/point tracking, 2D/3D track data, constraints and correction tools.
- [ ] Port recorded-footage solve and AR workflows to shared platform backends.
- [ ] Camera-matched 3D composites and shadow catcher.
- [ ] Physics, mesh shatter, fluid/smoke/fire and particles rendered into final export.

## Stage 5 — Pro experience
- [ ] Draggable dockable panels, keyboard shortcuts, search/command palette and custom workspaces.
- [ ] Node-based graph editor with executable nodes and graph validation.
- [ ] Bezier graph editor, motion paths, expressions and reusable presets.
- [ ] Full project interchange, asset relinking and template/preset ecosystem.

## Release gate

A capability is complete only when it has a project model, working controls, real-time preview, final export implementation, automated tests and physical-device/platform validation.
