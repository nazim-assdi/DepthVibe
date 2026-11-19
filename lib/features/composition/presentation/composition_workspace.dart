import 'dart:io';
import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../application/composition_controller.dart';
import '../data/effect_catalog.dart';
import '../data/photoshop_import_service.dart';
import '../domain/composition_models.dart';
import '../engine/parent_transform_resolver.dart';
import '../engine/camera_projection_resolver.dart';
import '../engine/composition_export_service.dart';
import '../engine/audio_waveform_service.dart';
import '../engine/motion_tracking_service.dart';
import '../engine/transition_frame_validator.dart';

class CompositionWorkspace extends StatefulWidget {
  const CompositionWorkspace({super.key});

  @override
  State<CompositionWorkspace> createState() => _CompositionWorkspaceState();
}

class _CompositionWorkspaceState extends State<CompositionWorkspace> {
  final CompositionController _controller = CompositionController();
  final PhotoshopImportService _photoshop = const PhotoshopImportService();
  final CompositionExportService _exporter = const CompositionExportService();
  final MotionTrackingService _tracker = const MotionTrackingService();
  final AudioWaveformService _waveformService = const AudioWaveformService();
  final Map<String, Future<File?>> _waveformJobs = {};

  Future<File?> _waveformFor(String path) =>
      _waveformJobs.putIfAbsent(path, () => _waveformService.generate(path));
  bool _tracking = false;
  double _trackingLeft = 100;
  double _trackingTop = 100;
  double _trackingWidth = 100;
  double _trackingHeight = 100;
  double _trackingThreshold = 0.30;
  bool _stabilizeTracking = true;
  bool _rendering = false;
  double _renderProgress = 0;
  String _panel = 'Layers';
  String _effectCategory = 'All';
  String? _notice;

  static const _layerButtons = <(LayerKind, String, IconData)>[
    (LayerKind.video, 'Video', Icons.movie_outlined),
    (LayerKind.image, 'Image', Icons.image_outlined),
    (LayerKind.shape, 'Shape', Icons.category_outlined),
    (LayerKind.text, 'Text', Icons.text_fields),
    (LayerKind.nullObject, 'Null', Icons.control_camera),
    (LayerKind.adjustment, 'Adjust', Icons.tune),
    (LayerKind.camera, 'Camera', Icons.videocam_outlined),
    (LayerKind.light, 'Light', Icons.lightbulb_outline),
    (LayerKind.threeDModel, '3D Model', Icons.view_in_ar),
    (LayerKind.audio, 'Audio', Icons.graphic_eq),
    (LayerKind.particle, 'Particles', Icons.auto_awesome),
    (LayerKind.precomposition, 'Precomp', Icons.layers_outlined),
  ];

  CompositionLayer? get _selected => _controller.selectedLayer;

  Future<void> _runMotionTracking() async {
    final layer = _selected;
    if (layer == null || layer.kind != LayerKind.video || layer.sourceUri == null) {
      setState(() => _notice = 'Select a video layer before running tracking.');
      return;
    }
    setState(() {
      _tracking = true;
      _notice = 'Extracting the tracking region and analysing the clip…';
    });
    try {
      final result = await _tracker.track(
        sourcePath: layer.sourceUri!,
        left: _trackingLeft.round(),
        top: _trackingTop.round(),
        width: _trackingWidth.round(),
        height: _trackingHeight.round(),
        threshold: _trackingThreshold,
      );
      _controller.applyMotionTrack(
        layerId: layer.id,
        samples: result.samples,
        sourceWidth: result.sourceWidth,
        sourceHeight: result.sourceHeight,
        stabilize: _stabilizeTracking,
      );
      if (!mounted) return;
      setState(() {
        _notice = 'Tracked ' + result.samples.length.toString() +
            ' samples. Position keyframes added to ' + layer.name + '.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _notice = 'Tracking failed: ' + error.toString());
    } finally {
      if (mounted) setState(() => _tracking = false);
    }
  }

  Widget _trackingField(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    return SizedBox(
      width: 112,
      child: TextFormField(
        initialValue: value.toStringAsFixed(0),
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (text) {
          final parsed = double.tryParse(text);
          if (parsed != null) onChanged(parsed);
        },
      ),
    );
  }

  Future<void> _importPhotoshop() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['psd', 'psb'],
      );
      if (picked == null) return;
      final sourcePath = picked.path;
      if (sourcePath == null) {
        setState(() => _notice = 'This provider did not expose a local PSD/PSB file path.');
        return;
      }
      setState(() => _notice = 'Reading Photoshop layer structure…');
      final document = await _photoshop.importDocument(sourcePath);
      _controller.addPhotoshopLayers(
        sourceDocumentUri: sourcePath,
        documentWidth: document.width,
        documentHeight: document.height,
        assets: document.layers,
      );
      setState(() {
        _notice =
            'Imported ${document.visibleLayerCount} Photoshop layers, '
            '${document.groupCount} groups, ${document.clippedLayerCount} clipping layers '
            'and ${document.smartObjectCount} Smart Objects from '
            '${document.width}×${document.height} document';
        _panel = 'Layers';
      });
    } catch (error) {
      setState(() => _notice = 'PSD/PSB import failed: $error');
    }
  }

  Future<void> _addLayer(LayerKind kind) async {
    if (kind == LayerKind.video ||
        kind == LayerKind.image ||
        kind == LayerKind.audio) {
      final file = await FilePicker.pickFile(
        type: switch (kind) {
          LayerKind.video => FileType.video,
          LayerKind.audio => FileType.audio,
          _ => FileType.image,
        },
      );
      if (file == null) return;
      final sourcePath = file.path;
      if (sourcePath == null) {
        setState(() => _notice = 'This provider did not expose a local media file path.');
        return;
      }
      var width = _controller.document.width;
      var height = _controller.document.height;
      if (kind == LayerKind.image) {
        final decoded = img.decodeImage(await File(sourcePath).readAsBytes());
        if (decoded != null) {
          width = decoded.width;
          height = decoded.height;
        }
      }
      _controller.addLayer(
        kind,
        name: file.name,
        sourceUri: sourcePath,
        sourceWidth: width,
        sourceHeight: height,
      );
    } else {
      _controller.addLayer(kind);
    }
    if (!mounted) return;
    setState(() {
      _panel = switch (kind) {
        LayerKind.shape => 'Shape',
        LayerKind.camera || LayerKind.light || LayerKind.threeDModel => '3D',
        LayerKind.nullObject => 'Parent',
        LayerKind.adjustment => 'Effects',
        _ => 'Layers',
      };
      _notice = '${kind.name} layer added. Animate its Transform or Effects.';
    });
  }

  Future<void> _exportComposition() async {
    if (_rendering) return;
    setState(() {
      _rendering = true;
      _renderProgress = 0;
      _notice = 'Preparing composition render…';
    });
    try {
      final result = await _exporter.export(
        _controller.document,
        onProgress: (value) {
          if (mounted) setState(() => _renderProgress = value);
        },
      );
      if (!mounted) return;
      setState(() {
        _notice = result.skippedLayerNames.isEmpty
            ? 'Rendered ${result.renderedLayerCount} layers (silent first-pass compositor): ${result.file.path}'
            : 'Rendered ${result.renderedLayerCount} layers (silent first-pass compositor). Skipped: ${result.skippedLayerNames.join(', ')}';
      });
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(result.file.path)],
          text: 'Composition rendered with DepthVibe by N Tech',
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _notice = 'Composition render failed: $error');
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  void _addKeyframe(String property) {
    _controller.addKeyframe(property);
    setState(() => _notice = 'Keyframe added at ${_time(_controller.document.playheadMs)}');
  }

  Future<void> _editBezierCurve(
    String property,
    BezierCurve initialCurve, {
    String? effectId,
    String? maskId,
    String? busId,
    int? timeMs,
  }) async {
    var draft = initialCurve;
    final result = await showDialog<BezierCurve>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('BEZIER GRAPH EDITOR'),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Drag either control handle to shape the animation easing.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF9AA8BD)),
                ),
                const SizedBox(height: 12),
                _BezierCurveEditor(
                  curve: draft,
                  onChanged: (curve) => setDialogState(() => draft = curve),
                ),
                const SizedBox(height: 8),
                Text(
                  'P1  ${draft.x1.toStringAsFixed(2)}, ${draft.y1.toStringAsFixed(2)}'
                  '     P2  ${draft.x2.toStringAsFixed(2)}, ${draft.y2.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 10, color: Color(0xFFB7C3D5)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(draft),
              child: const Text('APPLY CURVE'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (maskId != null) {
      _controller.setMaskBezierCurve(
        maskId,
        property,
        result,
        timeMs: timeMs,
      );
    } else if (busId != null) {
      _controller.setAudioBusBezierCurve(
        busId,
        property,
        result,
        timeMs: timeMs,
      );
    } else {
      _controller.setBezierCurve(
        property,
        result,
        effectId: effectId,
        timeMs: timeMs,
      );
    }
    setState(() => _notice = 'Bezier curve updated for $property');
  }

  String _time(int ms) {
    final seconds = ms ~/ 1000;
    final frames = ((ms % 1000) / 1000 * _controller.document.frameRate).floor();
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}:${frames.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final doc = _controller.document;
        final layer = _selected;
        return Scaffold(
          appBar: AppBar(
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DEPTHVIBE COMPOSITOR', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                Text('Layers • Masks • Parent • Keyframes • 3D', style: TextStyle(fontSize: 10)),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Import Photoshop PSD / PSB layers',
                onPressed: _importPhotoshop,
                icon: const Icon(Icons.photo_library_outlined),
              ),
              IconButton(
                tooltip: 'Add null parent',
                onPressed: () => _addLayer(LayerKind.nullObject),
                icon: const Icon(Icons.control_camera),
              ),
              IconButton(
                tooltip: 'Add camera',
                onPressed: () => _addLayer(LayerKind.camera),
                icon: const Icon(Icons.videocam_outlined),
              ),
              IconButton(
                tooltip: 'Add light',
                onPressed: _rendering ? null : () => _addLayer(LayerKind.light),
                icon: const Icon(Icons.lightbulb_outline),
              ),
              IconButton(
                tooltip: 'Render composition to MP4',
                onPressed: _rendering ? null : _exportComposition,
                icon: const Icon(Icons.ios_share),
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: Column(
            children: [
              _buildLayerToolbar(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 900;
                    if (compact) {
                      return Column(
                        children: [
                          Expanded(child: _buildCanvas(doc, layer)),
                          SizedBox(height: 230, child: _buildActivePanel(layer)),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        SizedBox(width: 260, child: _buildLayerPanel(doc.layers)),
                        Expanded(flex: 6, child: _buildCanvas(doc, layer)),
                        SizedBox(width: 330, child: _buildActivePanel(layer)),
                      ],
                    );
                  },
                ),
              ),
              _buildTimeline(doc.layers, doc.playheadMs, doc.durationMs),
              if (_rendering)
                LinearProgressIndicator(value: _renderProgress == 0 ? null : _renderProgress),
              if (_notice != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  color: const Color(0xFF101722),
                  child: Text(_notice!, style: const TextStyle(fontSize: 11, color: Color(0xFF9DABC2))),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLayerToolbar() {
    return SizedBox(
      height: 66,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        children: [
          for (final entry in _layerButtons)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Tooltip(
                message: 'Add ${entry.$2} layer',
                child: OutlinedButton.icon(
                  onPressed: _rendering ? null : () => _addLayer(entry.$1),
                  icon: Icon(entry.$3, size: 16),
                  label: Text(entry.$2),
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: _importPhotoshop,
            icon: const Icon(Icons.layers, size: 16),
            label: const Text('Import PSD'),
          ),
        ],
      ),
    );
  }

  Widget _buildLayerPanel(List<CompositionLayer> layers) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF101722),
        border: Border(right: BorderSide(color: Color(0xFF29354A))),
      ),
      child: Column(
        children: [
          _panelHeader('LAYER STACK', Icons.layers),
          Expanded(
            child: ListView.builder(
              itemCount: layers.length,
              itemBuilder: (context, index) {
                final layer = layers[index];
                final selected = layer.id == _controller.document.selectedLayerId;
                var depth = 0;
                var ancestorId = layer.parentId;
                while (ancestorId != null && depth <= layers.length) {
                  final parents = layers.where((item) => item.id == ancestorId);
                  if (parents.isEmpty) break;
                  ancestorId = parents.first.parentId;
                  depth++;
                }
                final metadata = <String>[
                  layer.kind == LayerKind.precomposition
                      ? 'PSD group'
                      : layer.kind.name,
                  if (layer.photoshopClipped)
                    layer.clippingBaseLayerId == null
                        ? 'clipped layer'
                        : 'clipped to base',
                  if (layer.smartObjectResourceId != null) 'Smart Object',
                  if (layer.photoshopAdjustmentKey != null)
                    'Adjustment ${layer.photoshopAdjustmentKey}',
                ];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.only(
                    left: 10 + depth * 14,
                    right: 8,
                  ),
                  selected: selected,
                  selectedTileColor: const Color(0xFF263553),
                  leading: Icon(
                    layer.kind == LayerKind.precomposition
                        ? Icons.folder_open
                        : _iconFor(layer.kind),
                    size: 17,
                  ),
                  title: Text(layer.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                  subtitle: Text(metadata.join(' · '), maxLines: 1, style: const TextStyle(fontSize: 9)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: layer.enabled ? 'Hide layer' : 'Show layer',
                        onPressed: () => _controller.setLayerEnabled(layer.id, !layer.enabled),
                        icon: Icon(layer.enabled ? Icons.visibility : Icons.visibility_off, size: 16),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: layer.locked ? 'Unlock layer' : 'Lock layer',
                        onPressed: () => _controller.setLayerLocked(layer.id, !layer.locked),
                        icon: Icon(layer.locked ? Icons.lock : Icons.lock_open, size: 16),
                      ),
                    ],
                  ),
                  onTap: () => _controller.selectLayer(layer.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(CompositionDocument doc, CompositionLayer? selected) {
    return Container(
      color: const Color(0xFF080C13),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: doc.width / doc.height,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final canvasWidth = constraints.maxWidth;
                    final canvasHeight = constraints.maxHeight;
                    final ordered = doc.layers.reversed.where((item) => item.enabled);
                    return Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: const Color(0xFF151C2A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF36445F)),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const CustomPaint(painter: _CanvasGridPainter()),
                          for (final layer in ordered)
                            _buildLayerVisual(
                              layer,
                              doc,
                              Size(canvasWidth, canvasHeight),
                            ),
                          if (selected != null)
                            Positioned(
                              right: 10,
                              top: 10,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xCC0A101C),
                                  border: Border.all(color: const Color(0xFF8293FF)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  child: Text(
                                    selected.name,
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            left: 10,
                            bottom: 10,
                            child: Text(
                              '${doc.width} × ${doc.height}  •  ${doc.frameRate.toStringAsFixed(0)} FPS',
                              style: const TextStyle(fontSize: 9, color: Color(0xFF8998AF)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _toolChip('Select', Icons.mouse, true),
              _toolChip('Hand', Icons.pan_tool_alt, false),
              _toolChip('Mask', Icons.crop_free, false, onTap: () {
                _controller.addMask();
                setState(() => _panel = 'Masks');
              }),
              _toolChip('Keyframe', Icons.key, false, onTap: () => _addKeyframe('position.x')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLayerVisual(
    CompositionLayer layer,
    CompositionDocument doc,
    Size canvasSize,
  ) {
    final timeMs = doc.playheadMs;
    final resolved = const ParentTransformResolver().resolve(
      layer: layer,
      timeMs: timeMs,
      layers: doc.layers,
    );
    if (!resolved.enabled) return const SizedBox.shrink();
    final cameraLayer = doc.layers
        .where((item) => item.kind == LayerKind.camera && item.enabled)
        .firstOrNull;
    final cameraTransform = cameraLayer == null
        ? null
        : const ParentTransformResolver().resolve(
            layer: cameraLayer,
            timeMs: timeMs,
            layers: doc.layers,
          );
    final projected = cameraLayer != null &&
            cameraTransform != null &&
            cameraTransform.enabled &&
            cameraLayer.camera != null &&
            layer.kind != LayerKind.camera &&
            layer.kind != LayerKind.light &&
            layer.kind != LayerKind.precomposition
        ? const CameraProjectionResolver().project(
            layer: resolved,
            camera: cameraTransform,
            settings: cameraLayer.camera!,
          )
        : null;
    final displayPosition = projected?.position ?? resolved.position;
    final displayScale = projected?.scale ?? resolved.scale;
    final displayRotation = projected?.rotation ?? resolved.rotation;
    final displayOpacity = projected?.opacity ?? resolved.opacity;
    final x = displayPosition.x;
    final y = displayPosition.y;
    final scaleX = displayScale.x / 100;
    final scaleY = displayScale.y / 100;
    final rotation = displayRotation.z * math.pi / 180;
    final opacity = (displayOpacity / 100).clamp(0, 1).toDouble();

    double baseWidth = 160;
    double baseHeight = 120;
    Widget visual;

    switch (layer.kind) {
      case LayerKind.photoshopLayer:
      case LayerKind.image:
        baseWidth = layer.sourceWidth > 0 ? layer.sourceWidth.toDouble() : 320;
        baseHeight = layer.sourceHeight > 0 ? layer.sourceHeight.toDouble() : 180;
        visual = layer.sourceUri == null
            ? const Icon(Icons.perm_media_outlined, color: Color(0xFFB3BEFF))
            : Image.file(
                File(layer.sourceUri!),
                fit: BoxFit.fill,
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: Color(0x553E4D6C),
                  child: Icon(Icons.broken_image_outlined),
                ),
              );
        break;
      case LayerKind.video:
        baseWidth = doc.width.toDouble();
        baseHeight = doc.height.toDouble();
        visual = const Icon(Icons.movie, color: Color(0xFFB3BEFF), size: 36);
        break;
      case LayerKind.shape:
        visual = CustomPaint(
          painter: _ShapeLayerPainter(layer.shapeStyle ?? const ShapeStyle()),
        );
        break;
      case LayerKind.text:
        baseWidth = 320;
        baseHeight = 80;
        visual = Align(
          alignment: Alignment.centerLeft,
          child: Text(
            layer.textContent ?? layer.name,
            style: TextStyle(
              color: Colors.white,
              fontSize: 26 * canvasSize.width / doc.width,
              fontWeight: FontWeight.w800,
              shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
            ),
          ),
        );
        break;
      case LayerKind.nullObject:
        visual = const Icon(Icons.control_camera, color: Color(0xFFB5A4FF), size: 30);
        break;
      case LayerKind.camera:
        visual = const Icon(Icons.videocam, color: Color(0xFF8EC5FF), size: 34);
        break;
      case LayerKind.light:
        visual = const Icon(Icons.lightbulb, color: Color(0xFFFFD78A), size: 34);
        break;
      case LayerKind.adjustment:
        visual = DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x337C8CFF),
            border: Border.all(color: const Color(0x997C8CFF)),
          ),
          child: const Center(
            child: Text('ADJUSTMENT', style: TextStyle(fontSize: 9, letterSpacing: 1)),
          ),
        );
        break;
      case LayerKind.threeDModel:
        visual = const Icon(Icons.view_in_ar, color: Color(0xFF9DE1D3), size: 36);
        break;
      case LayerKind.audio:
        visual = const Icon(Icons.graphic_eq, color: Color(0xFF9DE1D3), size: 26);
        break;
      case LayerKind.particle:
        visual = const Icon(Icons.auto_awesome, color: Color(0xFFFFC98A), size: 32);
        break;
      case LayerKind.precomposition:
        visual = const SizedBox.shrink();
        break;
    }

    final width = baseWidth * scaleX.abs() / doc.width * canvasSize.width;
    final height = baseHeight * scaleY.abs() / doc.height * canvasSize.height;
    final left = x / doc.width * canvasSize.width - width / 2;
    final top = y / doc.height * canvasSize.height - height / 2;

    return Positioned(
      left: left,
      top: top,
      width: width.clamp(1, canvasSize.width * 4).toDouble(),
      height: height.clamp(1, canvasSize.height * 4).toDouble(),
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: rotation,
          child: Transform.scale(
            scaleX: scaleX.isNegative ? -1 : 1,
            scaleY: scaleY.isNegative ? -1 : 1,
            child: visual,
          ),
        ),
      ),
    );
  }

  Widget _toolChip(String label, IconData icon, bool active, {VoidCallback? onTap}) {
    return ActionChip(
      avatar: Icon(icon, size: 14),
      label: Text(label),
      onPressed: onTap ?? () => setState(() => _notice = '$label tool selected'),
      backgroundColor: active ? const Color(0xFF394A7B) : const Color(0xFF1B2638),
    );
  }

  Widget _buildActivePanel(CompositionLayer? layer) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF101722),
        border: Border(left: BorderSide(color: Color(0xFF29354A))),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final panel in const ['Layers', 'Timing', 'Transform', 'Animation', 'Shape', 'Effects', 'Masks', 'Audio', 'Bus Mixer', 'Tracking', 'Transitions', 'Parent', '3D'])
                  TextButton(
                    onPressed: () => setState(() => _panel = panel),
                    child: Text(panel, style: TextStyle(fontSize: 10, fontWeight: _panel == panel ? FontWeight.w900 : FontWeight.normal)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF29354A)),
          Expanded(
            child: layer == null
                ? _panel == 'Bus Mixer'
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: _buildAudioBusPanel(null),
                      )
                    : const Center(child: Text('Select a layer to edit'))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: _panelContent(layer),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _panelContent(CompositionLayer layer) {
    switch (_panel) {
      case 'Timing':
        return _buildTimingPanel(layer);
      case 'Transform':
        return _buildTransformPanel(layer);
      case 'Animation':
        return _buildAnimationPanel(layer);
      case 'Shape':
        return _buildShapePanel(layer);
      case 'Effects':
        return _buildEffectsPanel(layer);
      case 'Masks':
        return _buildMasksPanel(layer);
      case 'Audio':
        return _buildAudioPanel(layer);
      case 'Bus Mixer':
        return _buildAudioBusPanel(layer);
      case 'Tracking':
        return _buildTrackingPanel(layer);
      case 'Transitions':
        return _buildTransitionsPanel(layer);
      case 'Parent':
        return _buildParentPanel(layer);
      case '3D':
        return _build3dPanel(layer);
      default:
        return _buildLayerInfo(layer);
    }
  }

  Widget _buildLayerInfo(CompositionLayer layer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('SELECTED LAYER', _iconFor(layer.kind)),
        Text(layer.textContent ?? layer.name, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text(layer.kind.name, style: const TextStyle(fontSize: 11, color: Color(0xFF9DABC3))),
        const SizedBox(height: 12),
        Text('Keyframe tracks: ${layer.keyframeTracks.length}'),
        Text('Masks: ${layer.masks.length}'),
        Text('Effects: ${layer.effects.length}'),
        Text('Parent: ${layer.parentId ?? 'None'}'),
        if (layer.photoshopClipped)
          Text(
            'Clipped to base: ${layer.clippingBaseLayerId ?? 'unresolved'}',
            style: const TextStyle(fontSize: 10, color: Color(0xFFE4C38A)),
          ),
        if (layer.smartObjectResourceId != null)
          Text(
            'Smart Object ID: ${layer.smartObjectResourceId}',
            style: const TextStyle(fontSize: 10, color: Color(0xFF9EDBCF)),
          ),
        if (layer.smartObjectSourceUri != null) ...[
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () => Share.shareXFiles(
              [XFile(layer.smartObjectSourceUri!)],
              text: 'Embedded Photoshop Smart Object',
            ),
            icon: const Icon(Icons.open_in_new, size: 15),
            label: const Text('Share embedded Smart Object source'),
          ),
        ],
        if (layer.photoshopAdjustmentKey != null)
          Text(
            'PSD adjustment block: ${layer.photoshopAdjustmentKey}',
            style: const TextStyle(fontSize: 10, color: Color(0xFFB6A5FF)),
          ),
        const SizedBox(height: 8),
        DropdownButtonFormField<LayerBlendMode>(
          initialValue: layer.blendMode,
          decoration: const InputDecoration(labelText: 'Blend mode'),
          items: LayerBlendMode.values
              .map((mode) => DropdownMenuItem(value: mode, child: Text(mode.name)))
              .toList(),
          onChanged: (value) {
            if (value != null) _controller.setLayerBlendMode(value);
          },
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _addKeyframe('position.x'),
          icon: const Icon(Icons.key, size: 16),
          label: const Text('Add Position Keyframe'),
        ),
      ],
    );
  }

  Widget _buildTimingPanel(CompositionLayer layer) {
    Widget field(String label, int value, ValueChanged<int> onSubmit) {
      return SizedBox(
        width: 135,
        child: TextFormField(
          key: ValueKey<String>(layer.id + label + value.toString()),
          initialValue: value.toString(),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onFieldSubmitted: (text) {
            final parsed = int.tryParse(text);
            if (parsed != null) onSubmit(parsed);
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('CLIP TIMING', Icons.content_cut),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            field('Timeline start (ms)', layer.startMs,
                (value) => _controller.setLayerTiming(layer.id, startMs: value)),
            field('Duration (ms)', layer.durationMs,
                (value) => _controller.setLayerTiming(layer.id, durationMs: value)),
            if (layer.kind == LayerKind.video || layer.kind == LayerKind.audio)
              field('Source In (ms)', layer.sourceInMs,
                  (value) => _controller.setLayerTiming(layer.id, sourceInMs: value)),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Timeline out: ' + layer.endMs.toString() + ' ms',
          style: const TextStyle(fontSize: 11, color: Color(0xFF9BAAC1)),
        ),
        const Text(
          'Drag the clip body in the timeline to move it. Drag its right edge to change duration. Source In trims the media before timeline placement.',
          style: TextStyle(fontSize: 10, color: Color(0xFF98A7C0)),
        ),
      ],
    );
  }

  Widget _buildShapePanel(CompositionLayer layer) {
    final style = layer.shapeStyle ?? const ShapeStyle();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('VECTOR SHAPE', Icons.category_outlined),
        DropdownButtonFormField<ShapePrimitive>(
          initialValue: style.primitive,
          decoration: const InputDecoration(labelText: 'Primitive'),
          items: ShapePrimitive.values
              .map((value) => DropdownMenuItem(value: value, child: Text(value.name)))
              .toList(),
          onChanged: (value) {
            if (value != null) _controller.setShapeStyle(style.copyWith(primitive: value));
          },
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: style.fillColor,
          decoration: const InputDecoration(labelText: 'Fill color (hex)'),
          onChanged: (value) => _controller.setShapeStyle(style.copyWith(fillColor: value)),
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: style.strokeColor,
          decoration: const InputDecoration(labelText: 'Stroke color (hex)'),
          onChanged: (value) => _controller.setShapeStyle(style.copyWith(strokeColor: value)),
        ),
        Text('Stroke width: ${style.strokeWidth.toStringAsFixed(1)} px'),
        Slider(
          min: 0,
          max: 30,
          value: style.strokeWidth.clamp(0, 30).toDouble(),
          onChanged: (value) => _controller.setShapeStyle(style.copyWith(strokeWidth: value)),
        ),
        Text('Corner radius: ${style.cornerRadius.toStringAsFixed(1)} px'),
        Slider(
          min: 0,
          max: 100,
          value: style.cornerRadius.clamp(0, 100).toDouble(),
          onChanged: (value) => _controller.setShapeStyle(style.copyWith(cornerRadius: value)),
        ),
      ],
    );
  }

  Widget _buildTransformPanel(CompositionLayer layer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('TRANSFORM', Icons.open_with),
        for (final item in const [
          ('Position X', 'position.x', 0.0, 1920.0),
          ('Position Y', 'position.y', 0.0, 1080.0),
          ('Position Z', 'position.z', -2000.0, 2000.0),
          ('Scale X', 'scale.x', 0.0, 400.0),
          ('Scale Y', 'scale.y', 0.0, 400.0),
          ('Rotation Z', 'rotation.z', -360.0, 360.0),
          ('Rotation X', 'rotation.x', -180.0, 180.0),
          ('Rotation Y', 'rotation.y', -180.0, 180.0),
          ('Opacity', 'opacity', 0.0, 100.0),
        ])
          _animatedPropertyRow(layer, item.$1, item.$2, item.$3, item.$4),
      ],
    );
  }

  Widget _animatedPropertyRow(
    CompositionLayer layer,
    String label,
    String property,
    double min,
    double max,
  ) {
    final value = layer.valueAt(property, _controller.document.playheadMs);
    final matchingTracks =
        layer.keyframeTracks.where((item) => item.property == property);
    final keyframes =
        matchingTracks.isEmpty ? 0 : matchingTracks.first.keyframes.length;
    ScalarKeyframe? activeKeyframe;
    if (matchingTracks.isNotEmpty) {
      for (final frame in matchingTracks.first.keyframes) {
        if (frame.timeMs == _controller.document.playheadMs) {
          activeKeyframe = frame;
          break;
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 11))),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Add keyframe at current playhead',
              onPressed: () => _addKeyframe(property),
              icon: Icon(
                Icons.diamond,
                size: 16,
                color: keyframes > 0
                    ? const Color(0xFFB6A5FF)
                    : const Color(0xFF8A98B0),
              ),
            ),
            if (keyframes > 0)
              PopupMenuButton<Interpolation>(
                tooltip: 'Set keyframe interpolation at playhead',
                icon: const Icon(Icons.linear_scale, size: 16),
                onSelected: (value) =>
                    _controller.setInterpolation(property, value),
                itemBuilder: (_) => Interpolation.values
                    .map((value) => PopupMenuItem(
                          value: value,
                          child: Text(value.name),
                        ))
                    .toList(),
              ),
            if (activeKeyframe?.interpolation == Interpolation.cubicBezier)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Edit Bezier graph',
                icon: const Icon(Icons.timeline, size: 16),
                onPressed: () => _editBezierCurve(
                  property,
                  activeKeyframe!.bezier,
                ),
              ),
            SizedBox(
              width: 54,
              child: Text(
                value.toStringAsFixed(1),
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
        Slider(
          min: min,
          max: max,
          value: value.clamp(min, max).toDouble(),
          onChanged: (next) => _controller.setTransformValue(property, next),
          onChangeEnd: (next) {
            if (keyframes > 0) {
              _controller.setTransformValue(property, next, keyframe: true);
            }
          },
        ),
      ],
    );
  }

  Widget _buildAnimationPanel(CompositionLayer layer) {
    final trackCount = layer.keyframeTracks.length +
        layer.effects.fold<int>(
          0,
          (count, effect) => count + effect.keyframeTracks.length,
        ) +
        layer.masks.fold<int>(
          0,
          (count, mask) => count + mask.keyframeTracks.length,
        ) +
        _controller.document.audioBuses.fold<int>(
          0,
          (count, bus) => count + bus.keyframeTracks.length,
        );
    final cards = <Widget>[
      _panelHeader('UNIFIED GRAPH EDITOR', Icons.timeline),
      const Text(
        'Every animated property on this layer is listed here. Choose a keyframe to adjust its interpolation and open the same Bezier graph editor.',
        style: TextStyle(fontSize: 10, color: Color(0xFF98A7C0)),
      ),
      const SizedBox(height: 8),
      if (trackCount == 0)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'No animated properties yet. Add keyframes in Transform, Effects or Audio.',
              style: TextStyle(fontSize: 11),
            ),
          ),
        ),
    ];

    for (final track in layer.keyframeTracks) {
      cards.add(_buildUnifiedTrackCard(
        title: track.property,
        track: track,
      ));
    }
    for (final effect in layer.effects) {
      for (final track in effect.keyframeTracks) {
        cards.add(_buildUnifiedTrackCard(
          title: '${effect.name} · ${track.property}',
          track: track,
          effectId: effect.id,
        ));
      }
    }
    for (final mask in layer.masks) {
      for (final track in mask.keyframeTracks) {
        cards.add(_buildUnifiedTrackCard(
          title: 'Mask · ${mask.name} · ${track.property}',
          track: track,
          maskId: mask.id,
        ));
      }
    }
    for (final bus in _controller.document.audioBuses) {
      for (final track in bus.keyframeTracks) {
        cards.add(_buildUnifiedTrackCard(
          title: 'Audio Bus · ${bus.name} · ${track.property}',
          track: track,
          busId: bus.id,
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: cards,
    );
  }

  Widget _buildUnifiedTrackCard({
    required String title,
    required KeyframeTrack track,
    String? effectId,
    String? maskId,
    String? busId,
  }) {
    final frames = [...track.keyframes]
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    final first = frames.first;
    final active = frames.firstWhere(
      (frame) => frame.timeMs == _controller.document.playheadMs,
      orElse: () => first,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${frames.length} keys',
                  style: const TextStyle(
                    fontSize: 9,
                    color: Color(0xFF9AA8BD),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Open keyframe in timeline',
                  onPressed: () => _controller.setPlayhead(active.timeMs),
                  icon: const Icon(Icons.my_location, size: 15),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Edit cubic Bezier graph',
                  onPressed: () => _editBezierCurve(
                    track.property,
                    active.bezier,
                    effectId: effectId,
                    maskId: maskId,
                    busId: busId,
                    timeMs: active.timeMs,
                  ),
                  icon: const Icon(Icons.timeline, size: 16),
                ),
              ],
            ),
            Row(
              children: [
                const Text(
                  'Interpolation',
                  style: TextStyle(fontSize: 9, color: Color(0xFF9AA8BD)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<Interpolation>(
                    isExpanded: true,
                    value: active.interpolation,
                    underline: const SizedBox.shrink(),
                    items: Interpolation.values
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(
                                value.name,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      if (maskId != null) {
                        _controller.setMaskInterpolation(
                          maskId,
                          track.property,
                          value,
                          timeMs: active.timeMs,
                        );
                      } else if (busId != null) {
                        _controller.setAudioBusInterpolation(
                          busId,
                          track.property,
                          value,
                          timeMs: active.timeMs,
                        );
                      } else {
                        _controller.setInterpolation(
                          track.property,
                          value,
                          effectId: effectId,
                          timeMs: active.timeMs,
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEffectsPanel(CompositionLayer layer) {
    final filtered = EffectCatalog.all
        .where((effect) => _effectCategory == 'All' || effect.category == _effectCategory)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('EFFECT LIBRARY', Icons.auto_awesome),
        DropdownButtonFormField<String>(
          initialValue: _effectCategory,
          items: ['All', ...EffectCatalog.categories]
              .map((category) => DropdownMenuItem(value: category, child: Text(category)))
              .toList(),
          onChanged: (value) => setState(() => _effectCategory = value ?? 'All'),
        ),
        const SizedBox(height: 8),
        for (final effect in filtered)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(effect.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            subtitle: Text(effect.description, style: const TextStyle(fontSize: 9), maxLines: 2),
            trailing: IconButton(
              tooltip: 'Add effect',
              icon: const Icon(Icons.add_circle_outline, size: 18),
              onPressed: () => _controller.addEffect(effect.id),
            ),
          ),
        const Divider(),
        _panelHeader('APPLIED EFFECTS', Icons.tune),
        if (layer.effects.isEmpty)
          const Text('No effects added to this layer.', style: TextStyle(fontSize: 10))
        else
          for (final effect in layer.effects)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(effect.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
                        Switch(
                          value: effect.enabled,
                          onChanged: (value) => _controller.setEffectEnabled(effect.id, value),
                        ),
                      ],
                    ),
                    for (final parameter in EffectCatalog.find(effect.effectId)?.parameters ?? const [])
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${parameter.label}  ${effect.parameterAt(parameter.id, _controller.document.playheadMs, fallback: parameter.defaultValue).toStringAsFixed(2)}${parameter.unit}',
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Animate this effect parameter',
                                onPressed: () => _controller.addEffectKeyframe(effect.id, parameter.id),
                                icon: Icon(
                                  Icons.diamond,
                                  size: 15,
                                  color: effect.keyframeTracks.any((track) => track.property == parameter.id)
                                      ? const Color(0xFFB8A4FF)
                                      : const Color(0xFF8290A8),
                                ),
                              ),
                              if (effect.keyframeTracks.any((track) =>
                                  track.property == parameter.id))
                                PopupMenuButton<Interpolation>(
                                  tooltip: 'Set effect keyframe interpolation',
                                  icon: const Icon(Icons.linear_scale, size: 15),
                                  onSelected: (value) => _controller.setInterpolation(
                                    parameter.id,
                                    value,
                                    effectId: effect.id,
                                  ),
                                  itemBuilder: (_) => Interpolation.values
                                      .map((value) => PopupMenuItem(
                                            value: value,
                                            child: Text(value.name),
                                          ))
                                      .toList(),
                                ),
                            ],
                          ),
                          Slider(
                            min: parameter.min,
                            max: parameter.max,
                            value: effect.parameterAt(
                              parameter.id,
                              _controller.document.playheadMs,
                              fallback: parameter.defaultValue,
                            ).clamp(parameter.min, parameter.max).toDouble(),
                            onChanged: (value) => _controller.setEffectParameter(
                              effect.id,
                              parameter.id,
                              value,
                              keyframe: effect.keyframeTracks.any((track) => track.property == parameter.id),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildTransitionsPanel(CompositionLayer layer) {
    const validator = TransitionFrameValidator();
    final document = _controller.document;
    final report = validator.validate(document);
    final transitions = document.transitions.where(
      (item) => item.fromLayerId == layer.id || item.toLayerId == layer.id,
    ).toList();
    final layers = _controller.document.layers;
    String nameOf(String id) {
      final matches = layers.where((item) => item.id == id);
      return matches.isEmpty ? 'Missing layer' : matches.first.name;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('CLIP TRANSITIONS', Icons.auto_awesome_motion),
        PopupMenuButton<TransitionKind>(
          tooltip: 'Add transition to adjacent clip',
          onSelected: _controller.addTransition,
          itemBuilder: (_) => TransitionKind.values
              .map((kind) => PopupMenuItem(value: kind, child: Text(kind.name)))
              .toList(),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 16),
                SizedBox(width: 6),
                Text('Add transition to adjacent clip'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF141D2B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: report.isValid
                  ? const Color(0xFF35445C)
                  : const Color(0xFF8E6541),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'FRAME VALIDATION · ${document.frameRate.toStringAsFixed(3)} FPS',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  report.isValid
                      ? report.warningCount == 0
                          ? 'All transitions pass timing and clip-range checks.'
                          : '${report.warningCount} frame/range warning(s).'
                      : '${report.errorCount} error(s), ${report.warningCount} warning(s).',
                  style: const TextStyle(fontSize: 10),
                ),
                for (final issue in report.issues.where(
                  (item) => transitions.any(
                    (transition) => transition.id == item.transitionId,
                  ),
                ))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '• ${issue.message}',
                      style: TextStyle(
                        fontSize: 9,
                        color: issue.severity ==
                                TransitionIssueSeverity.error
                            ? const Color(0xFFFFB18C)
                            : const Color(0xFFE5C18C),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (transitions.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Select a video/image layer and add a transition. The transition is applied between the selected clip and its adjacent visual layer at the playhead.',
              style: TextStyle(fontSize: 10, color: Color(0xFF98A7C0)),
            ),
          ),
        for (final transition in transitions) ...[
          const Divider(height: 18),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<TransitionKind>(
                  initialValue: transition.kind,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Transition',
                    isDense: true,
                  ),
                  items: TransitionKind.values
                      .map((kind) => DropdownMenuItem(
                            value: kind,
                            child: Text(kind.name, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (kind) => _controller.updateTransition(
                    transition.id,
                    kind: kind,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove transition',
                onPressed: () => _controller.removeTransition(transition.id),
                icon: const Icon(Icons.delete_outline, size: 17),
              ),
            ],
          ),
          Text(
            nameOf(transition.fromLayerId) + ' → ' + nameOf(transition.toLayerId),
            style: const TextStyle(fontSize: 10, color: Color(0xFF9BAAC1)),
          ),
          _settingSlider(
            'Duration (ms)',
            transition.durationMs.toDouble(),
            50,
            4000,
            (value) => _controller.updateTransition(
              transition.id,
              durationMs: value.round(),
            ),
          ),
          _settingSlider(
            'Start (ms)',
            transition.startMs.toDouble(),
            0,
            _controller.document.durationMs.toDouble(),
            (value) => _controller.updateTransition(
              transition.id,
              startMs: value.round(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTrackingPanel(CompositionLayer layer) {
    if (layer.kind != LayerKind.video || layer.sourceUri == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _panelHeader('MOTION TRACKING', Icons.track_changes),
          const Text(
            'Select a video layer to track a fixed object region and convert its movement into position keyframes.',
            style: TextStyle(fontSize: 11),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('MOTION TRACKING', Icons.track_changes),
        const Text(
          'Choose a rectangle around a high-contrast object in the first source frame. Coordinates are source-video pixels.',
          style: TextStyle(fontSize: 10, color: Color(0xFF9BAAC1)),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _trackingField('Left (px)', _trackingLeft,
                (value) => setState(() => _trackingLeft = value)),
            _trackingField('Top (px)', _trackingTop,
                (value) => setState(() => _trackingTop = value)),
            _trackingField('Width (px)', _trackingWidth,
                (value) => setState(() => _trackingWidth = value)),
            _trackingField('Height (px)', _trackingHeight,
                (value) => setState(() => _trackingHeight = value)),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Match threshold  ' + _trackingThreshold.toStringAsFixed(2),
          style: const TextStyle(fontSize: 10),
        ),
        Slider(
          min: 0.01,
          max: 0.99,
          value: _trackingThreshold,
          onChanged: (value) => setState(() => _trackingThreshold = value),
        ),
        DropdownButtonFormField<bool>(
          initialValue: _stabilizeTracking,
          decoration: const InputDecoration(labelText: 'Tracking action'),
          items: const [
            DropdownMenuItem(value: true, child: Text('Stabilize the object')),
            DropdownMenuItem(value: false, child: Text('Follow the object motion')),
          ],
          onChanged: (value) => setState(
            () => _stabilizeTracking = value ?? true,
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _tracking ? null : _runMotionTracking,
          icon: _tracking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.center_focus_strong),
          label: Text(_tracking ? 'TRACKING…' : 'TRACK OBJECT & CREATE KEYFRAMES'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tracker type: template matching at 10 samples/second. It handles translation on a mostly unchanged object; fast scale changes, rotation, occlusion and planar perspective need a stronger optical-flow/planar tracker.',
          style: TextStyle(fontSize: 10, color: Color(0xFF98A7C0)),
        ),
      ],
    );
  }

  Widget _audioBusAnimatedSlider(
    AudioBus bus,
    String property,
    String label,
    double min,
    double max,
  ) {
    final timeMs = _controller.document.playheadMs;
    final value = bus.valueAt(property, timeMs);
    final tracks = bus.keyframeTracks.where(
      (track) => track.property == property,
    );
    final animated = tracks.isNotEmpty && tracks.first.keyframes.isNotEmpty;
    final hasKey = animated &&
        tracks.first.keyframes.any((frame) => frame.timeMs == timeMs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 10)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Add bus automation keyframe',
              onPressed: () => _controller.setAudioBusValue(
                bus.id,
                property,
                value,
                keyframe: true,
              ),
              icon: Icon(
                Icons.diamond,
                size: 15,
                color: hasKey
                    ? const Color(0xFFB8A4FF)
                    : animated
                        ? const Color(0xFF8D9AB2)
                        : const Color(0xFF65738A),
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                value.toStringAsFixed(2),
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 9),
              ),
            ),
          ],
        ),
        Slider(
          min: min,
          max: max,
          value: value.clamp(min, max).toDouble(),
          onChanged: (next) => _controller.setAudioBusValue(
            bus.id,
            property,
            next,
            keyframe: animated,
          ),
        ),
      ],
    );
  }

  Widget _buildAudioBusPanel(CompositionLayer? layer) {
    final buses = _controller.document.audioBuses;
    final master = buses.where((bus) => bus.isMaster).firstOrNull;
    final selectedBusId = layer?.audioSettings.busId ??
        master?.id ??
        buses.firstOrNull?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('AUDIO BUS MIXER', Icons.tune),
        const Text(
          'Route audio and video tracks into submix buses. Each bus has independent gain, stereo balance, compression and limiting.',
          style: TextStyle(fontSize: 10, color: Color(0xFF98A7C0)),
        ),
        if (layer != null &&
            (layer.kind == LayerKind.audio || layer.kind == LayerKind.video)) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: selectedBusId,
            decoration: const InputDecoration(
              labelText: 'Selected track output',
              isDense: true,
            ),
            items: buses
                .map((bus) => DropdownMenuItem(
                      value: bus.id,
                      child: Text(bus.name),
                    ))
                .toList(),
            onChanged: (value) =>
                _controller.assignSelectedAudioBus(value),
          ),
        ],
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () {
            _controller.addAudioBus();
            setState(() => _notice = 'New audio submix bus added');
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('ADD SUBMIX BUS'),
        ),
        const SizedBox(height: 8),
        for (final bus in buses)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        bus.isMaster ? Icons.speaker : Icons.graphic_eq,
                        size: 17,
                        color: bus.isMaster
                            ? const Color(0xFF7EDBCB)
                            : const Color(0xFFB6A5FF),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          bus.name.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                      Switch(
                        value: !bus.muted,
                        onChanged: (value) => _controller.updateAudioBus(
                          bus.copyWith(muted: !value),
                        ),
                      ),
                      if (!bus.isMaster)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Remove bus and route its tracks to Master',
                          onPressed: () => _controller.removeAudioBus(bus.id),
                          icon: const Icon(Icons.delete_outline, size: 17),
                        ),
                    ],
                  ),
                  _audioBusAnimatedSlider(
                    bus,
                    'gainDb',
                    'Bus gain (dB)',
                    -24,
                    12,
                  ),
                  _audioBusAnimatedSlider(
                    bus,
                    'pan',
                    'Bus pan',
                    -1,
                    1,
                  ),
                  const Divider(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Compressor',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: bus.compressorEnabled,
                    onChanged: (value) => _controller.updateAudioBus(
                      bus.copyWith(compressorEnabled: value),
                    ),
                  ),
                  if (bus.compressorEnabled) ...[
                    _settingSlider(
                      'Threshold (dB)',
                      bus.compressorThresholdDb,
                      -48,
                      0,
                      (value) => _controller.updateAudioBus(
                        bus.copyWith(compressorThresholdDb: value),
                      ),
                    ),
                    _settingSlider(
                      'Ratio',
                      bus.compressorRatio,
                      1,
                      20,
                      (value) => _controller.updateAudioBus(
                        bus.copyWith(compressorRatio: value),
                      ),
                    ),
                    _settingSlider(
                      'Attack (ms)',
                      bus.compressorAttackMs,
                      1,
                      200,
                      (value) => _controller.updateAudioBus(
                        bus.copyWith(compressorAttackMs: value),
                      ),
                    ),
                    _settingSlider(
                      'Release (ms)',
                      bus.compressorReleaseMs,
                      10,
                      1000,
                      (value) => _controller.updateAudioBus(
                        bus.copyWith(compressorReleaseMs: value),
                      ),
                    ),
                    _settingSlider(
                      'Makeup gain (dB)',
                      bus.makeupGainDb,
                      0,
                      18,
                      (value) => _controller.updateAudioBus(
                        bus.copyWith(makeupGainDb: value),
                      ),
                    ),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Output limiter',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: bus.limiterEnabled,
                    onChanged: (value) => _controller.updateAudioBus(
                      bus.copyWith(limiterEnabled: value),
                    ),
                  ),
                  if (bus.limiterEnabled)
                    _settingSlider(
                      'Ceiling (dBFS)',
                      bus.limiterCeilingDb,
                      -12,
                      0,
                      (value) => _controller.updateAudioBus(
                        bus.copyWith(limiterCeilingDb: value),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAudioPanel(CompositionLayer layer) {
    if (layer.kind != LayerKind.audio && layer.kind != LayerKind.video) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _panelHeader('AUDIO MIXER', Icons.graphic_eq),
          const Text('Select an Audio or Video layer to edit audio gain, pan, fades and ducking.'),
        ],
      );
    }
    final audio = layer.audioSettings;
    final gainTrack = layer.keyframeTracks.where(
      (track) => track.property == 'audio.gainDb',
    );
    final animated = gainTrack.isNotEmpty && gainTrack.first.keyframes.isNotEmpty;
    final gain = animated
        ? gainTrack.first.sample(
            _controller.document.playheadMs,
            fallback: audio.gainDb,
          )
        : audio.gainDb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('AUDIO MIXER', Icons.graphic_eq),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Mute this track', style: TextStyle(fontSize: 11)),
          value: audio.muted,
          onChanged: (value) => _controller.setAudioSettings(
            audio.copyWith(muted: value),
          ),
        ),
        Row(
          children: [
            const Expanded(child: Text('Gain (dB)', style: TextStyle(fontSize: 11))),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Keyframe audio gain',
              onPressed: () => _controller.setAudioGain(gain, keyframe: true),
              icon: Icon(
                Icons.diamond,
                size: 16,
                color: animated
                    ? const Color(0xFFB8A4FF)
                    : const Color(0xFF8290A8),
              ),
            ),
            Text(gain.toStringAsFixed(1), style: const TextStyle(fontSize: 10)),
          ],
        ),
        Slider(
          min: -60,
          max: 12,
          value: gain.clamp(-60, 12).toDouble(),
          onChanged: (value) => _controller.setAudioGain(
            value,
            keyframe: animated,
          ),
        ),
        Builder(
          builder: (context) {
            final panTrack = layer.keyframeTracks.where(
              (track) => track.property == 'audio.pan',
            );
            final panAnimated = panTrack.isNotEmpty &&
                panTrack.first.keyframes.isNotEmpty;
            final pan = panAnimated
                ? panTrack.first.sample(
                    _controller.document.playheadMs,
                    fallback: audio.pan,
                  )
                : audio.pan;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Pan', style: TextStyle(fontSize: 11)),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Add pan automation keyframe',
                      onPressed: () => _controller.setAudioPan(
                        pan,
                        keyframe: true,
                      ),
                      icon: Icon(
                        Icons.diamond,
                        size: 16,
                        color: panAnimated
                            ? const Color(0xFFB8A4FF)
                            : const Color(0xFF8290A8),
                      ),
                    ),
                    Text(
                      pan.toStringAsFixed(2),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
                Slider(
                  min: -1,
                  max: 1,
                  value: pan.clamp(-1, 1).toDouble(),
                  onChanged: (value) => _controller.setAudioPan(
                    value,
                    keyframe: panAnimated,
                  ),
                ),
              ],
            );
          },
        ),
        const Divider(height: 18),
        const Text(
          '3-BAND PARAMETRIC EQ',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        _settingSlider('Low · 120 Hz (dB)', audio.lowEqDb, -12, 12,
            (value) => _controller.setAudioSettings(
              audio.copyWith(lowEqDb: value),
            )),
        _settingSlider('Mid · 1 kHz (dB)', audio.midEqDb, -12, 12,
            (value) => _controller.setAudioSettings(
              audio.copyWith(midEqDb: value),
            )),
        _settingSlider('High · 8 kHz (dB)', audio.highEqDb, -12, 12,
            (value) => _controller.setAudioSettings(
              audio.copyWith(highEqDb: value),
            )),
        _settingSlider('Fade In (ms)', audio.fadeInMs.toDouble(), 0, 5000,
            (value) => _controller.setAudioSettings(
              audio.copyWith(fadeInMs: value.round()),
            )),
        _settingSlider('Fade Out (ms)', audio.fadeOutMs.toDouble(), 0, 5000,
            (value) => _controller.setAudioSettings(
              audio.copyWith(fadeOutMs: value.round()),
            )),
        DropdownButtonFormField<AudioDuckingRole>(
          initialValue: audio.duckingRole,
          decoration: const InputDecoration(labelText: 'Ducking role'),
          items: AudioDuckingRole.values
              .map((role) => DropdownMenuItem(value: role, child: Text(role.name)))
              .toList(),
          onChanged: (value) => _controller.setAudioSettings(
            audio.copyWith(duckingRole: value ?? AudioDuckingRole.none),
          ),
        ),
        if (audio.duckingRole == AudioDuckingRole.background) ...[
          _settingSlider('Ducking threshold', audio.duckingThreshold, 0.001, 0.5,
              (value) => _controller.setAudioSettings(
                audio.copyWith(duckingThreshold: value),
              )),
          _settingSlider('Ducking ratio', audio.duckingRatio, 1, 20,
              (value) => _controller.setAudioSettings(
                audio.copyWith(duckingRatio: value),
              )),
          _settingSlider('Attack (ms)', audio.duckingAttackMs, 1, 200,
              (value) => _controller.setAudioSettings(
                audio.copyWith(duckingAttackMs: value),
              )),
          _settingSlider('Release (ms)', audio.duckingReleaseMs, 10, 1000,
              (value) => _controller.setAudioSettings(
                audio.copyWith(duckingReleaseMs: value),
              )),
        ],
        const Text(
          'Tracks marked Trigger control the ducking of tracks marked Background during the final mix.',
          style: TextStyle(fontSize: 10, color: Color(0xFF98A7C0)),
        ),
      ],
    );
  }

  Widget _animatedMaskPropertyRow(
    MaskModel mask,
    String label,
    String property,
    double min,
    double max,
  ) {
    final playhead = _controller.document.playheadMs;
    final value = mask.valueAt(property, playhead);
    final tracks = mask.keyframeTracks.where(
      (track) => track.property == property,
    );
    final animated = tracks.isNotEmpty && tracks.first.keyframes.isNotEmpty;
    final hasKeyAtPlayhead = animated &&
        tracks.first.keyframes.any((frame) => frame.timeMs == playhead);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 10)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Add mask keyframe at playhead',
              onPressed: () => _controller.setMaskAnimatedValue(
                mask.id,
                property,
                value,
                keyframe: true,
              ),
              icon: Icon(
                Icons.diamond,
                size: 15,
                color: hasKeyAtPlayhead
                    ? const Color(0xFFB8A4FF)
                    : animated
                        ? const Color(0xFF8D9AB2)
                        : const Color(0xFF65738A),
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                value.toStringAsFixed(2),
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 9),
              ),
            ),
          ],
        ),
        Slider(
          min: min,
          max: max,
          value: value.clamp(min, max).toDouble(),
          onChanged: (next) => _controller.setMaskAnimatedValue(
            mask.id,
            property,
            next,
            keyframe: animated,
          ),
        ),
      ],
    );
  }

  Widget _buildMasksPanel(CompositionLayer layer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('MASKS', Icons.crop_free),
        Wrap(
          spacing: 6,
          children: [
            for (final shape in MaskShape.values)
              ActionChip(
                label: Text(shape.name),
                onPressed: () => _controller.addMask(shape: shape),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final mask in layer.masks)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(mask.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
                      Switch(
                        value: mask.enabled,
                        onChanged: (value) => _controller.setMaskEnabled(mask.id, value),
                      ),
                    ],
                  ),
                  DropdownButtonFormField<MaskOperation>(
                    initialValue: mask.operation,
                    decoration: const InputDecoration(labelText: 'Mask mode'),
                    items: MaskOperation.values
                        .map((value) => DropdownMenuItem(value: value, child: Text(value.name)))
                        .toList(),
                    onChanged: (value) => _controller.setMaskParameters(mask.id, operation: value),
                  ),
                  _animatedMaskPropertyRow(mask, 'Feather', 'feather', 0, 200),
                  _animatedMaskPropertyRow(mask, 'Expansion', 'expansion', -100, 100),
                  _animatedMaskPropertyRow(mask, 'Left', 'left', 0, (1 - mask.width).clamp(0, 1).toDouble()),
                  _animatedMaskPropertyRow(mask, 'Top', 'top', 0, (1 - mask.height).clamp(0, 1).toDouble()),
                  _animatedMaskPropertyRow(mask, 'Width', 'width', 0.01, (1 - mask.left).clamp(0.01, 1).toDouble()),
                  _animatedMaskPropertyRow(mask, 'Height', 'height', 0.01, (1 - mask.top).clamp(0.01, 1).toDouble()),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Invert mask', style: TextStyle(fontSize: 10)),
                    value: mask.inverted,
                    onChanged: (value) => _controller.setMaskParameters(mask.id, inverted: value),
                  ),
                  if (mask.shape == MaskShape.bezier)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        'BEZIER VERTICES · ${mask.vertices.length}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      children: [
                        for (var index = 0; index < mask.vertices.length; index++)
                          Builder(
                            builder: (context) {
                              final vertex = mask.vertices[index];
                              void updateAnchor(double x, double y) =>
                                  _controller.setMaskVertex(
                                    mask.id,
                                    index,
                                    anchor: Vector2(x, y),
                                  );
                              void updateInHandle(double x, double y) =>
                                  _controller.setMaskVertex(
                                    mask.id,
                                    index,
                                    inHandle: Vector2(x, y),
                                  );
                              void updateOutHandle(double x, double y) =>
                                  _controller.setMaskVertex(
                                    mask.id,
                                    index,
                                    outHandle: Vector2(x, y),
                                  );
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Vertex ${index + 1}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  _settingSlider(
                                    'Anchor X',
                                    vertex.anchor.x,
                                    0,
                                    1,
                                    (value) => updateAnchor(value, vertex.anchor.y),
                                  ),
                                  _settingSlider(
                                    'Anchor Y',
                                    vertex.anchor.y,
                                    0,
                                    1,
                                    (value) => updateAnchor(vertex.anchor.x, value),
                                  ),
                                  _settingSlider(
                                    'In handle X',
                                    vertex.inHandle.x,
                                    -0.5,
                                    0.5,
                                    (value) => updateInHandle(value, vertex.inHandle.y),
                                  ),
                                  _settingSlider(
                                    'In handle Y',
                                    vertex.inHandle.y,
                                    -0.5,
                                    0.5,
                                    (value) => updateInHandle(vertex.inHandle.x, value),
                                  ),
                                  _settingSlider(
                                    'Out handle X',
                                    vertex.outHandle.x,
                                    -0.5,
                                    0.5,
                                    (value) => updateOutHandle(value, vertex.outHandle.y),
                                  ),
                                  _settingSlider(
                                    'Out handle Y',
                                    vertex.outHandle.y,
                                    -0.5,
                                    0.5,
                                    (value) => updateOutHandle(vertex.outHandle.x, value),
                                  ),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    title: const Text(
                                      'Smooth tangent',
                                      style: TextStyle(fontSize: 10),
                                    ),
                                    value: vertex.smooth,
                                    onChanged: (value) =>
                                        _controller.setMaskVertex(
                                      mask.id,
                                      index,
                                      smooth: value,
                                    ),
                                  ),
                                  const Divider(height: 12),
                                ],
                              );
                            },
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        const Text(
          'Rectangle, ellipse, polygon and cubic Bezier masks support feather, expansion, boolean operations and export rendering. Bezier vertices expose editable anchors and tangent handles.',
          style: TextStyle(fontSize: 10, color: Color(0xFF98A7C0)),
        ),
      ],
    );
  }

  Widget _buildParentPanel(CompositionLayer layer) {
    final candidates = _controller.document.layers.where((item) =>
        item.id != layer.id &&
        (item.kind == LayerKind.nullObject ||
            item.kind == LayerKind.camera ||
            item.kind == LayerKind.threeDModel));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('PARENT & LINK', Icons.account_tree),
        DropdownButtonFormField<String?>(
          initialValue: layer.parentId,
          decoration: const InputDecoration(labelText: 'Parent layer'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('No parent')),
            for (final candidate in candidates)
              DropdownMenuItem<String?>(
                value: candidate.id,
                child: Text(candidate.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) {
            final success = _controller.setParent(layer.id, value);
            if (!success) {
              setState(() => _notice = 'Parent link rejected: cyclic or unsupported parent.');
            }
          },
        ),
        const SizedBox(height: 10),
        const Text('Null objects control child transforms without rendering pixels. Parenting is cycle-checked.', style: TextStyle(fontSize: 10, color: Color(0xFF9BAAC1))),
      ],
    );
  }

  Widget _build3dPanel(CompositionLayer layer) {
    if (layer.kind == LayerKind.camera) {
      final camera = layer.camera ?? const CameraSettings();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _panelHeader('CAMERA CONTROLS', Icons.videocam),
          const Text(
            '2.5D perspective projection affects layer position and scale in preview/export. Mesh rendering, camera orientation, depth-of-field blur and shadow maps are not integrated yet.',
            style: TextStyle(fontSize: 10, color: Color(0xFF98A7C0)),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: camera.projection,
            decoration: const InputDecoration(labelText: 'Projection'),
            items: const [
              DropdownMenuItem(value: 'perspective', child: Text('Perspective')),
              DropdownMenuItem(value: 'orthographic', child: Text('Orthographic')),
            ],
            onChanged: (value) => _controller.setCameraSettings(
              camera.copyWith(projection: value ?? 'perspective'),
            ),
          ),
          _settingSlider('Field of View', camera.fieldOfView, 10, 120,
              (value) => _controller.setCameraSettings(camera.copyWith(fieldOfView: value))),
          _settingSlider('Focal Length', camera.focalLength, 10, 300,
              (value) => _controller.setCameraSettings(camera.copyWith(focalLength: value))),
          _settingSlider('Focus Distance', camera.focusDistance, 1, 5000,
              (value) => _controller.setCameraSettings(camera.copyWith(focusDistance: value))),
          _settingSlider('Aperture', camera.aperture, 0.7, 22,
              (value) => _controller.setCameraSettings(camera.copyWith(aperture: value))),
          const SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Depth of Field · renderer pending',
              style: TextStyle(fontSize: 11),
            ),
            value: false,
            onChanged: null,
          ),
        ],
      );
    }
    if (layer.kind == LayerKind.light) {
      final light = layer.light ?? const LightSettings();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _panelHeader('LIGHT CONTROLS', Icons.lightbulb_outline),
          const Text(
            'Light rig settings are stored in the project model. Surface shading, cast shadows and light interaction will render when the mesh lighting pipeline is integrated.',
            style: TextStyle(fontSize: 10, color: Color(0xFF98A7C0)),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<LightKind>(
            initialValue: light.kind,
            decoration: const InputDecoration(labelText: 'Light type'),
            items: LightKind.values
                .map((value) => DropdownMenuItem(value: value, child: Text(value.name)))
                .toList(),
            onChanged: (value) => _controller.setLightSettings(
              light.copyWith(kind: value ?? LightKind.directional),
            ),
          ),
          _settingSlider('Intensity', light.intensity, 0, 1000,
              (value) => _controller.setLightSettings(light.copyWith(intensity: value))),
          _settingSlider('Spot Cone', light.coneAngle, 1, 180,
              (value) => _controller.setLightSettings(light.copyWith(coneAngle: value))),
          _settingSlider('Shadow Softness', light.shadowSoftness, 0, 100,
              (value) => _controller.setLightSettings(light.copyWith(shadowSoftness: value))),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cast Shadows', style: TextStyle(fontSize: 11)),
            value: light.castShadows,
            onChanged: (value) => _controller.setLightSettings(
              light.copyWith(castShadows: value),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        _panelHeader('3D LAYER', Icons.view_in_ar),
        const Text(
          'Camera and Null-parent transforms are evaluated in 2.5D. GLB/OBJ mesh import, material shading and full 3D scene rendering are not integrated yet.',
          style: TextStyle(fontSize: 11),
        ),
      ],
    );
  }

  Widget _settingSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$label  ${value.toStringAsFixed(1)}', style: const TextStyle(fontSize: 10)),
        Slider(
          min: min,
          max: max,
          value: value.clamp(min, max).toDouble(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildTimeline(List<CompositionLayer> layers, int playhead, int duration) {
    return Container(
      height: 212,
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        color: Color(0xFF101722),
        border: Border(top: BorderSide(color: Color(0xFF29354A))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.timeline, size: 16),
              const SizedBox(width: 8),
              const Text('NLE / ANIMATION TIMELINE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const Spacer(),
              Text(_time(playhead), style: const TextStyle(fontSize: 10, color: Color(0xFFB7C4DC))),
              IconButton(
                tooltip: 'Previous frame',
                onPressed: () => _controller.setPlayhead(playhead - (1000 / _controller.document.frameRate).round()),
                icon: const Icon(Icons.chevron_left, size: 18),
              ),
              IconButton(
                tooltip: 'Next frame',
                onPressed: () => _controller.setPlayhead(playhead + (1000 / _controller.document.frameRate).round()),
                icon: const Icon(Icons.chevron_right, size: 18),
              ),
              PopupMenuButton<TransitionKind>(
                tooltip: 'Add transition',
                onSelected: _controller.addTransition,
                itemBuilder: (_) => TransitionKind.values
                    .map((kind) => PopupMenuItem(value: kind, child: Text(kind.name)))
                    .toList(),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.auto_awesome_motion, size: 18),
                ),
              ),
            ],
          ),
          Slider(
            value: playhead.toDouble().clamp(0, duration.toDouble()).toDouble(),
            min: 0,
            max: duration.toDouble(),
            onChanged: (value) => _controller.setPlayhead(value.round()),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: layers.length,
              itemBuilder: (context, index) {
                final layer = layers[index];
                return InkWell(
                  onTap: () => _controller.selectLayer(layer.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(width: 130, child: Text(layer.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10))),
                        Expanded(child: _buildTimelineClip(layer, duration)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineClip(CompositionLayer layer, int duration) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final safeDuration = math.max(1, duration);
        final left = (layer.startMs / safeDuration * width)
            .clamp(0.0, width).toDouble();
        final right = (layer.endMs / safeDuration * width)
            .clamp(left, width).toDouble();
        final clipWidth = math.max(8.0, right - left);
        final color = switch (layer.kind) {
          LayerKind.audio => const Color(0xFF247B76),
          LayerKind.video => const Color(0xFF425B9B),
          LayerKind.image || LayerKind.photoshopLayer => const Color(0xFF66539D),
          LayerKind.shape || LayerKind.text => const Color(0xFF93613D),
          _ => const Color(0xFF475568),
        };
        final markers = <int>[
          for (final track in layer.keyframeTracks)
            for (final keyframe in track.keyframes) keyframe.timeMs,
          for (final effect in layer.effects)
            for (final track in effect.keyframeTracks)
              for (final keyframe in track.keyframes) keyframe.timeMs,
        ];
        return GestureDetector(
          onTapDown: (details) {
            final position = (details.localPosition.dx / width * safeDuration)
                .round().clamp(0, safeDuration);
            _controller.setPlayhead(position);
          },
          child: Container(
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF101827),
              border: Border.all(color: const Color(0xFF2B3850)),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                for (final transition in _controller.document.transitions)
                  if (transition.fromLayerId == layer.id ||
                      transition.toLayerId == layer.id)
                    Positioned(
                      left: (transition.startMs / safeDuration * width)
                          .clamp(0.0, width).toDouble(),
                      width: (transition.durationMs / safeDuration * width)
                          .clamp(2.0, width).toDouble(),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0x66B48CFF),
                          border: Border.all(color: const Color(0xFFB48CFF)),
                        ),
                      ),
                    ),
                Positioned(
                  left: left,
                  width: clipWidth,
                  top: 3,
                  bottom: 3,
                  child: GestureDetector(
                    onHorizontalDragUpdate: layer.locked
                        ? null
                        : (details) {
                            final delta = (details.delta.dx / width *
                                    safeDuration)
                                .round();
                            _controller.setLayerTiming(
                              layer.id,
                              startMs: layer.startMs + delta,
                            );
                          },
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: layer.locked
                              ? const Color(0xFF687386)
                              : const Color(0xFF91A8FF),
                        ),
                      ),
                      child: Stack(
                        children: [
                          if (layer.kind == LayerKind.audio &&
                              layer.sourceUri != null)
                            Positioned.fill(
                              child: FutureBuilder<File?>(
                                future: _waveformFor(layer.sourceUri!),
                                builder: (context, snapshot) {
                                  final waveform = snapshot.data;
                                  if (waveform == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return IgnorePointer(
                                    child: Opacity(
                                      opacity: 0.82,
                                      child: Image.file(
                                        waveform,
                                        fit: BoxFit.fill,
                                        errorBuilder: (_, __, ___) =>
                                            const SizedBox.shrink(),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          Positioned(
                            left: 5,
                            right: 12,
                            top: 4,
                            child: Text(
                              layer.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFF2F5FF),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: GestureDetector(
                              onHorizontalDragUpdate: layer.locked
                                  ? null
                                  : (details) {
                                      final delta = (details.delta.dx /
                                              width * safeDuration)
                                          .round();
                                      _controller.setLayerTiming(
                                        layer.id,
                                        durationMs: layer.durationMs + delta,
                                      );
                                    },
                              child: Container(
                                width: 9,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFB8C8FF),
                                  borderRadius: BorderRadius.horizontal(
                                    right: Radius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                for (final time in markers)
                  Positioned(
                    left: (time / safeDuration * width)
                        .clamp(0.0, math.max(0.0, width - 10)).toDouble(),
                    top: 0,
                    bottom: 0,
                    child: const Icon(
                      Icons.diamond,
                      size: 10,
                      color: Color(0xFFD6C8FF),
                    ),
                  ),
                Positioned(
                  left: (_controller.document.playheadMs / safeDuration * width)
                      .clamp(0.0, math.max(0.0, width - 1)).toDouble(),
                  top: 0,
                  bottom: 0,
                  child: Container(width: 1, color: const Color(0xFFFFC36A)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _panelHeader(String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 15, color: const Color(0xFFA9B5FF)),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
        ],
      ),
    );
  }

  IconData _iconFor(LayerKind kind) => switch (kind) {
        LayerKind.video => Icons.movie,
        LayerKind.image => Icons.image,
        LayerKind.photoshopLayer => Icons.layers,
        LayerKind.text => Icons.text_fields,
        LayerKind.shape => Icons.category,
        LayerKind.audio => Icons.graphic_eq,
        LayerKind.nullObject => Icons.control_camera,
        LayerKind.adjustment => Icons.tune,
        LayerKind.camera => Icons.videocam,
        LayerKind.light => Icons.lightbulb,
        LayerKind.threeDModel => Icons.view_in_ar,
        LayerKind.particle => Icons.auto_awesome,
        LayerKind.precomposition => Icons.layers_outlined,
      };
}

class _ShapeLayerPainter extends CustomPainter {
  const _ShapeLayerPainter(this.style);

  final ShapeStyle style;

  Color _color(String value) {
    final normalized = value.replaceFirst('#', '');
    final parsed = int.tryParse(normalized, radix: 16) ?? 0x7C8CFF;
    return Color(0xFF000000 | parsed);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    switch (style.primitive) {
      case ShapePrimitive.rectangle:
        path.addRect(Offset.zero & size);
        break;
      case ShapePrimitive.roundedRectangle:
        path.addRRect(
          RRect.fromRectAndRadius(
            Offset.zero & size,
            Radius.circular(style.cornerRadius),
          ),
        );
        break;
      case ShapePrimitive.ellipse:
        path.addOval(Offset.zero & size);
        break;
      case ShapePrimitive.polygon:
      case ShapePrimitive.star:
        final count = style.primitive == ShapePrimitive.star
            ? (style.points.clamp(3, 24) * 2)
            : style.points.clamp(3, 24);
        final center = Offset(size.width / 2, size.height / 2);
        final radius = math.min(size.width, size.height) / 2;
        for (var index = 0; index < count; index++) {
          final starInner = style.primitive == ShapePrimitive.star && index.isOdd;
          final pointRadius = starInner ? radius * 0.42 : radius;
          final angle = -math.pi / 2 + index * math.pi * 2 / count;
          final point = Offset(
            center.dx + math.cos(angle) * pointRadius,
            center.dy + math.sin(angle) * pointRadius,
          );
          if (index == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        path.close();
        break;
      case ShapePrimitive.path:
        path.addRect(Offset.zero & size);
        break;
    }

    if (style.fillColor.toLowerCase() != 'transparent') {
      canvas.drawPath(path, Paint()..color = _color(style.fillColor));
    }
    if (style.strokeWidth > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = style.strokeWidth
          ..color = _color(style.strokeColor),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ShapeLayerPainter oldDelegate) =>
      oldDelegate.style != style;
}

class _CanvasGridPainter extends CustomPainter {
  const _CanvasGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF263249)
      ..strokeWidth = 0.5;
    const step = 24.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasGridPainter oldDelegate) => false;
}


/// Interactive cubic Bezier graph used by the keyframe interpolation editor.
class _BezierCurveEditor extends StatefulWidget {
  const _BezierCurveEditor({
    required this.curve,
    required this.onChanged,
  });

  final BezierCurve curve;
  final ValueChanged<BezierCurve> onChanged;

  @override
  State<_BezierCurveEditor> createState() => _BezierCurveEditorState();
}

class _BezierCurveEditorState extends State<_BezierCurveEditor> {
  int _activeHandle = 1;

  Rect _plotRect(Size size) =>
      Rect.fromLTWH(24, 12, size.width - 48, size.height - 36);

  Offset _handlePoint(BezierCurve curve, Rect plot, int handle) {
    final x = handle == 1 ? curve.x1 : curve.x2;
    final y = handle == 1 ? curve.y1 : curve.y2;
    return Offset(plot.left + x * plot.width, plot.bottom - y * plot.height);
  }

  void _beginDrag(Offset position, Size size) {
    final plot = _plotRect(size);
    final first = _handlePoint(widget.curve, plot, 1);
    final second = _handlePoint(widget.curve, plot, 2);
    _activeHandle =
        (position - first).distance <= (position - second).distance ? 1 : 2;
  }

  void _updateDrag(Offset position, Size size) {
    final plot = _plotRect(size);
    final x = ((position.dx - plot.left) / plot.width)
        .clamp(0.0, 1.0)
        .toDouble();
    final y = (1 - (position.dy - plot.top) / plot.height)
        .clamp(0.0, 1.0)
        .toDouble();
    final current = widget.curve;
    widget.onChanged(
      _activeHandle == 1
          ? BezierCurve(x1: x, y1: y, x2: current.x2, y2: current.y2)
          : BezierCurve(x1: current.x1, y1: current.y1, x2: x, y2: y),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 320,
        height: 190,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) =>
                  _beginDrag(details.localPosition, size),
              onPanUpdate: (details) =>
                  _updateDrag(details.localPosition, size),
              child: CustomPaint(
                painter: _BezierCurveGraphPainter(widget.curve),
                size: size,
              ),
            );
          },
        ),
      );
}

class _BezierCurveGraphPainter extends CustomPainter {
  const _BezierCurveGraphPainter(this.curve);

  final BezierCurve curve;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTWH(24, 12, size.width - 48, size.height - 36);
    final background = Paint()..color = const Color(0xFF101827);
    canvas.drawRRect(
      RRect.fromRectAndRadius(plot, const Radius.circular(8)),
      background,
    );

    final grid = Paint()
      ..color = const Color(0xFF2A3850)
      ..strokeWidth = 0.8;
    for (var index = 0; index <= 4; index++) {
      final x = plot.left + plot.width * index / 4;
      final y = plot.top + plot.height * index / 4;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }

    Offset point(double x, double y) =>
        Offset(plot.left + x * plot.width, plot.bottom - y * plot.height);
    final start = point(0, 0);
    final end = point(1, 1);
    final first = point(
      curve.x1.clamp(0.0, 1.0).toDouble(),
      curve.y1.clamp(0.0, 1.0).toDouble(),
    );
    final second = point(
      curve.x2.clamp(0.0, 1.0).toDouble(),
      curve.y2.clamp(0.0, 1.0).toDouble(),
    );

    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = const Color(0xFF64748B)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );
    canvas.drawLine(
      start,
      first,
      Paint()
        ..color = const Color(0xFF7C8CFF)
        ..strokeWidth = 1.5,
    );
    canvas.drawLine(
      end,
      second,
      Paint()
        ..color = const Color(0xFF37D6C0)
        ..strokeWidth = 1.5,
    );

    final curvePath = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(first.dx, first.dy, second.dx, second.dy, end.dx, end.dy);
    canvas.drawPath(
      curvePath,
      Paint()
        ..color = const Color(0xFFB6A5FF)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(start, 4, Paint()..color = const Color(0xFFE2E8F0));
    canvas.drawCircle(end, 4, Paint()..color = const Color(0xFFE2E8F0));
    canvas.drawCircle(first, 7, Paint()..color = const Color(0xFF7C8CFF));
    canvas.drawCircle(second, 7, Paint()..color = const Color(0xFF37D6C0));
  }

  @override
  bool shouldRepaint(covariant _BezierCurveGraphPainter oldDelegate) =>
      oldDelegate.curve.x1 != curve.x1 ||
      oldDelegate.curve.y1 != curve.y1 ||
      oldDelegate.curve.x2 != curve.x2 ||
      oldDelegate.curve.y2 != curve.y2;
}
