import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/composition_models.dart';
import 'obj_mesh_loader.dart';
import 'parent_transform_resolver.dart';
import 'software_3d_renderer.dart';

/// Stateful, z-buffered CPU preview widget. Resolution is capped for responsive
/// editing on integrated GPUs and low-memory systems.
class Software3dMeshView extends StatefulWidget {
  const Software3dMeshView({
    super.key,
    required this.mesh,
    required this.modelTransform,
    required this.cameraTransform,
    required this.cameraSettings,
    required this.lights,
    required this.compositionWidth,
    required this.compositionHeight,
    this.maximumPreviewDimension = 640,
  });

  final ObjMesh mesh;
  final ResolvedLayerTransform modelTransform;
  final ResolvedLayerTransform cameraTransform;
  final CameraSettings cameraSettings;
  final List<SceneLight> lights;
  final double compositionWidth;
  final double compositionHeight;
  final int maximumPreviewDimension;

  @override
  State<Software3dMeshView> createState() => _Software3dMeshViewState();
}

class _Software3dMeshViewState extends State<Software3dMeshView> {
  ui.Image? _image;
  Object? _error;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(covariant Software3dMeshView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mesh != widget.mesh ||
        oldWidget.modelTransform != widget.modelTransform ||
        oldWidget.cameraTransform != widget.cameraTransform ||
        oldWidget.cameraSettings != widget.cameraSettings ||
        oldWidget.lights != widget.lights ||
        oldWidget.compositionWidth != widget.compositionWidth ||
        oldWidget.compositionHeight != widget.compositionHeight) {
      _render();
    }
  }

  Future<void> _render() async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      await Future<void>.delayed(Duration.zero);
      final longest = math.max(
        widget.compositionWidth,
        widget.compositionHeight,
      );
      final scale = math.min(
        1.0,
        widget.maximumPreviewDimension / math.max(1.0, longest),
      ).toDouble();
      final width = math.max(1, (widget.compositionWidth * scale).round()).toInt();
      final height = math.max(1, (widget.compositionHeight * scale).round()).toInt();
      final frame = const Software3dRenderer().rasterizeFrame(
        mesh: widget.mesh,
        width: width,
        height: height,
        compositionWidth: widget.compositionWidth,
        compositionHeight: widget.compositionHeight,
        modelTransform: widget.modelTransform,
        cameraTransform: widget.cameraTransform,
        cameraSettings: widget.cameraSettings,
        lights: widget.lights,
        centerOnModel: true,
      );
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        frame.rgba,
        width,
        height,
        ui.PixelFormat.rgba8888,
        completer.complete,
        rowBytes: width * 4,
      );
      final image = await completer.future;
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }
      final previous = _image;
      setState(() {
        _image = image;
        _loading = false;
        _error = null;
      });
      previous?.dispose();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_image != null) {
      return RawImage(image: _image, fit: BoxFit.fill, filterQuality: FilterQuality.low);
    }
    if (_error != null) {
      return const Center(
        child: Icon(Icons.broken_image_outlined, color: Color(0xFFFF8E8E), size: 38),
      );
    }
    return Center(
      child: _loading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.view_in_ar),
    );
  }
}
