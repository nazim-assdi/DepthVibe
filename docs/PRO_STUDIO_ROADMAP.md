### GLB / glTF scene import and rendering

- Implemented: active-scene traversal, nested node transforms, POSITION / NORMAL / TEXCOORD_0, decoded base-colour, metallic-roughness, normal, occlusion and emissive image payloads, metallic/roughness factors, alpha MASK / BLEND metadata, and timeline-selected translation / rotation / scale clips.
- CPU preview and frame export sample the base-colour map with perspective-correct UVs, repeat + bilinear sampling, and KHR_texture_transform when it targets UV0. The other four maps and their UV/strength metadata are decoded and retained, but are not yet applied to CPU shading.
- Remaining: GPU texture/sampler bindings, CPU/GPU metallic-roughness BRDF, normal/occlusion/emissive map shading, non-zero UV set import, glTF sampler wrap/filter modes, skinning / inverse bind matrices, morph-target deformation and complete PBR parity.

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

## Implemented camera and OBJ mesh preview increment (2026-11-19)

- Imported Wavefront OBJ geometry with polygon triangulation, negative vertex indices and basic MTL diffuse colour/opacity parsing.
- Added a CPU triangle preview renderer with model transforms, active-camera perspective/orthographic projection, near/far clipping, depth sorting and ambient/directional/point/spot-light shading.
- Added camera near/far clip controls and shared depth visibility rules for card preview and FFmpeg camera expressions.
- Current scope is OBJ geometry and diffuse MTL values only. Texture maps, GLB/GLTF, physically correct shadow maps, depth-of-field blur and 3D mesh export are not implemented in this increment. The export validator continues to report 3D model layers as unsupported rather than silently rendering a placeholder.

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


### CPU 3D mesh pipeline increment — 19 November 2026

- **Per-pixel depth buffer:** mesh preview and frame rasterization now use a CPU Z-buffer rather than relying on triangle painter order. The legacy painter remains available as a low-level projected-triangle drawing helper; the workspace preview uses the raster output.
- **GLB / glTF geometry import:** Add Layer accepts `.glb`, `.gltf` and `.obj`. The glTF importer reads GLB v2 JSON/BIN chunks and local/data-URI buffers, triangle primitives, POSITION accessors, unsigned indices and PBR base-colour factors.
- **3D frame export:** the composition exporter rasterizes each 3D model layer frame to transparent RGBA PNG, encodes a temporary alpha-capable QTRLE MOV sequence, then feeds it to the regular FFmpeg composition path. Animated model/camera transforms and light transforms are sampled at each output frame.
- **Depth of field:** CPU raster output has a bounded depth-aware blur pass driven by focus distance and aperture.
- **Shadow maps:** directional lights can build a low-resolution CPU depth shadow map; softness controls neighbourhood filtering. This is not a GPU shadow pipeline and point/spot shadow maps are not yet supported.
- **Area lights:** area sources use four spatial samples with an area-size control; this is a compact CPU approximation, not physically based area-light integration.

### Explicit limits after this increment

- **GPU renderer remains unimplemented.** There is no Vulkan, Metal, OpenGL or WebGPU backend yet. Preview and 3D frame export use CPU rasterization and are expected to be slower on larger meshes or compositions.
- glTF import is geometry-only for triangle primitives with FLOAT VEC3 POSITION and supported index types. Node hierarchy/transforms, normals, UVs, skins, morphs, animations, sparse accessors, embedded/external texture images and full metallic-roughness lighting are not yet implemented. PBR `baseColorFactor` is read as a flat material colour only.
- The Z-buffer now uses reciprocal camera-depth interpolation for perspective projection and linear camera depth for orthographic projection. Polygon clipping against near/far planes, perspective-correct interpolation of non-depth attributes, back-face culling and multisample anti-aliasing remain future work.
- Shadow mapping is directional-only and uses a compact CPU depth map; point/spot/cubemap shadows, cascades, physically soft penumbrae and shadow catcher are still outstanding.
- The DOF pass is a bounded screen-space blur approximation, not a physically based circle-of-confusion/lens model. Area lighting is four-point sampling.
- The transparent per-frame intermediate export is wired but still needs real-device performance/long-duration stress tests and full CI validation. No release APK or desktop package is implied by the source commit.


### WebGPU 3D rasterization milestone — 19 November 2026

- **Native GPU backend:** DepthVibe now uses `nitro_webgpu` for real WebGPU adapters and WGSL render passes. Runtime adapter discovery reports the actual backend and falls back to the CPU preview when no adapter or presentation surface is available.
- **GPU depth and rasterization:** triangle streams are uploaded to a hardware vertex buffer; WebGPU performs triangle rasterization, depth testing and 4× MSAA where supported (single-sample GPU fallback otherwise). The 3D view pauses its render loop between document updates to avoid idle GPU work.
- **Near/far polygon clipping:** the shared mesh projector clips triangles against camera near and far planes with polygon splitting and fan triangulation. CPU preview and the GPU vertex stream receive the same clipped triangles.
- **Current hybrid boundary:** model parenting, camera projection and flat scene-light shading are still evaluated on the CPU before vertices are uploaded. The current WGSL shader passes projected vertex colour; GPU-side model transforms, per-pixel PBR/normal mapping, textures and GPU shadow passes are not yet wired.
- **Platform presentation caveats:** the WebGPU package can use Vulkan, Metal, D3D12 and GL adapters where available. Some targets use CPU readback/upload for Flutter texture presentation, and Web builds do not currently have a browser WebGPU presenter. Hardware availability and driver features are checked at runtime.
- **Remaining 3D scope:** extend glTF attributes (UVs/normals/tangents), images/samplers and node transforms; skinned/morph animation; GPU PBR; directional plus point/spot shadows; physically based depth of field; more robust multisampling and mobile performance stress tests. The existing CPU directional shadow/DOF approximations remain fallbacks, not full GPU effects.


### glTF scene data and animation evaluation increment — 19 November 2026

- Replaced the active GLB/GLTF import route with the `gltfx` glTF 2.0 parser. GLB and JSON glTF now resolve embedded and external buffers/images through the parser.
- Imports the default scene graph, parent/child node links, node matrix or TRS transforms, triangle/strip/fan primitives, POSITION, NORMAL, TEXCOORD_0, indices, PBR base-colour factor, metallic/roughness factors, alpha mode and base-colour image bytes.
- The renderer evaluates node translation/rotation/scale animation channels at the layer-local playhead time, including STEP, LINEAR (quaternion slerp) and CUBICSPLINE interpolation. The same evaluated pose feeds CPU preview, GPU vertex upload and 3D frame export.
- Smooth vertex normals are retained and used for the preview lighting normal; node and model transforms apply inverse-transpose normal handling.

### Current GLTF / GPU rendering limits

- All five core glTF texture slots (base colour, metallic-roughness, normal, occlusion and emissive) are now decoded into reusable RGBA material payloads. The CPU preview/export path samples only base colour today; KHR_texture_transform is applied for base-colour UV0. Auxiliary maps are retained for the next shading increment, not yet used in lighting.
- The WebGPU vertex-colour shader still receives CPU-projected, pre-shaded colours; no source texture is uploaded or sampled by WGSL yet. Metallic/roughness factors are retained, but per-pixel metallic-roughness BRDF, normal/occlusion/emissive map shading, non-zero UV sets, sampler state, alpha mask/blend parity and GPU light evaluation remain pending.
- Node TRS animation is evaluated for preview/export, but skeletal skinning, inverse-bind matrices, joint weights, morph targets and weights animation are not deformed/rendered yet.


### Light transport and lens pass increment — 19 November 2026

- **Directional shadows:** the orthographic light-space depth map now returns percentage-closer filtered visibility rather than a single boolean cutoff.
- **Spot shadows:** added a cone-projected perspective depth map. Scene triangles are clipped to the light frustum before rasterization; receiver samples outside the cone remain lit.
- **Point shadows:** added a six-face perspective cubemap depth map with per-face depth testing and filtered lookup. Area emitters use the point-shadow map at their source centre while sample positions provide area-light integration.
- **Bias/filtering:** depth-dependent bias reduces self-shadow acne; the Shadow Softness control selects a bounded PCF kernel. The current shadow maps are CPU-built depth maps shared by the CPU projector and the GPU vertex-colour preview (visibility is resolved before upload), not GPU-resident shadow textures.
- **Depth of field:** replaced the relative-distance blur heuristic with a thin-lens circle-of-confusion radius using object distance, focus distance, focal length, f-number/aperture, sensor width and preview pixel density. The screen-space disk gather uses premultiplied-alpha accumulation and a depth-aware rejection step to reduce edge halos. DOF-enabled mesh previews intentionally use the CPU path until the GPU post-process shader is connected.
- **Area lights:** replaced the fixed four corner points with deterministic Hammersley samples over the rotated rectangular emitter. The Area Samples control supports 1–64 samples; the Area Size control changes emitter dimensions and emitted contribution. A cosine-weighted emitter term and inverse-square distance falloff are included.

### Remaining physical-rendering limits

- Point/spot maps are software cube/perspective maps rebuilt from the current mesh on scene updates. They are not yet GPU shadow render passes, cached across static frames, cascaded, or filtered with variance/PCSS methods.
- The thin-lens CoC is physically parameterized, but the current bounded screen-space gather is not a full lens/bokeh renderer: polygonal aperture blades, anamorphic bokeh, chromatic aberration, sensor clipping and temporal accumulation remain future work.
- Area lighting uses low-discrepancy deterministic samples and a central point-shadow map for visibility. Per-sample area-source shadow maps, multiple-scattering integration and a complete energy-conserving PBR BRDF remain outstanding.


### glTF PBR texture ingestion increment — 20 November 2026

- Added a reusable ObjTextureMap payload containing original encoded bytes, decoded RGBA pixels, dimensions, selected texture-coordinate set and KHR texture-transform parameters.
- The scene loader now resolves and decodes base-colour, metallic-roughness, normal, occlusion and emissive texture slots. Normal scale and occlusion strength are retained alongside the existing metallic/roughness and emissive factors.
- Base-colour UV0 applies KHR_texture_transform in the CPU projection path. Texture-coordinate set overrides other than UV0 are preserved as metadata but are not sampled because only TEXCOORD_0 is imported at present.
- Added loader fixture assertions for all five decoded maps, normal/AO strengths and UV transform math.
- Explicit limit: this is material ingestion plus base-colour UV transform, not complete PBR shading. Metallic-roughness, normal, occlusion and emissive maps are not yet applied to the CPU lighting equation or uploaded to the WebGPU shader. CI for this increment is pending at the time of this commit; no platform package is claimed as verified.


### WebGPU base-colour texture sampling increment — 20 November 2026

- The projected GPU vertex stream now carries UV0 plus a per-triangle texture-present flag. The WebGPU shader has a sampler and `texture_2d` binding, and the renderer uploads RGBA base-colour images with `queue.writeTexture` before sampling them in WGSL.
- Base-colour images use an sRGB GPU texture format and a repeat/linear sampler. KHR_texture_transform for UV0 is applied by the shared CPU scene projector before upload; texture repeat is performed by the GPU sampler.
- The GPU route currently accepts opaque meshes that share one decoded base-colour image. Multiple distinct images, alpha MASK/BLEND and unsupported UV sets stay on the CPU route rather than being rendered with the wrong material.
- Vertex projection, parent/node transforms and light shading are still CPU evaluated; GPU shading currently multiplies the CPU-lit colour by base-colour texture output. A metallic-roughness BRDF, normal mapping, occlusion/emissive lighting, material batching/texture arrays, sampler-specific source modes, GPU-side lights/shadows and full alpha parity remain outstanding.
- Added vertex-packer tests for UV payloads, a shared texture, multi-image fallback, alpha-mode fallback and perspective/orthographic depth indexing. CI for the final commit must still pass before this increment is release-verified.


### Primary color page increment — 20 November 2026

- Added a dedicated **Color** page to the selected-layer inspector, with four interactive Lift, Gamma, Gain and Offset wheels. The wheel emits bounded RGB channel-balance values and supports drag-to-grade plus a Reset Wheels action.
- Added Temperature/Tint, Contrast, Exposure/Brightness, Master Gamma and Saturation controls. Grade data is persisted in a regular EffectInstance, so it follows the existing project serialization and undo/redo path.
- FFmpeg export maps Lift/Gamma/Gain tonal ranges and Offset/Temperature/Tint to the documented `colorbalance` options with lightness preservation. Contrast, brightness, master gamma and saturation compile to `eq` expressions evaluated on every output frame; those scalar controls can use effect keyframes.
- Added regression coverage for tonal-wheel mapping, global offset/white-balance math and animated scalar grading expressions.
- **Explicit limits:** grading is currently applied in FFmpeg export, not in the live canvas preview. Primary wheels and white-balance adjustments are static (not keyframed). Waveform/RGB parade/vectorscope scopes, LUT import/export, custom curves, HDR/10-bit color management, shot matching and GPU color preview are still pending. This is a primary color-grading foundation, not full DaVinci Resolve parity.

### Color Studio preview, scopes and finishing increment — 20 November 2026

- **Frame-seeking live preview:** video layers now decode the source frame at the current composition playhead and paint it in the compositor. The primary Lift/Gamma/Gain/Offset, temperature/tint, contrast, brightness, master-gamma and saturation matrix is applied in the Flutter canvas. This is an interactive preview approximation, not continuous timeline playback or GPU/export pixel parity.
- **Primary wheel animation:** all RGB channels in each wheel can receive keyframes from the Color page. FFmpeg export compiles animated wheel passes through geq expressions evaluated at frame time; static wheels retain the colorbalance path.
- **Waveform and scopes:** the Color page draws a luma waveform, RGB parade and vectorscope from the current decoded video/image frame. Scope samples include the primary-wheel preview approximation, not custom curves or LUT processing. Sampling is bounded to a reduced pixel grid for UI responsiveness.
- **Curves:** added a draggable five-point editor for Master, Red, Green and Blue curves. The effect compiles to FFmpeg curves with natural interpolation. Curves are currently export-only and do not yet have preview/export parity.
- **3D LUT import:** validated 3D .cube files are copied to the app’s LUT folder and attached to the selected layer. Parsing validates 3D size 2–65, finite samples, sample count, domain ranges and a 24 MiB text limit. The Color page exposes FFmpeg’s Nearest, Trilinear, Tetrahedral, Pyramid and Prism interpolation modes.
- **HDR export profile:** added Rec.709 SDR, HDR10 PQ and HLG profile selectors. HDR modes apply a Rec.709-to-BT.2020 zscale conversion and write ProRes 422 HQ 10-bit MOV with transfer/primaries/matrix tags. This is an SDR-to-HDR mapping, not scene-referred HDR processing or native HDR source preservation; dynamic/mastering metadata and Dolby Vision are not authored.
- **Preview timeout handling:** current-frame decode is bounded to 12 seconds. On timeout, the matching active FFmpeg session is cancelled and the failed frame cache entry is removed so a later retry can run.
- **Runtime regression tests:** added FFmpeg-backed integration tests for primary grade filters, animated wheels, master/RGB curves, all five LUT interpolation modes and process timeout cancellation. CI installs the FFmpeg executable on the Linux test runner. LUT parser tests cover invalid domains and oversized input.
- **Manual smoke evidence:** FFmpeg 7.1.5 successfully processed the primary color chain, curves, five 3D-LUT interpolation modes, animated geq wheel expression, Rec.709-to-PQ 10-bit conversion and ProRes 422 HQ 10-bit output. The timeout smoke run terminated the deliberately throttled FFmpeg process.
- **Verification gate:** these are local FFmpeg smoke checks and committed integration tests. The latest GitHub Actions run must complete successfully before this increment is marked CI-verified or a platform build is described as passing.

**Remaining colour work:** continuous real-time playback grading, a shared render graph for preview/export, GPU preview, scopes including curves/LUT/HDR pipeline output, animated curves, shot matching, LUT export/library management, scene-referred HDR input/output, 10/12-bit intermediate precision, chroma/gamut monitoring and HDR mastering metadata.


## Implementation Update — Extension manager and editing reliability (20 November 2026)

- Added .dvext declarative package installation, local package registry, enable/disable and uninstall.
- Extension effect aliases use a strict allow-list of audited host renderer operations. Bundled assets are restricted to .cube LUT files under assets/.
- Extension effect IDs and parameter values are persisted in .dvproj; the same host FFmpeg compiler evaluates enabled extension effects.
- Added bounded in-memory composition Undo/Redo (80 states). Selection and playhead scrubbing do not create history entries; opening a different project resets the history.
- Extension package limits, authoring instructions and security boundaries are documented in docs/EXTENSIONS.md.

The extension manager is a data-only v1, not a general-purpose runtime for arbitrary third-party Dart, JavaScript, native code, shaders or FFmpeg command strings. New rendering algorithms still require a reviewed host renderer implementation and tests.


## Implementation Update — Marketplace, publisher trust and Adobe adapters (20 November 2026)

- Added Ed25519 publisher-key trust with SHA-256 fingerprints, explicit user trust and key revocation.
- Added signed marketplace catalog parsing, signature verification, signed package SHA-256 checks, HTTPS feeds, package metadata/version listing and release notes.
- Added CLI tools to generate publisher key pairs and sign marketplace catalogs. Private key paths are excluded from version control; the repository does not contain a publisher private key.
- Added opt-in 24-hour marketplace checks while DepthVibe is running. Automatic replacement is restricted to DepthVibe .dvext packages and uses transactional installation; Adobe packages remain user-installed through Adobe's own host workflow.
- Added a loopback-only Adobe bridge with one-time pairing codes, bearer session tokens, session disconnect, effect listing, and DepthVibe composition JSON exchange. Secure HTTPS startup is available using a user-supplied certificate/key pair for Adobe UXP on macOS.
- Added a Premiere Pro 25.6+ UXP panel, an After Effects CEP legacy panel, an After Effects Beta UXP panel source scaffold, and TypeScript SDK contracts/client.

**Important boundary:** these panels are bridge integrations. They do not yet translate arbitrary Premiere sequences or After Effects compositions/projects. Native Adobe .prm/.aex effects remain Adobe-host binaries requiring separate C++ SDK builds and host-side testing. No production marketplace catalog/server is hosted by this repository.


## Implementation Update — 21 November 2026

### Cancellable compositor export and low-spec preview controls

- Added a shared cancellation token across CPU 3D frame generation, intermediate FFmpeg encoding and final composition encoding. Cancellation before an FFmpeg session handle is returned is remembered and applied immediately when the session attaches.
- Cancelled renders raise a typed cancellation result, remove incomplete output and clean temporary mesh/text render folders. Closing the workspace requests cancellation rather than leaving a render running without its owner.
- The compositor progress indicator now allocates 0–20% to 3D frame preparation and 20–100% to final encoding, and exposes percentage plus Cancel/Stopping controls.
- Added persisted Compatibility (320 px / 0.55 scale), Balanced (480 px / 0.75) and Quality (640 px / 1.0) preview modes. CPU fallback resolution and GPU presentation scale read the selected setting. Final composition dimensions are unchanged.
- Added regression tests for cancellation lifecycle and monotonic preview workload presets.

**Scope boundary:** this is active-render cancellation and progress, not yet a persistent multi-job Render Queue. Job scheduling, durable per-job logs, recovery/resume and retry controls remain open. Low-end CPU/GPU performance still requires physical-device measurement.
