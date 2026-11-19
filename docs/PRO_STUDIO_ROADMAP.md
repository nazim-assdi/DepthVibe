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

## Implementation Update — 19 November 2026 (continued)

The following additional work is now committed on `main`:

- **Audio bus automation:** each Master/Submix bus has keyframe tracks for Gain and Pan. The Bus Mixer exposes keyframe controls, the unified Animation panel lists bus tracks, and Bezier editing/interpolation can target a bus keyframe. FFmpeg export compiles Gain to frame-evaluated volume and Pan to sample-time stereo expressions.
- **Bus dynamics and routing:** track-to-bus routing, submix aggregation, bus gain/pan, compressor, makeup gain and limiter are connected to the export graph. Sidechain trigger sources are split so ducking and bus routing can both consume them.
- **Transition frame checks:** new transitions snap to the composition frame grid; the editor reports off-grid times, missing layers, out-of-range transitions and clip-range warnings.
- **Parent/group transform parity:** export compiles the same additive position/scale/rotation/opacity parent-chain math as the preview. Disabled PSD folder parents now hide descendants in preview and export.
- **PSD structure:** folder start/end records become structural group layers, nested parent references and clipping-base references are retained, embedded Smart Object source files are extracted, and embedded PSD/PSB merged previews are decoded when possible.
- **Partial PSD adjustment rendering:** Brightness/Contrast, Invert, Posterize and Threshold are mapped to native compositor effects where the PSD data is recognized. Adjustment layers run over the previously composited frame at their layer-stack position. Posterize and Threshold use alpha-preserving LUT filters rather than relying on optional FFmpeg filter names.
- **CPU VFX fallback:** procedural displacement and particle dust compile to FFmpeg per-frame pixel expressions. These are CPU export passes, not GPU render passes.

### Latest verification notes

Local FFmpeg 7.1.5 smoke tests succeeded for animated bus Gain/Pan, Bezier frame-evaluated scaling, displacement, particle dust, Threshold and Posterize LUT passes. GitHub Actions for the latest commit are still queued; Flutter analyze/tests and platform builds therefore remain **pending CI confirmation**. No new APK/desktop release artifact has been produced in this update.

### Remaining gaps / explicit limits

- Bus Gain/Pan automation is wired; bus compressor threshold/ratio/attack/release and EQ controls are still static parameters, not fully automated lanes.
- Animated masks currently cover geometry bounds, feather, expansion and opacity; animated individual vertex/tangent paths and rotoscoping remain incomplete.
- PSD clipping-base references are imported and retained but are not yet applied as a true alpha clipping stack in the renderer. Embedded Smart Objects retain their source and a flattened merged preview; live re-render/relink editing is not implemented. Adjustment coverage is partial and does not reproduce every Photoshop adjustment, mask, style or filter.
- Blend modes still need frame-by-frame preview/export parity testing.
- Camera/light records and 3D transforms still do not have an integrated GLB/OBJ scene renderer, depth-of-field or shadow-map pipeline.
- Tracking is still template-based translation tracking; planar homography tracking, perspective feature tracking and 3D camera solve remain outstanding.
- Displacement and particles currently use a CPU FFmpeg backend; GPU multi-pass render graph, caching and real-time preview integration remain outstanding.

### Camera preview/export increment — 19 November 2026

A shared **2.5D camera projection** runs in compositor preview and FFmpeg export. Relative layer depth, Field of View and focal length affect projected position and scale. Camera Euler rotation (X/Y/Z) is now inverted into camera space before projection, so orbit and roll alter the view consistently in preview/export; camera roll also counter-rotates the 2.5D image cards. Perspective mode applies near-plane visibility culling and caps magnification at 20× to avoid unstable giant layers. Orthographic mode also respects camera orientation but does not depth-scale. This remains a 2.5D card renderer: mesh geometry, true per-vertex perspective, materials, light interaction, shadow maps and depth-of-field blur are not implemented. The Depth of Field UI control remains visibly marked as pending.

### Tracking geometry foundation — 19 November 2026

A pure-Dart **normalized planar homography solver** now estimates a 3×3 projective transform from four or more matched point pairs, includes deterministic RANSAC outlier rejection, transforms points/polygons, and reports mean/maximum reprojection error. The motion-tracking service exposes the estimator for a future feature-matching provider. The existing FFmpeg tracker still supplies translation-only template matches; automatic planar feature detection, per-frame homography capture/application, perspective preview/export warp and 3D camera solve remain outstanding.

### Mask rotoscoping increment — 19 November 2026

Polygon and cubic Bezier masks now support keyframes for every vertex anchor and in/out tangent component. The Mask panel exposes per-component keyframe controls and a **Keyframe Full Mask** action that captures all points/handles at the current playhead. These tracks appear in the unified animation graph and timeline markers; FFmpeg export evaluates the vertex/tangent interpolation per output frame and builds the path from the animated cubic controls. The canvas preview now clips to the animated polygon/Bezier geometry and combines masks with add/subtract/intersect/difference operations. Preview clipping is hard-edged: feather, expansion and per-mask alpha are still rendered by the FFmpeg export path but are not yet pixel-matched in the live preview. Automatic subject segmentation, motion-assisted path propagation and professional roto brush/edge refinement remain outstanding.

### VFX automation and blend catalog increment — 19 November 2026

- **Glow / Drop Shadow automation:** Glow threshold, intensity and radius; Drop Shadow opacity, blur and offset now compile from keyframe tracks. Animated blur radius is rendered through fixed-radius FFmpeg blur branches blended over frame time, keeping the export CPU-compatible. Static effects retain a single-blur path.
- **Blend catalog:** the model now exposes 40 blend modes and uses a central exhaustive mapping to FFmpeg's blend filter names. Mapping tests cover each enum value. Advanced blend modes are export-backed; the canvas preview still uses normal source-over compositing and displays a warning for non-normal layer modes. Preview/export pixel parity remains outstanding.


### Camera orientation and clipping increment — 19 November 2026

- Camera X/Y/Z Euler rotation now transforms world-space layer offsets into camera-space coordinates in the shared preview/export projection.
- Camera roll counter-rotates the camera-facing 2.5D cards. The Camera panel exposes Orbit X, Orbit Y and Roll Z controls using the existing animated transform tracks, so the camera move can be keyframed.
- Perspective mode clips layers that cross behind the near plane and limits maximum projection magnification to 20×. The FFmpeg path applies the same visibility expression through layer opacity.
- Regression coverage checks yaw, roll, near-plane culling and generated FFmpeg expressions.
- **Still not true 3D:** 2.5D layers are still flat, camera-facing cards. There is no GLB/OBJ mesh rasterizer, mesh material/normal pipeline, real light/shadow rendering or depth-of-field blur. No claim of full 3D scene rendering is made.
