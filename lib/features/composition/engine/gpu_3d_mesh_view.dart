import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:nitro_webgpu/nitro_webgpu.dart';

import '../domain/composition_models.dart';
import 'obj_mesh_loader.dart';
import 'parent_transform_resolver.dart';
import 'software_3d_mesh_view.dart';
import 'software_3d_renderer.dart';
import 'gpu_3d_mesh_packer.dart';
import 'gpu_3d_mesh_renderer.dart';

/// GPU-backed mesh viewport with a transparent CPU fallback.
///
/// The adapter is detected at runtime. If WebGPU or the presentation surface
/// is unavailable, the software preview remains usable instead of failing the
/// entire composition workspace.
class Gpu3dMeshView extends StatefulWidget {
  const Gpu3dMeshView({
    super.key,
    required this.mesh,
    required this.modelTransform,
    required this.cameraTransform,
    required this.cameraSettings,
    required this.lights,
    required this.compositionWidth,
    required this.compositionHeight,
    this.timeMs = 0,
    this.animationIndex = 0,
    this.baseWidth = 760,
    this.baseHeight = 760,
  });

  final ObjMesh mesh;
  final ResolvedLayerTransform modelTransform;
  final ResolvedLayerTransform cameraTransform;
  final CameraSettings cameraSettings;
  final List<SceneLight> lights;
  final double compositionWidth;
  final double compositionHeight;
  final int timeMs;
  final int animationIndex;
  final double baseWidth;
  final double baseHeight;

  @override
  State<Gpu3dMeshView> createState() => _Gpu3dMeshViewState();
}

class _Gpu3dMeshViewState extends State<Gpu3dMeshView> {
  static Future<_GpuBoot>? _sharedBoot;

  final _renderer = Gpu3dMeshRenderer();
  final _viewController = WebGpuViewController();
  late Future<_GpuBoot> _boot;
  GpuMeshVertexData _vertexData = GpuMeshVertexData.empty;
  bool _needsFrame = true;

  @override
  void initState() {
    super.initState();
    _boot = _sharedBoot ??= _bootGpu();
    _rebuildVertexData();
  }

  @override
  void didUpdateWidget(covariant Gpu3dMeshView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rebuildVertexData();
    _needsFrame = true;
    _viewController.resume();
  }

  Future<_GpuBoot> _bootGpu() async {
    final adapter = await Gpu.requestAdapter(
      powerPreference: GpuPowerPreference.highPerformance,
    );
    try {
      final info = adapter.info;
      final device = await adapter.requestDevice(
        label: 'DepthVibe shared GPU mesh device',
        requireTimestampQueries: adapter.supportsTimestampQueries,
      );
      return _GpuBoot(
        device: device,
        backend: adapter.backendType.name,
        adapter: info.device.isEmpty ? info.description : info.device,
        adapterType: adapter.adapterType.name,
      );
    } finally {
      adapter.dispose();
    }
  }

  void _rebuildVertexData() {
    final viewport = Size(widget.baseWidth, widget.baseHeight);
    final triangles = const Software3dRenderer().projectTriangles(
      mesh: widget.mesh,
      viewport: viewport,
      baseWidth: widget.baseWidth,
      compositionWidth: widget.compositionWidth,
      compositionHeight: widget.compositionHeight,
      modelTransform: widget.modelTransform,
      cameraTransform: widget.cameraTransform,
      cameraSettings: widget.cameraSettings,
      lights: widget.lights,
      centerOnModel: true,
      timeMs: widget.timeMs,
      animationIndex: widget.animationIndex,
    );
    _vertexData = const GpuMeshVertexPacker().pack(
      triangles: triangles,
      viewport: viewport,
      cameraSettings: widget.cameraSettings,
    );
  }

  Widget _cpuFallback(String reason) => Stack(
        children: [
          Positioned.fill(
            child: Software3dMeshView(
              mesh: widget.mesh,
              modelTransform: widget.modelTransform,
              cameraTransform: widget.cameraTransform,
              cameraSettings: widget.cameraSettings,
              lights: widget.lights,
              compositionWidth: widget.compositionWidth,
              compositionHeight: widget.compositionHeight,
              timeMs: widget.timeMs,
              animationIndex: widget.animationIndex,
            ),
          ),
          Positioned(
            left: 6,
            bottom: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xD9000000),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                child: Text(
                  'CPU fallback · $reason',
                  style: const TextStyle(
                    color: Color(0xFFFFD68A),
                    fontSize: 9,
                  ),
                ),
              ),
            ),
          ),
        ],
      );

  @override
  void dispose() {
    _renderer.dispose();
    // The logical device is shared by all 3D views for this app session.
    // Each view owns and releases only its pipelines, buffers and textures.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The current WGSL mesh pass has no sampled depth-buffer post-process.
    // Route DOF-enabled frames through the CPU thin-lens CoC pipeline until
    // the GPU post-process pass is integrated.
    if (widget.cameraSettings.depthOfField) {
      return _cpuFallback('CPU thin-lens depth of field');
    }
    final meshUsesBaseColorTextures = widget.mesh.materials.values.any(
      (material) => material.baseColorTextureBytes != null,
    );
    final meshUsesUnsupportedAlphaMode = widget.mesh.materials.values.any(
      (material) => material.alphaMode != 'OPAQUE',
    );
    if ((meshUsesBaseColorTextures || meshUsesUnsupportedAlphaMode) &&
        !_vertexData.canRenderGpuMaterialData) {
      return _cpuFallback('multiple glTF base-colour textures');
    }
    if (meshUsesBaseColorTextures &&
        !_vertexData.hasBaseColorTexture) {
      return _cpuFallback('unavailable glTF base-colour pixels');
    }
    return FutureBuilder<_GpuBoot>(
      future: _boot,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _cpuFallback('WebGPU unavailable: ${snapshot.error}');
        }
        final boot = snapshot.data;
        if (boot == null) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final bytes = _vertexData.bytes;
        final vertexCount = _vertexData.vertexCount;
        return Stack(
          fit: StackFit.expand,
          children: [
            WebGpuView(
              device: boot.device,
              renderScale: boot.adapterType == 'integratedGpu' ? 0.75 : 1.0,
              controller: _viewController,
              onFrame: (target, elapsed) async {
                await _renderer.render(
                  device: boot.device,
                  target: target,
                  vertices: bytes,
                  vertexCount: vertexCount,
                  baseColorTextureRgba: _vertexData.baseColorTextureRgba,
                  baseColorTextureWidth: _vertexData.baseColorTextureWidth,
                  baseColorTextureHeight: _vertexData.baseColorTextureHeight,
                );
                if (_needsFrame) {
                  _needsFrame = false;
                  _viewController.pause();
                }
              },
              errorBuilder: (context, message) => _cpuFallback(message),
            ),
            Positioned(
              right: 6,
              top: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xD9000000),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  child: Text(
                    '${boot.backend.toUpperCase()} · ${boot.adapterType.toUpperCase()} · ${boot.adapter}',
                    style: const TextStyle(
                      color: Color(0xFF9DE1D3),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GpuBoot {
  const _GpuBoot({
    required this.device,
    required this.backend,
    required this.adapter,
    required this.adapterType,
  });

  final GpuDevice device;
  final String backend;
  final String adapter;
  final String adapterType;
}
