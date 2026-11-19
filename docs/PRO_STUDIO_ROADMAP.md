# DepthVibe Professional Studio Roadmap

DepthVibe is intended to combine a professional nonlinear video editor, motion-design compositor, colour-finishing workspace and 3D/VFX environment in one cross-platform application. This document defines the engineering sequence and the evidence required before a feature is called complete.

## Product principles

1. One project format, one application and one primary branch (`main`).
2. Preview and final export must use the same render graph semantics. A control or metadata field is not a finished feature.
3. Local-first editing: media stays on the user's device unless the user explicitly chooses a cloud/AI service.
4. Hardware acceleration is capability-detected. CPU fallback remains available for supported operations.
5. Long renders, waveform generation, tracking and media probing never block Flutter's UI isolate.
6. Every project is recoverable: autosave, versioned project files, undo/redo and relinkable media.

## Target workspace

- **Edit:** source monitor, program monitor, multi-track timeline, track targeting, snapping, ripple/roll/slip edits, trim tools, markers, nested sequences and proxy controls.
- **Composite:** layer stack, masks, mattes, blend modes, keyframes, motion paths, graph editor, parenting and precompositions.
- **Audio:** multi-track mixer, clip gain/envelopes, waveform cache, EQ, compressor, limiter, buses, automation and ducking.
- **Colour:** primary wheels, curves, qualifiers, scopes, LUT management, shot matching, HDR-aware pipeline and colour-managed export.
- **VFX:** node graph, keying, roto/masks, planar and point tracking, stabilization, particles, optical flow, displacement, glow, shadow and denoise.
- **3D:** GLB/OBJ scene import, mesh/material controls, camera projection, lights, environment maps, depth of field and shadow catcher.
- **Deliver:** render queue, presets, codec/container controls, bitrate/quality, audio layout, subtitles, alpha-capable intermediate formats where supported, and render reports.

## Engineering architecture

### A. Document and edit model
- Versioned project schema with stable IDs, relative media paths, asset manifest and migration functions.
- Separate source-media metadata from timeline clip instances.
- Explicit sequence, track, clip, transition, effect, mask, audio-bus and node-graph models.
- Command-based edits with bounded undo/redo history and autosave snapshots.
- Media relinking by stable asset ID, filename, size and optional content hash.

### B. Render graph
- Keep the current FFmpeg path as a reliable CPU 2D backend for operations it can render correctly.
- Introduce a backend-neutral render graph: source, decode, transform, mask, effect, blend, transition, audio mix and output nodes.
- Add a GPU backend behind capability interfaces (Vulkan on supported Windows/Linux/Android devices; Metal on Apple platforms). Never assume identical GPU features across devices.
- Use explicit colour-space, pixel-format, alpha-mode and frame-time metadata on graph edges.
- Add deterministic frame rendering so preview, thumbnails and export evaluate the same graph at the same timestamp.
- Unsupported nodes must produce a visible validation error and be listed in the export report; never silently omit content.

### C. Media and timeline
- Implement source monitor and timeline clip instances with independent source-in/source-out and timeline-in/timeline-out.
- Add snapping, ripple, roll, slip, slide, blade, track targeting, linked audio/video and multi-select.
- Add waveform/peak cache, thumbnails, proxy generation and background conform jobs.
- Add nested sequences and compound clips only after clip timing and relinking are stable.

### D. Motion and compositing
- Evaluate transform and effect parameter tracks per frame, not just at the playhead.
- Add Bezier temporal/spatial interpolation, graph editor, motion-path handles and expression safety limits.
- Render editable Bezier masks, animated masks, track mattes and rotoscoping outputs.
- Make transitions first-class graph nodes that combine adjacent clips with handles and correct frame-accurate offsets.
- Complete PSD/PSB import in stages: groups, clipping, masks, text fallback, smart-object rasterization and adjustment-layer equivalents. Unsupported Photoshop features must be reported.

### E. Audio
- Build waveform and envelope editing, clip fades, keyframe automation, EQ and dynamics.
- Support track/bus routing, pre/post-fader sends, sidechain routing and a master limiter.
- Keep audio sample timing independent from video frame timing; test sync over long exports.

### F. Colour and VFX
- Add colour-managed processing and scopes before advanced grading controls.
- Build reusable effect nodes with parameter schemas, animated values, GPU/CPU implementations and reference tests.
- Prioritize keying, tracking, roto, displacement, optical flow, denoise, glow, shadow and particle systems.
- Add render-quality tiers and proxy/preview resolution controls.

### G. 3D and tracking
- Integrate a real scene renderer for meshes, materials, cameras and lights; camera/light controls alone do not count.
- Add point tracking, planar tracking, scale/rotation solving, occlusion-aware tracks and track-to-null.
- Add 3D camera solve and camera-matched compositing only after tracking quality has measurable validation clips.

## Delivery sequence

### Milestone 1 — Reliability and project foundation
- [ ] Versioned project save/open and migration tests.
- [ ] Autosave, crash recovery and undo/redo.
- [ ] Media relink and missing-media report.
- [ ] Render queue with cancellation, progress, logs and retry.
- [ ] Export validation report and preview/export parity fixtures.

### Milestone 2 — Professional NLE
- [ ] Source monitor and timeline clip-instance model.
- [ ] Source-out handles, snapping, ripple/roll/slip/slide and linked clips.
- [ ] Multi-select, track targeting, markers and nested sequences.
- [ ] Waveforms, thumbnails and proxy media.

### Milestone 3 — Motion graphics and compositing
- [ ] Full-frame animated effect parameter evaluation.
- [ ] Bezier graph editor and motion paths.
- [ ] Shape/text rasterization in preview and export.
- [ ] Bezier masks, animated masks, track mattes and rotoscoping.
- [ ] Correct clip-to-clip transition rendering with handles.

### Milestone 4 — Audio and colour finishing
- [ ] Waveform/envelope editor and audio effect racks.
- [ ] Buses, EQ, dynamics, automation and sync tests.
- [ ] Colour wheels, curves, scopes, LUTs and colour management.
- [ ] HDR/10-bit support where platform encoders and decoders allow it.

### Milestone 5 — GPU VFX and 3D
- [ ] GPU render backend with device capability detection and CPU fallback.
- [ ] GPU multi-pass effects and render-graph caching.
- [ ] GLB/OBJ scene rendering in preview and export.
- [ ] Camera/light projection, depth of field and shadow maps.
- [ ] Advanced tracking, particles and camera-matched composites.

### Milestone 6 — Pro workflow and release
- [ ] Dockable workspaces, command palette and complete shortcut map.
- [ ] Template/preset browser and project interchange.
- [ ] Performance benchmarks on low-, mid- and high-tier hardware.
- [ ] Platform-specific export, crash, memory and long-timeline test suites.
- [ ] Licence, codec, privacy and distribution review.

## Definition of done

A feature is complete only when all of the following are true:

- It has a persisted project model and migration behaviour where applicable.
- Its controls are connected to the model and provide undo/redo.
- It renders correctly in the preview at arbitrary playhead positions.
- It renders correctly in final export using the same semantics.
- Automated unit, integration and golden-frame tests pass.
- It has been tested on every platform claimed as supported, with capability fallbacks documented.
- Performance and memory behaviour are measured on representative hardware.
- The export report identifies any unsupported media, effect or colour conversion.

## Current baseline and known gaps

The current codebase has a Flutter multi-platform shell, MediaKit preview, FFmpeg export, composition/layer models, 2D transform/keyframe compilation, basic masks/blends/transitions, multi-track audio mixing, PSD raster extraction, a basic template tracker and CPU glow/shadow passes. These are useful foundations, not feature parity with Premiere Pro, After Effects or DaVinci Resolve.

The current composition exporter explicitly skips layer kinds it cannot render. In particular, true 3D scene rendering, complete text/shape/adjustment rendering, full PSD semantics, GPU VFX, advanced tracking and a professional NLE editing toolset remain engineering work. Do not mark these complete until the definition-of-done gates above pass.

## Implementation Update — 19 November 2026

The following foundations have now been added on the single `main` branch:

- **Cubic Bezier keyframes:** keyframes persist normalized X/Y control handles; the Dart sampler evaluates the curve using a stable bounded solve; FFmpeg export compiles the same curve into a frame-evaluated expression.
- **Bezier graph UI:** transform-property keyframes can switch to cubic Bezier and open an interactive two-handle graph editor. Existing keyframe data without Bezier controls loads with default controls.
- **Bezier masks:** export now flattens cubic segments from vertex in/out handles into a deterministic mask outline. The Masks panel exposes anchor and tangent editing, and smooth tangents keep opposing handles collinear.
- **Audio EQ:** the Audio panel has low (120 Hz), mid (1 kHz) and high (8 kHz) parametric bands. A dedicated compiler turns non-neutral settings into native FFmpeg EQ filters and bounds gain to a safe editing range.
- **Timeline waveform thumbnails:** audio clips generate a local cached waveform PNG with FFmpeg `showwavespic`; the editor reuses the per-source future while the workspace is open.
- **Regression tests:** curve sampling, keyframe serialization, FFmpeg curve expression generation, Bezier mask outline complexity, smooth tangent alignment and EQ filter generation have targeted tests.

### Verification status

GitHub Actions runs were created by the commits, but the latest observed runs were still queued. Therefore Flutter analyze/tests and platform builds are **not yet marked as CI-passed or build-verified**. Local FFmpeg 7.1.5 command-line smoke tests did succeed for the cubic expression syntax, the `showwavespic` waveform image, and the 3-band EQ filter chain. No APK/desktop release artifact has been produced in this update.

### Still outstanding from the requested pro-studio scope

The Bezier graph is currently exposed for transform-property tracks; a unified graph editor for every effect/audio property remains. Animated mask properties and rotoscoping are not complete. The waveform is currently a static cached clip thumbnail, not a zoomable sample-accurate envelope editor; full automation lanes, bus routing and advanced dynamics are not complete. Preview/export parity still needs frame-by-frame validation for every blend mode and transition. The cross-platform 3D camera/light renderer, planar/perspective/3D tracking, complete PSD group/clipping/adjustment/smart-object fidelity, and a true GPU multi-pass VFX pipeline remain separate engineering milestones.
