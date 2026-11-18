# DepthVibe architecture

## Product boundary

The first delivery target is Android. The editor shell is native Kotlin + Jetpack Compose; video playback uses AndroidX Media3. Processing engines remain separate interfaces so the UI never pretends a feature is operational before a real backend exists.

## Processing pipeline

1. **Ingest:** import source media through the Storage Access Framework; retain a content URI and create lightweight proxy metadata.
2. **Decode:** decode video frames off the UI thread. Keep original media untouched.
3. **Depth:** run a mobile monocular-depth model on sampled frames, then add temporal smoothing and edge-aware refinement. A depth map estimates relative distance; it does not recover hidden geometry or turn a single 2D recording into a fully modelled object.
4. **Scene:** build a layered 2.5D scene (foreground, midground, background) with mesh displacement and disocclusion-fill passes. Offer bounded camera motion to avoid exposing unseen regions.
5. **Tracking:** use ARCore pose tracking for a live camera session on supported devices. Imported footage needs its own visual feature tracking / SLAM or structure-from-motion solve; live phone sensor poses cannot directly track an old recording.
6. **Compositing:** combine footage, depth layers, tracked transforms, 3D assets, lights, shadows and effects into a render graph.
7. **Export:** render in background chunks, encode through Android media codecs, and expose progress / cancellation / recoverable errors.

## Engine boundaries

- `DepthEstimationEngine`: frame-to-depth inference.
- `CameraTrackingEngine`: live session pose and offline-video solve are explicitly separate calls.
- `ParticleSimulationEngine`: deterministic simulation step for preview and render.
- `ModelAssetLoader`: normalizes imported asset metadata before GPU upload.

The interfaces are contracts only. They do not ship a model, ARCore session, GPU simulation, GLB renderer, or export encoder yet.

## Rendering choices

- **Depth preview:** start with a grayscale depth texture and edge overlay.
- **2.5D scene:** use a subdivided plane / layered cards and conservative camera displacement.
- **3D assets:** integrate a maintained physically based renderer (Filament is the preferred candidate) after validating Android ABI, native packaging, and memory costs.
- **Particles:** use GPU instancing for large particle counts; keep deterministic CPU-side emitters and simulation parameters for repeatable exports.
- **Timeline:** use a single project timebase and immutable clip/effect state. Preview and export must consume the same render graph.

## Performance and reliability

- Decode / inference / rendering must never run on the main thread.
- Provide draft preview resolution (for example, 540p or 720p) and full-resolution export separately.
- Use bounded frame queues and release decoded buffers promptly.
- Cache depth maps and proxy frames on disk with size limits.
- Detect low-memory conditions and reduce preview resolution / particle count.
- Keep original source files read-only and make project saves atomic.
- Add device capability checks before enabling AR or GPU features.

## Important limitations

- Monocular depth is an estimate, not measured LiDAR depth.
- Moving the virtual camera in a 2D clip can expose missing pixels; inpainting can reduce but cannot eliminate this.
- ARCore tracking depends on a supported device and suitable visual conditions.
- OBJ may reference external MTL and texture files; robust import must resolve those dependencies.
- Realistic relighting requires plausible normals / materials and environment-light estimation. A depth map alone is not enough.
