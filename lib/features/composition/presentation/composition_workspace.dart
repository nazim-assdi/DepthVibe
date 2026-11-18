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
import '../engine/composition_export_service.dart';

class CompositionWorkspace extends StatefulWidget {
  const CompositionWorkspace({super.key});

  @override
  State<CompositionWorkspace> createState() => _CompositionWorkspaceState();
}

class _CompositionWorkspaceState extends State<CompositionWorkspace> {
  final CompositionController _controller = CompositionController();
  final PhotoshopImportService _photoshop = const PhotoshopImportService();
  final CompositionExportService _exporter = const CompositionExportService();
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
            'Imported ${document.visibleLayerCount} editable raster layers from ${document.width}×${document.height} Photoshop document';
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
                return ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: const Color(0xFF263553),
                  leading: Icon(_iconFor(layer.kind), size: 17),
                  title: Text(layer.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                  subtitle: Text(layer.parentId == null ? layer.kind.name : 'Parent: ${layer.parentId}', maxLines: 1, style: const TextStyle(fontSize: 9)),
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
    final x = resolved.position.x;
    final y = resolved.position.y;
    final scaleX = resolved.scale.x / 100;
    final scaleY = resolved.scale.y / 100;
    final rotation = resolved.rotation.z * math.pi / 180;
    final opacity = (resolved.opacity / 100).clamp(0, 1).toDouble();

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
        visual = const Icon(Icons.layers_outlined, color: Color(0xFFB3BEFF), size: 32);
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
                for (final panel in const ['Layers', 'Transform', 'Shape', 'Effects', 'Masks', 'Audio', 'Parent', '3D'])
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
                ? const Center(child: Text('Select a layer to edit'))
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
      case 'Transform':
        return _buildTransformPanel(layer);
      case 'Shape':
        return _buildShapePanel(layer);
      case 'Effects':
        return _buildEffectsPanel(layer);
      case 'Masks':
        return _buildMasksPanel(layer);
      case 'Audio':
        return _buildAudioPanel(layer);
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
    final track = layer.keyframeTracks.where((item) => item.property == property);
    final keyframes = track.isEmpty ? 0 : track.first.keyframes.length;
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
              icon: Icon(Icons.diamond, size: 16, color: keyframes > 0 ? const Color(0xFFB6A5FF) : const Color(0xFF8A98B0)),
            ),
            SizedBox(
              width: 54,
              child: Text(value.toStringAsFixed(1), textAlign: TextAlign.end, style: const TextStyle(fontSize: 10)),
            ),
          ],
        ),
        Slider(
          min: min,
          max: max,
          value: value.clamp(min, max).toDouble(),
          onChanged: (next) {
            _controller.setTransformValue(property, next);
          },
          onChangeEnd: (next) {
            if (keyframes > 0) _controller.setTransformValue(property, next, keyframe: true);
          },
        ),
      ],
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
        _settingSlider('Pan', audio.pan, -1, 1,
            (value) => _controller.setAudioSettings(audio.copyWith(pan: value))),
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
                  _settingSlider('Feather', mask.feather, 0, 200,
                      (value) => _controller.setMaskParameters(mask.id, feather: value)),
                  _settingSlider('Expansion', mask.expansion, -100, 100,
                      (value) => _controller.setMaskParameters(mask.id, expansion: value)),
                  _settingSlider('Left', mask.left, 0, (1 - mask.width).clamp(0, 1),
                      (value) => _controller.setMaskParameters(mask.id, left: value)),
                  _settingSlider('Top', mask.top, 0, (1 - mask.height).clamp(0, 1),
                      (value) => _controller.setMaskParameters(mask.id, top: value)),
                  _settingSlider('Width', mask.width, 0.01, (1 - mask.left).clamp(0.01, 1),
                      (value) => _controller.setMaskParameters(mask.id, width: value)),
                  _settingSlider('Height', mask.height, 0.01, (1 - mask.top).clamp(0.01, 1),
                      (value) => _controller.setMaskParameters(mask.id, height: value)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Invert mask', style: TextStyle(fontSize: 10)),
                    value: mask.inverted,
                    onChanged: (value) => _controller.setMaskParameters(mask.id, inverted: value),
                  ),
                ],
              ),
            ),
          ),
        const Text(
          'Rectangle, ellipse and polygon alpha masks with position, size, feather, expansion and boolean operations are rendered in the compositor.',
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Depth of Field', style: TextStyle(fontSize: 11)),
            value: camera.depthOfField,
            onChanged: (value) => _controller.setCameraSettings(
              camera.copyWith(depthOfField: value),
            ),
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
        const Text('Camera, light, null and GLB/3D model transforms share the same keyframe system.', style: TextStyle(fontSize: 11)),
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
              const Text('ANIMATION TIMELINE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
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
                final count = layer.keyframeTracks.fold<int>(
                      0,
                      (sum, track) => sum + track.keyframes.length,
                    ) +
                    layer.effects.fold<int>(
                      0,
                      (sum, effect) => sum +
                          effect.keyframeTracks.fold<int>(
                            0,
                            (trackSum, track) => trackSum + track.keyframes.length,
                          ),
                    );
                return InkWell(
                  onTap: () => _controller.selectLayer(layer.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(width: 130, child: Text(layer.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10))),
                        Expanded(
                          child: Container(
                            height: 22,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1D2A41),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Stack(
                              children: [
                                for (final track in layer.keyframeTracks)
                                  for (final keyframe in track.keyframes)
                                    Positioned(
                                      left: (keyframe.timeMs / duration) * 500,
                                      top: 3,
                                      child: const Icon(Icons.diamond, size: 14, color: Color(0xFFB8A4FF)),
                                    ),
                                Positioned(
                                  right: 6,
                                  top: 4,
                                  child: Text('$count kf', style: const TextStyle(fontSize: 9, color: Color(0xFFB7C5DE))),
                                ),
                              ],
                            ),
                          ),
                        ),
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
