# DepthVibe architecture

## Platforms and build
The current target is Android. Kotlin 2.4.0, AGP 8.11.1, Gradle 8.13 and API 36 are used. Jetpack Compose provides the editor UI. Media3 ExoPlayer provides source playback; Media3 Transformer creates export compositions.

## Video composition
The current export composition supports:
- A sequential list of video items (first video is clipped to its selected in/out range).
- Per-item constant speed and video effects, including rotation, presentation fit/crop, brightness, grayscale and static title overlay.
- Optional separate audio-only sequence which loops through the video composition.
- Publishing the rendered MP4 into Movies/DepthVibe.

The current export is not yet a full nonlinear editor render graph. Split markers do not generate sub-clips. There is no independent overlapping video track, audio mixing/ducking, image/text sticker overlay sequence, LUT pipeline or cross-fade transition. Preview and export parity must be tested.

## AI depth
MiDaS Small is downloaded on first use instead of bundled inside the APK. LiteRT CompiledModel runs 256×256 normalized RGB inference using GPU first and CPU fallback. The output is normalized to a relative grayscale depth map. A separate OpenGL ES parallax view builds a subdivided image mesh and displaces vertices by depth.

Relative monocular depth is not metric distance or complete geometry. The first single-frame parallax preview cannot fill unseen back surfaces. Temporal consistency, segmentation and disocclusion fill remain future work. The model runtime must be warmed, reused and closed with screen lifecycle for production performance.

## Live AR camera
ARCore owns the live phone camera session, camera background texture, pose updates, horizontal/vertical plane detection and anchor lifecycle. The current demo places wireframe marker cubes on detected planes. It requires camera permission, Google Play Services for AR and an ARCore-capable device. This is separate from solving motion in an already-recorded video.

## Recorded-video motion solve
OpenCV samples frames from an imported recording, detects ORB features, matches descriptors, estimates an essential matrix and calls recoverPose to produce relative monocular camera motion. Absolute scale is unknown. There is no loop closure, global bundle adjustment, distortion calibration, manual track correction or robust reconstruction mesh yet. This is a first-pass visual-odometry solver, not production-grade full SLAM.

## 3D assets and lighting
Filament glTF viewer loads GLB, frames the object and exposes key-light intensity. Filament's physically based material renderer and shadow-capable direct light provide the base for real-time model preview. Environment HDR/IBL, reflection probes, custom shadow controls and camera-matched relighting still need integration.

Static OBJ support parses positions, normals and polygon faces, triangulates faces and renders the geometry in a simple lit OpenGL ES viewport. It records material names but does not yet parse MTL texture maps or animation rigs.

## Physics / particles
A deterministic bounded CPU simulation produces fire, smoke and shatter-style particles with velocity, gravity, lifetime and simple floor bounce. OpenGL ES renders them as point sprites for preview. It is not a mesh-fragment rigid-body shatter engine, and particle output is not yet inserted into final video export.

## Pro graph and keyframes
The current Pro Lab contains typed node definitions, graph connections, a starter graph, float animation tracks, HOLD/LINEAR/EASE_IN_OUT interpolation and a curve preview. It is not yet a fully draggable node canvas with live render evaluation. Keyframes are not yet bound to exported scene transforms or camera motion.

## Performance and safety
- Run decoding, inference and rendering off the main thread.
- Use model/proxy caches with size limits and release native buffers.
- Adapt mesh resolution and particle counts to GPU/RAM capability.
- Keep original source media read-only; use temporary files for export.
- Check camera/GPU/ARCore capability before exposing advanced tools.
- Physical-device profiling and export validation are required before Play release.
