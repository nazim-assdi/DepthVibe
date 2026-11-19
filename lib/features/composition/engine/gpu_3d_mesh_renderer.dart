import 'dart:typed_data';

import 'package:nitro_webgpu/nitro_webgpu.dart';

/// Hardware rasterizer for pre-projected mesh triangles.
///
/// WebGPU performs triangle rasterization, depth testing and (where supported)
/// 4x MSAA. Scene projection and flat lighting are currently evaluated by the
/// shared CPU scene evaluator before vertices are uploaded.
class Gpu3dMeshRenderer {
  static const _shader = r'''
struct VertexInput {
  @location(0) position: vec3<f32>,
  @location(1) color: vec4<f32>,
};

struct VertexOutput {
  @builtin(position) position: vec4<f32>,
  @location(0) color: vec4<f32>,
};

@vertex
fn vs_main(input: VertexInput) -> VertexOutput {
  var output: VertexOutput;
  output.position = vec4<f32>(input.position, 1.0);
  output.color = input.color;
  return output;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
  return input.color;
}
''';

  GpuShaderModule? _module;
  GpuRenderPipeline? _pipeline;
  GpuBuffer? _vertices;
  GpuTexture? _depthTexture;
  GpuTextureView? _depthView;
  GpuTexture? _msaaTexture;
  GpuTextureView? _msaaView;
  Uint8List? _uploadedBytes;
  int _vertexCount = 0;
  int _bufferSize = 0;
  int _width = 0;
  int _height = 0;
  GpuTextureFormat? _targetFormat;
  int _sampleCount = 4;
  bool _disposed = false;

  Future<void> render({
    required GpuDevice device,
    required GpuRenderTarget target,
    required Uint8List vertices,
    required int vertexCount,
  }) async {
    if (_disposed) throw StateError('GPU mesh renderer is disposed.');
    if (target.width <= 0 || target.height <= 0) return;

    await _ensurePipeline(device, target.targetFormat);
    await _ensureAttachments(device, target);
    _uploadVertices(device, vertices, vertexCount);

    final encoder = device.createCommandEncoder(label: 'DepthVibe 3D frame');
    final pass = encoder.beginRenderPass(
      colorAttachments: [
        GpuColorAttachmentInfo(
          view: _sampleCount == 4 ? _msaaView! : target.view,
          resolveTarget: _sampleCount == 4 ? target.view : null,
          loadOp: GpuLoadOp.clear,
          storeOp: GpuStoreOp.store,
          clearColor: GpuColor.transparent,
        ),
      ],
      depthAttachment: GpuDepthAttachmentInfo(
        view: _depthView!,
        loadOp: GpuLoadOp.clear,
        storeOp: GpuStoreOp.discard,
        clearValue: 1,
      ),
      label: 'DepthVibe 3D Z-buffer pass',
    );
    pass.setPipeline(_pipeline!);
    if (_vertexCount > 0 && _vertices != null) {
      pass.setVertexBuffer(0, _vertices!);
      pass.draw(_vertexCount);
    }
    pass.end();
    device.queue.submit([encoder.finish()]);
  }

  Future<void> _ensurePipeline(
    GpuDevice device,
    GpuTextureFormat targetFormat,
  ) async {
    if (_pipeline != null && _targetFormat == targetFormat) return;

    _pipeline?.dispose();
    _pipeline = null;
    _module ??= await device.createShaderModule(
      _shader,
      label: 'DepthVibe WGSL mesh shader',
    );

    const vertexLayout = [
      GpuVertexLayout(
        arrayStride: 28,
        attributes: [
          GpuVertexAttr(
            format: GpuVertexFormat.float32x3,
            offset: 0,
            shaderLocation: 0,
          ),
          GpuVertexAttr(
            format: GpuVertexFormat.float32x4,
            offset: 12,
            shaderLocation: 1,
          ),
        ],
      ),
    ];

    try {
      _pipeline = await device.createRenderPipeline(
        module: _module!,
        targetFormat: targetFormat,
        depthFormat: GpuTextureFormat.depth24Plus,
        depthWriteEnabled: true,
        depthCompare: GpuCompareFunction.less,
        blend: GpuBlendMode.alpha,
        sampleCount: 4,
        topology: GpuPrimitiveTopology.triangleList,
        cullMode: GpuCullMode.none,
        vertexBuffers: vertexLayout,
        label: 'DepthVibe WebGPU mesh pipeline (4x MSAA)',
      );
      _sampleCount = 4;
    } catch (_) {
      // Devices that do not expose a 4x sample count still get a real GPU
      // depth-tested renderer, with MSAA disabled as a capability fallback.
      _pipeline = await device.createRenderPipeline(
        module: _module!,
        targetFormat: targetFormat,
        depthFormat: GpuTextureFormat.depth24Plus,
        depthWriteEnabled: true,
        depthCompare: GpuCompareFunction.less,
        blend: GpuBlendMode.alpha,
        sampleCount: 1,
        topology: GpuPrimitiveTopology.triangleList,
        cullMode: GpuCullMode.none,
        vertexBuffers: vertexLayout,
        label: 'DepthVibe WebGPU mesh pipeline (single sample)',
      );
      _sampleCount = 1;
    }
    _targetFormat = targetFormat;
    _releaseAttachments();
  }

  Future<void> _ensureAttachments(
    GpuDevice device,
    GpuRenderTarget target,
  ) async {
    if (_width == target.width &&
        _height == target.height &&
        _depthView != null &&
        (_sampleCount == 1 || _msaaView != null)) {
      return;
    }
    _releaseAttachments();
    _width = target.width;
    _height = target.height;
    if (_sampleCount == 4) {
      try {
        _createAttachments(device, target, 4);
      } catch (_) {
        _releaseAttachments();
        _pipeline?.dispose();
        _pipeline = await device.createRenderPipeline(
          module: _module!,
          targetFormat: target.targetFormat,
          depthFormat: GpuTextureFormat.depth24Plus,
          depthWriteEnabled: true,
          depthCompare: GpuCompareFunction.less,
          blend: GpuBlendMode.alpha,
          sampleCount: 1,
          topology: GpuPrimitiveTopology.triangleList,
          cullMode: GpuCullMode.none,
          vertexBuffers: const [
            GpuVertexLayout(
              arrayStride: 28,
              attributes: [
                GpuVertexAttr(
                  format: GpuVertexFormat.float32x3,
                  offset: 0,
                  shaderLocation: 0,
                ),
                GpuVertexAttr(
                  format: GpuVertexFormat.float32x4,
                  offset: 12,
                  shaderLocation: 1,
                ),
              ],
            ),
          ],
          label: 'DepthVibe WebGPU mesh pipeline (single sample)',
        );
        _sampleCount = 1;
        _createAttachments(device, target, 1);
      }
    } else {
      _createAttachments(device, target, 1);
    }
  }

  void _createAttachments(
    GpuDevice device,
    GpuRenderTarget target,
    int sampleCount,
  ) {
    _depthTexture = device.createTexture(
      width: _width,
      height: _height,
      format: GpuTextureFormat.depth24Plus,
      usage: GpuTextureUsage.renderAttachment,
      sampleCount: sampleCount,
      label: 'DepthVibe 3D depth buffer',
    );
    _depthView = _depthTexture!.createView();
    if (sampleCount == 4) {
      _msaaTexture = device.createTexture(
        width: _width,
        height: _height,
        format: target.targetFormat,
        usage: GpuTextureUsage.renderAttachment,
        sampleCount: 4,
        label: 'DepthVibe 3D MSAA colour target',
      );
      _msaaView = _msaaTexture!.createView();
    }
  }

  void _uploadVertices(
    GpuDevice device,
    Uint8List bytes,
    int vertexCount,
  ) {
    _vertexCount = vertexCount;
    if (bytes.isEmpty || vertexCount <= 0) {
      _vertices?.dispose();
      _vertices = null;
      _uploadedBytes = bytes;
      _bufferSize = 0;
      return;
    }
    if (_vertices == null || _bufferSize != bytes.length) {
      _vertices?.dispose();
      _vertices = device.createBuffer(
        size: bytes.length,
        usage: GpuBufferUsage.vertex | GpuBufferUsage.copyDst,
        label: 'DepthVibe 3D vertex stream',
      );
      _bufferSize = bytes.length;
      _uploadedBytes = null;
    }
    if (!identical(_uploadedBytes, bytes)) {
      device.queue.writeBuffer(_vertices!, bytes);
      _uploadedBytes = bytes;
    }
  }

  void _releaseAttachments() {
    _depthView?.dispose();
    _depthView = null;
    _depthTexture?.dispose();
    _depthTexture = null;
    _msaaView?.dispose();
    _msaaView = null;
    _msaaTexture?.dispose();
    _msaaTexture = null;
    _width = 0;
    _height = 0;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _releaseAttachments();
    _vertices?.dispose();
    _vertices = null;
    _pipeline?.dispose();
    _pipeline = null;
    _module?.dispose();
    _module = null;
    _uploadedBytes = null;
  }
}
