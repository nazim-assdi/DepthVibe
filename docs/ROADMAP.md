# DepthVibe delivery roadmap

Status labels describe code actually present in this repository.

## Stage 0 — foundation (current)

- [x] Native Android app shell and dark editor theme
- [x] Easy / Pro workspace switch
- [x] Video picker and Media3 preview
- [x] Starter timeline and node-workspace presentation
- [x] Engine contracts and architecture notes
- [x] GitHub Actions debug-build workflow
- [ ] Persistent project serialization and relaunch recovery
- [ ] Functional clip trimming, split, reorder and audio controls

## Stage 1 — dependable 2D editor

- Import video / image / audio and model assets with explicit type validation
- Timeline with trim handles, snapping, tracks, keyframe data and undo/redo
- Project save / restore and proxy generation
- Preview playback synchronised with timeline
- Background render queue and a basic export pipeline

## Stage 2 — AI depth and 2.5D

- Select and benchmark a commercially usable monocular-depth model
- On-device inference with GPU / NNAPI fallback and CPU-safe mode
- Depth map visualisation and temporal smoothing
- Foreground / background masks, mesh displacement and disocclusion fill
- Camera-motion limits and performance controls for lower-memory devices

## Stage 3 — camera tracking

- ARCore live camera session and anchor placement on supported devices
- Imported-video feature detection, camera solve, bundle adjustment and solve diagnostics
- Track quality indicators, lost-track recovery and manual correction points

## Stage 4 — 3D, lighting and effects

- GLB / glTF import, then OBJ + MTL + texture support
- PBR materials, environment lighting, shadow maps and reflection probes
- 3D transform gizmos and animation keyframes
- GPU particle emitters, gravity, collisions and shatter presets

## Stage 5 — pro finishing

- Node graph with typed ports and graph validation
- Curve / graph editor and X/Y/Z keyframe interpolation
- Render graph shared by preview and export
- Audio mixing, colour controls, export presets and crash recovery
- Device matrix testing, accessibility, privacy disclosures and Play release checks

## Acceptance rule

A stage is complete only after automated tests pass and the capability is verified on physical hardware representative of the target range. A UI control, interface, placeholder, or architecture note does not count as a completed processing feature.
