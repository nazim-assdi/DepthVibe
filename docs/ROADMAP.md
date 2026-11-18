# DepthVibe delivery roadmap

Status labels refer to code present in this repository, not product aspirations.

## Stage 0 — Android foundation

- [x] Native Android app shell and dark editor theme
- [x] Easy / Pro starter workspaces
- [x] Android document-picker video import
- [x] Media3 ExoPlayer preview
- [x] GitHub Actions debug build and APK artifact

## Stage 1 — video studio and virtual 3D camera (current)

- [x] Import a video source
- [x] Capture a source clip using the device's camera app
- [x] Read source duration and set trim in/out points
- [x] Export the selected trim range to MP4 with Media3 Transformer
- [x] Export rotation and source-audio removal
- [x] Save export to Movies/DepthVibe and share it
- [x] Preview playback-speed adjustment and mute
- [x] Preview canvas presets for 16:9, 9:16, 1:1 and 4:5
- [x] Preview-only title overlay
- [x] Import audio and image references into the editor
- [x] Add visual split markers to the timeline
- [x] OpenGL ES perspective camera viewport with orbit, dolly and FOV control
- [ ] Actual split editing with independently selectable timeline segments
- [ ] Persistent projects, undo/redo and clip reorder
- [ ] Multi-clip assembly and independent audio/image compositing in export
- [x] Burn-in one static title layer in the export
- [ ] Animated captions, text animation, filters and transitions in export
- [x] Exported aspect-ratio fit/crop and constant speed control
- [ ] Multi-track audio mixing

## Stage 2 — AI depth and 2.5D scene

- [ ] Select and benchmark a commercially usable mobile monocular-depth model
- [ ] On-device inference with GPU / NNAPI fallback and CPU-safe mode
- [ ] Temporal depth smoothing and depth-map visualisation
- [ ] Foreground masks, mesh displacement and disocclusion fill
- [ ] Interactive virtual camera motion through the estimated depth scene

## Stage 3 — camera tracking and AR

- [ ] ARCore session for supported Android devices
- [ ] Tracked 3D object and text placement in live camera footage
- [ ] Separate offline camera solve for imported video
- [ ] Track quality diagnostics and manual correction

## Stage 4 — 3D and visual effects

- [ ] GLB / glTF renderer
- [ ] OBJ + MTL + texture import
- [ ] PBR materials, environment lighting and shadows
- [ ] GPU particles, gravity, collisions and shatter
- [ ] 3D animation and camera keyframes

## Stage 5 — pro finishing

- [ ] Typed node graph and shared preview/export render graph
- [ ] Curve editor, keyframe interpolation and masks
- [ ] Multi-track audio mixing, ducking and audio effects
- [ ] Proxy media, background render queue and crash recovery
- [ ] Export presets, device capability checks and physical-device testing
- [ ] Privacy and Play release validation

## Product principle

Keep editing responsive on ordinary phones. Decode, infer and render off the UI thread, bound frame queues, use proxy previews and adapt quality to device capability. A button, preview overlay or interface placeholder does not count as a completed render feature.
