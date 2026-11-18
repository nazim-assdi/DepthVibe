# DepthVibe delivery roadmap

Status labels refer to implemented code in the repository. CI compile status and physical-device verification are recorded separately.

## Stage 0 — Android foundation
- [x] Native Android shell and Compose UI
- [x] Video import and Media3 playback
- [x] Easy / Pro entry points and a virtual 3D camera viewport
- [x] GitHub Actions debug build and artifact upload

## Stage 1 — Video Studio / timeline
- [x] Main video import and trim in/out export
- [x] Sequential additional video clip export
- [x] Separate looping background audio sequence in export
- [x] Rotation, constant speed, fit/crop output ratio
- [x] Static title burn-in
- [x] Brightness and grayscale effects in preview/export
- [x] Export to Movies/DepthVibe and share
- [x] Import image source reference
- [ ] Image/sticker overlay compositing and independent audio mixing/ducking
- [ ] Actual split-to-independent-clips, clip reorder and ripple editing
- [ ] Overlapping video layers, transitions and cross-fades
- [ ] LUT import, colour wheels, curves and masks
- [ ] Persistent projects, undo/redo and crash recovery

## Stage 2 — AI Depth / 2.5D
- [x] MiDaS Small model download path
- [x] LiteRT GPU inference with CPU fallback path
- [x] Depth map visualization and depth-displaced 2.5D mesh preview
- [ ] Validate model tensor layout/preprocessing and model inference on physical devices
- [ ] Temporal depth smoothing and foreground segmentation
- [ ] Disocclusion fill and edge-aware refinement
- [ ] Depth parallax output integrated into the video compositor

## Stage 3 — Camera tracking
- [x] ARCore live camera view and plane tracking integration
- [x] Anchored 3D marker placement on detected surfaces
- [x] OpenCV ORB + essential-matrix relative camera motion solver for recorded clips
- [ ] Verify AR session/anchor stability on certified ARCore phones
- [ ] Offline lens calibration, loop closure, global bundle adjustment and scale constraints
- [ ] Track confidence, manual correction and export-linked tracking data

## Stage 4 — 3D assets and VFX
- [x] Filament GLB/glTF model-loading path
- [x] Static OBJ geometry loader and viewport
- [x] Filament key light intensity control and sun-shadow renderer
- [x] CPU physics particle simulation and OpenGL particle preview
- [ ] OBJ/MTL maps and textures; more model validation
- [ ] Environment HDR/IBL relighting and reflection probes
- [ ] Mesh-fragment shatter, collisions and particle render-to-video
- [ ] 3D text, models and shadows composed over tracked footage
- [ ] Shared render graph for real-time preview and final export

## Stage 5 — Pro animation / finishing
- [x] Typed node graph data model and starter graph UI
- [x] Editable graph connections
- [x] Keyframe interpolation and curve preview
- [ ] Drag-wire node editor, node ports, graph validation and execution
- [ ] Keyframes bound to actual 3D transforms/camera and export renderer
- [ ] Graph editor handles, easing controls and motion paths
- [ ] LUT, colour grading, masks, titles and transitions in the final render graph

## Quality gate
Every advanced capability requires:
1. Successful automated build and unit tests.
2. Functional testing on physical devices covering ARCore/GPU support and memory limits.
3. A test export showing the effect is actually baked into the video.
4. Clear fallback/error messaging on unsupported devices.

A screen, contract or preview-only effect is not considered a completed export feature.
