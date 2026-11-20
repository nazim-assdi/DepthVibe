import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/depthvibe_brand_mark.dart';
import '../../../app/depthvibe_settings.dart';
import '../../../app/depthvibe_settings_dialog.dart';
import '../application/composition_controller.dart';
import '../../fonts/data/font_manager_service.dart';
import '../../fonts/presentation/font_manager_dialog.dart';
import '../../fonts/presentation/font_picker_dialog.dart';
import '../data/effect_catalog.dart';
import '../../extensions/data/extension_manager_service.dart';
import '../../extensions/data/adobe_bridge_service.dart';
import '../data/photoshop_import_service.dart';
import '../domain/composition_models.dart';
import '../data/motion_preset_catalog.dart';
import '../data/motion_preset_package.dart';
import '../data/transition_catalog.dart';
import '../domain/color_grade_preset.dart';
import '../engine/parent_transform_resolver.dart';
import '../engine/camera_projection_resolver.dart';
import '../engine/composition_export_service.dart';
import '../engine/composition_project_service.dart';
import '../engine/composition_recovery_service.dart';
import '../engine/obj_mesh_loader.dart';
import '../engine/scene_mesh_loader.dart';
import '../engine/software_3d_renderer.dart';
import '../engine/gpu_3d_mesh_view.dart';
import '../engine/audio_waveform_service.dart';
import '../engine/color_grade_preview.dart';
import '../engine/cube_lut_validator.dart';
import '../engine/motion_tracking_service.dart';
import '../engine/transition_frame_validator.dart';
import 'text_layer_content_editor.dart';
import 'color_wheel_control.dart';
import 'color_curve_editor.dart';
import 'color_scopes_view.dart';

class CompositionWorkspace extends StatefulWidget {
  const CompositionWorkspace({super.key});

  @override
  State<CompositionWorkspace> createState() => _CompositionWorkspaceState();
}

class _CompositionWorkspaceState extends State<CompositionWorkspace>
    with WidgetsBindingObserver {
  final CompositionController _controller = CompositionController();
  final PhotoshopImportService _photoshop = const PhotoshopImportService();
  final CompositionExportService _exporter = const CompositionExportService();
  final MotionTrackingService _tracker = const MotionTrackingService();
  final AudioWaveformService _waveformService = const AudioWaveformService();
  final Map<String, Future<File?>> _waveformJobs = {};
  final Map<String, Future<File?>> _videoFrameJobs = {};
  final Map<String, Future<img.Image?>> _scopeImageJobs = {};
  final Map<String, Future<ObjMesh>> _meshJobs = {};
  String _curveChannel = 'master';

  Future<File?> _waveformFor(String path) =>
      _waveformJobs.putIfAbsent(path, () => _waveformService.generate(path));

  Future<ObjMesh> _meshFor(String path) =>
      _meshJobs.putIfAbsent(path, () => const SceneMeshLoader().load(path));

  String _quoteFfmpeg(String value) =>
      "'" + value.replaceAll("'", "'\\''") + "'";

  Future<File?> _videoFrameFor(
    CompositionLayer layer,
    int timelineTimeMs,
    double frameRate,
  ) {
    final path = layer.sourceUri;
    if (path == null || path.isEmpty || frameRate <= 0) {
      return Future<File?>.value(null);
    }
    final sourceTimeMs = math.max(
      0,
      layer.sourceInMs + timelineTimeMs - layer.startMs,
    );
    final frameIndex = (sourceTimeMs * frameRate / 1000).floor();
    final seekMs = (frameIndex * 1000 / frameRate).round();
    final key = '${path}_${frameIndex}_${frameRate.toStringAsFixed(3)}';
    final frameJob = _videoFrameJobs.putIfAbsent(key, () async {
      if (!await File(path).exists()) return null;
      final temporary = await getTemporaryDirectory();
      final frame = File(
        temporary.path + Platform.pathSeparator +
            'depthvibe_preview_${key.hashCode.toUnsigned(32).toRadixString(16)}.png',
      );
      if (await frame.exists() && await frame.length() > 0) return frame;
      final command = '-hide_banner -loglevel error -y -ss ' +
          (seekMs / 1000).toStringAsFixed(3) +
          ' -i ' + _quoteFfmpeg(path) +
          ' -frames:v 1 -vf scale=960:540:force_original_aspect_ratio=decrease,'
          'pad=960:540:(ow-iw)/2:(oh-ih)/2 -an ' +
          _quoteFfmpeg(frame.path);
      final session = await FFmpegKit.executeAsync(command).timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          final activeSessions = FFmpegKit.getFFmpegSessions()
              .where((running) => running.getCommand().contains(frame.path))
              .toList();
          for (final running in activeSessions) {
            running.cancel();
          }
          throw TimeoutException(
            'Decoding the current color preview frame exceeded 12 seconds.',
          );
        },
      );
      if (!ReturnCode.isSuccess(session.getReturnCode()) ||
          !await frame.exists() ||
          await frame.length() == 0) {
        return null;
      }
      return frame;
    });
    return frameJob.then(
      (frame) {
        if (frame == null) _videoFrameJobs.remove(key);
        return frame;
      },
      onError: (Object error, StackTrace stackTrace) {
        _videoFrameJobs.remove(key);
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

  Future<img.Image?> _scopeImageFor(
    CompositionLayer layer,
    int timelineTimeMs,
    double frameRate,
  ) {
    final path = layer.sourceUri;
    if (path == null || path.isEmpty) return Future<img.Image?>.value(null);
    final frame = layer.kind == LayerKind.video
        ? (timelineTimeMs < layer.startMs || timelineTimeMs >= layer.endMs
            ? -1
            : ((layer.sourceInMs + timelineTimeMs - layer.startMs) *
                    frameRate /
                    1000)
                .floor())
        : 0;
    final key = '${path}_scope_${frame}_${frameRate.toStringAsFixed(3)}';
    return _scopeImageJobs.putIfAbsent(key, () async {
      File? source;
      if (layer.kind == LayerKind.video) {
        if (frame < 0) return null;
        source = await _videoFrameFor(layer, timelineTimeMs, frameRate);
      } else {
        source = File(path);
      }
      if (source == null || !await source.exists()) return null;
      return img.decodeImage(await source.readAsBytes());
    });
  }

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
  final CompositionProjectService _projectService = const CompositionProjectService();
  final CompositionRecoveryService _recoveryService = const CompositionRecoveryService();
  bool _projectBusy = false;
  bool _recoverySaving = false;
  bool _recoveryDirty = false;
  int _documentRevision = 0;
  Timer? _recoveryTimer;
  File? _currentProjectFile;
  String _autosaveStatus = 'Autosave ready';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onCompositionChanged);
    ExtensionManagerService.instance.addListener(_onExtensionsChanged);
    AdobeBridgeService.instance.attachController(_controller);
    _recoveryTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _autosaveIfNeeded(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForCrashRecovery());
    });
  }

  void _onExtensionsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openSettings() => DepthVibeSettingsDialog.show(context);

  Future<void> _openFontManager() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const FontManagerDialog(),
    );
    if (mounted) setState(() {});
  }

  Future<void> _chooseLayerFont(CompositionLayer layer) async {
    final font = await FontPickerDialog.show(
      context,
      currentFamily: layer.textFontFamily,
    );
    if (!mounted || font == null) return;
    await _applyLayerFont(font);
  }

  int _fontWeightForStyle(String? style) =>
      FontManagerService.suggestedWeight(style);

  Future<void> _applyLayerFont(FontCatalogEntry? font) async {
    if (font == null) {
      _controller.updateTextLayer(clearTextFont: true);
      return;
    }
    try {
      if (font.isImported) {
        await FontManagerService.instance.ensureFontLoaded(
          family: font.family,
          path: font.path,
        );
      }
      final styleName = (font.styleName ?? '').toLowerCase();
      _controller.updateTextLayer(
        textFontFamily: font.family,
        textFontAssetUri: font.isImported ? font.path : null,
        clearTextFontAsset: !font.isImported,
        textFontWeight: _fontWeightForStyle(font.styleName),
        textItalic: FontManagerService.isItalicStyle(styleName),
      );
    } catch (error) {
      if (mounted) setState(() => _notice = 'Font could not be loaded: $error');
    }
  }

  void _onCompositionChanged() {
    _documentRevision++;
    _recoveryDirty = true;
    _autosaveStatus = 'Unsaved changes';
    final layer = _controller.selectedLayer;
    if (layer != null && layer.kind == LayerKind.text &&
        layer.textFontFamily != null && layer.textFontAssetUri != null) {
      unawaited(FontManagerService.instance.ensureFontsLoaded(
        family: layer.textFontFamily,
        path: layer.textFontAssetUri,
        fallbackFamilies: [
          ...layer.textFontFallback,
          ...FontManagerService.instance.fallbackFamilies,
        ],
      ).then<void>(
        (_) { if (mounted) setState(() {}); },
        onError: (Object _) {},
      ));
    }
  }

  Future<Directory> _recoveryDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(
      documents.path + Platform.pathSeparator +
          'DepthVibe' + Platform.pathSeparator + 'Recovery',
    );
  }

  Future<void> _autosaveIfNeeded() async {
    if (_recoverySaving ||
        !_recoveryDirty ||
        _projectBusy ||
        _rendering) {
      return;
    }
    _recoverySaving = true;
    final revision = _documentRevision;
    final snapshot = _controller.document;
    try {
      final directory = await _recoveryDirectory();
      await _recoveryService.save(snapshot, recoveryDirectory: directory);
      if (revision == _documentRevision) {
        _recoveryDirty = false;
        _autosaveStatus = 'Autosaved ' + DateTime.now().toLocal().toString();
        if (mounted) setState(() {});
      }
    } catch (error) {
      _autosaveStatus = 'Autosave failed';
      if (mounted) {
        setState(() => _notice = 'Autosave failed: ' + error.toString());
      }
    } finally {
      _recoverySaving = false;
    }
  }

  Future<void> _checkForCrashRecovery() async {
    try {
      final directory = await _recoveryDirectory();
      final snapshot = await _recoveryService.load(
        recoveryDirectory: directory,
      );
      if (snapshot == null || !mounted) return;
      final recover = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('RECOVER UNSAVED PROJECT?'),
          content: Text(
            'DepthVibe found an autosave from ' +
                snapshot.savedAt.toLocal().toString() +
                '. Restore ' + snapshot.document.name +
                ' with ' + snapshot.document.layers.length.toString() +
                ' layers?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('DISCARD'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('RECOVER PROJECT'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (recover == true) {
        _controller.replaceDocument(snapshot.document);
        _recoveryDirty = false;
        _currentProjectFile = null;
        _autosaveStatus = 'Recovered unsaved project';
        setState(() {
          _notice = 'Recovered "' + snapshot.document.name +
              '" from crash-recovery autosave. Save a .dvproj copy to keep it portable.';
        });
      } else {
        await _recoveryService.clear(recoveryDirectory: directory);
        _recoveryDirty = false;
        _autosaveStatus = 'Recovery discarded';
      }
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Crash recovery could not be opened: ' +
            error.toString());
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_autosaveIfNeeded());
    }
  }

  String _localAssetPath(String path) {
    if (path.toLowerCase().startsWith('file://')) {
      try {
        return Uri.parse(path).toFilePath();
      } on FormatException {
        return path;
      }
    }
    return path;
  }

  Future<List<String>> _missingMediaPaths() async {
    final candidates = <String>{};
    for (final layer in _controller.document.layers) {
      for (final path in [
        layer.sourceUri,
        layer.sourceDocumentUri,
        layer.smartObjectSourceUri,
        for (final effect in layer.effects) effect.assetUri,
      ]) {
        if (path != null &&
            path.isNotEmpty &&
            !path.startsWith('http://') &&
            !path.startsWith('https://')) {
          candidates.add(path);
        }
      }
    }
    final missing = <String>[];
    for (final path in candidates) {
      if (!await File(_localAssetPath(path)).exists()) missing.add(path);
    }
    missing.sort();
    return missing;
  }

  Future<void> _relinkMissingMedia() async {
    if (_projectBusy || _rendering) return;
    final missing = await _missingMediaPaths();
    if (missing.isEmpty) {
      if (mounted) setState(() => _notice = 'All local media references are available.');
      return;
    }

    var relinked = 0;
    try {
      for (final oldPath in missing) {
        if (!mounted) return;
        setState(() {
          _projectBusy = true;
          _notice = 'Relink ' + (relinked + 1).toString() +
              ' of ' + missing.length.toString() + ': ' + oldPath;
        });
        final picked = await FilePicker.pickFile(type: FileType.any);
        if (picked == null) break;
        final pickedPath = picked.path;
        if (pickedPath == null || pickedPath.isEmpty) {
          throw StateError('The selected replacement file has no local path.');
        }
        final source = File(pickedPath);
        if (!await source.exists()) {
          throw StateError('The selected replacement file does not exist.');
        }

        final documents = await getApplicationDocumentsDirectory();
        final targetDirectory = Directory(
          documents.path + Platform.pathSeparator +
              'DepthVibe' + Platform.pathSeparator + 'RelinkedAssets',
        );
        await targetDirectory.create(recursive: true);
        final originalName = picked.name.replaceAll(
          RegExp(r'[^A-Za-z0-9._-]'),
          '_',
        );
        final safeName = originalName.isEmpty ? 'media.bin' : originalName;
        final destination = File(
          targetDirectory.path + Platform.pathSeparator +
              DateTime.now().microsecondsSinceEpoch.toString() +
              '_' + safeName,
        );
        final copied = await source.copy(destination.path);
        _controller.relinkAssetReference(oldPath, copied.path);
        relinked++;
      }
      if (mounted) {
        setState(() {
          _notice = 'Relinked ' + relinked.toString() + ' of ' +
              missing.length.toString() + ' missing media references.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Media relink failed: ' + error.toString());
      }
    } finally {
      if (mounted) setState(() => _projectBusy = false);
    }
  }

  Future<void> _showProjectVersionHistory() async {
    final projectFile = _currentProjectFile;
    if (projectFile == null) {
      setState(() => _notice = 'Save this composition as a .dvproj first to create version history.');
      return;
    }
    try {
      final versions = await _projectService.listProjectVersions(projectFile);
      if (!mounted) return;
      if (versions.isEmpty) {
        setState(() => _notice = 'No previous project versions have been saved yet.');
        return;
      }
      final selected = await showDialog<CompositionProjectVersion>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('PROJECT VERSION HISTORY'),
          content: SizedBox(
            width: 460,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final version in versions)
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(version.modifiedAt.toLocal().toString()),
                    subtitle: Text(
                      (version.sizeBytes / (1024 * 1024)).toStringAsFixed(1) +
                          ' MB · ' + version.file.uri.pathSegments.last,
                    ),
                    onTap: () => Navigator.of(dialogContext).pop(version),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('CLOSE'),
            ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('RESTORE THIS VERSION?'),
          content: const Text(
            'The selected version will replace the current composition. Save the current state first if you need to keep it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('RESTORE'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() {
        _projectBusy = true;
        _notice = 'Restoring project version…';
      });
      final documents = await getApplicationDocumentsDirectory();
      final imported = await _projectService.importProject(
        selected.file,
        projectsDirectory: Directory(
          documents.path + Platform.pathSeparator +
              'DepthVibe' + Platform.pathSeparator + 'Projects' +
              Platform.pathSeparator + 'HistoryRestores',
        ),
      );
      _controller.replaceDocument(imported.document);
      final recovery = await _recoveryDirectory();
      await _recoveryService.clear(recoveryDirectory: recovery);
      _recoveryDirty = true;
      if (mounted) {
        setState(() {
          _currentProjectFile = projectFile;
          _notice = 'Restored version of "' + imported.document.name + '".';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Version restore failed: ' + error.toString());
      }
    } finally {
      if (mounted) setState(() => _projectBusy = false);
    }
  }


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
        kind == LayerKind.audio ||
        kind == LayerKind.threeDModel) {
      final file = kind == LayerKind.threeDModel
          ? await FilePicker.pickFile(
              type: FileType.custom,
              allowedExtensions: const ['obj', 'gltf', 'glb'],
            )
          : await FilePicker.pickFile(
              type: switch (kind) {
                LayerKind.video => FileType.video,
                LayerKind.audio => FileType.audio,
                _ => FileType.image,
              },
            );
      if (file == null) return;
      final sourcePath = file.path;
      if (sourcePath == null) {
        setState(() => _notice = 'This provider did not expose a local file path.');
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
        LayerKind.text => 'Typography',
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
    _recoveryTimer?.cancel();
    _controller.removeListener(_onCompositionChanged);
    ExtensionManagerService.instance.removeListener(_onExtensionsChanged);
    AdobeBridgeService.instance.detachController(_controller);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_autosaveIfNeeded());
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
        final palette = Theme.of(context).extension<DepthVibePalette>()!;
        return Scaffold(
          appBar: AppBar(
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DepthVibeBrandMark(size: 34),
                SizedBox(width: 14),
                Text(
                  'COMPOSITOR',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.15,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Settings · View and appearance',
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
              IconButton(
                tooltip: 'Undo',
                onPressed: _controller.canUndo ? _controller.undo : null,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: 'Redo',
                onPressed: _controller.canRedo ? _controller.redo : null,
                icon: const Icon(Icons.redo),
              ),
              IconButton(
                tooltip: 'Open .dvproj project',
                onPressed: _projectBusy || _rendering
                    ? null
                    : _openCompositionProject,
                icon: const Icon(Icons.folder_open_outlined),
              ),
              IconButton(
                tooltip: 'Save complete .dvproj project',
                onPressed: _projectBusy || _rendering
                    ? null
                    : _saveCompositionProject,
                icon: const Icon(Icons.save_alt),
              ),
              IconButton(
                tooltip: 'Autosave now · $_autosaveStatus',
                onPressed: _projectBusy || _rendering
                    ? null
                    : () => _autosaveIfNeeded(),
                icon: const Icon(Icons.cloud_done_outlined),
              ),
              IconButton(
                tooltip: 'Project version history',
                onPressed: _projectBusy || _rendering
                    ? null
                    : _showProjectVersionHistory,
                icon: const Icon(Icons.history),
              ),
              IconButton(
                tooltip: 'Relink missing media',
                onPressed: _projectBusy || _rendering
                    ? null
                    : _relinkMissingMedia,
                icon: const Icon(Icons.link),
              ),
              IconButton(
                tooltip: 'Open global Font Manager',
                onPressed: _openFontManager,
                icon: const Icon(Icons.font_download_outlined),
              ),
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
              if (_rendering || _projectBusy)
                LinearProgressIndicator(
                  value: _rendering && _renderProgress != 0
                      ? _renderProgress
                      : null,
                ),
              if (_notice != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  color: palette.toolbar,
                  child: Text(_notice!, style: TextStyle(fontSize: 11, color: palette.secondaryText)),
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
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return Container(
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(right: BorderSide(color: palette.border)),
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
                  selectedTileColor: palette.accentSoft,
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
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return Container(
      color: palette.appBackground,
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
    if (layer.kind == LayerKind.video &&
        (timeMs < layer.startMs || timeMs >= layer.endMs)) {
      return const SizedBox.shrink();
    }
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
        visual = FutureBuilder<File?>(
          future: _videoFrameFor(layer, timeMs, doc.frameRate),
          builder: (context, snapshot) {
            final frame = snapshot.data;
            if (frame != null) {
              return Image.file(
                frame,
                fit: BoxFit.fill,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_outlined),
                ),
              );
            }
            return Center(
              child: snapshot.connectionState == ConnectionState.waiting
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : const Icon(
                      Icons.movie_outlined,
                      color: Color(0xFFB3BEFF),
                      size: 36,
                    ),
            );
          },
        );
        break;
      case LayerKind.shape:
        visual = CustomPaint(
          painter: _ShapeLayerPainter(layer.shapeStyle ?? const ShapeStyle()),
        );
        break;
      case LayerKind.text:
        baseWidth = layer.textBoxWidth;
        final content = layer.textContent ?? layer.name;
        final approximateCharactersPerLine =
            (baseWidth / (layer.textFontSize * 0.52))
                .floor()
                .clamp(1, 5000)
                .toInt();
        final estimatedLines = content.split('\n').fold<int>(
          0,
          (count, line) => count +
              math.max(1, (line.length / approximateCharactersPerLine).ceil()).toInt(),
        );
        baseHeight = math.max(
          180.0,
          estimatedLines * layer.textFontSize * layer.textLineHeight + 24,
        ).toDouble();
        final fontScale = canvasSize.width / doc.width;
        final weightIndex = ((layer.textFontWeight.clamp(100, 900) / 100)
                    .round() - 1)
                .clamp(0, 8)
                .toInt();
        final rawColor = layer.textColor.replaceFirst('#', '');
        final parsedColor = int.tryParse(rawColor, radix: 16);
        final textColor = parsedColor == null
            ? Colors.white
            : Color(rawColor.length == 6 ? 0xFF000000 | parsedColor : parsedColor);
        final textAlign = switch (layer.textAlign) {
          'center' => TextAlign.center,
          'right' => TextAlign.right,
          'justify' => TextAlign.justify,
          _ => TextAlign.left,
        };
        final textDirection = RegExp(r'[\u0590-\u08FF\uFB1D-\uFEFF]')
                .hasMatch(content)
            ? TextDirection.rtl
            : TextDirection.ltr;
        visual = Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: baseWidth * fontScale,
            child: Text(
              content,
              textAlign: textAlign,
              textDirection: textDirection,
              softWrap: true,
              style: TextStyle(
                color: textColor,
                fontFamily: layer.textFontFamily ?? FontManagerService.instance.activeFamily,
                fontFamilyFallback: [
                  ...layer.textFontFallback,
                  ...FontManagerService.instance.fallbackFamilies,
                ],
                fontSize: layer.textFontSize * fontScale,
                fontWeight: FontWeight.values[weightIndex],
                fontStyle: layer.textItalic ? FontStyle.italic : FontStyle.normal,
                letterSpacing: layer.textLetterSpacing * fontScale,
                height: layer.textLineHeight,
                shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
              ),
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
        baseWidth = 760;
        baseHeight = 760;
        if (layer.sourceUri == null) {
          visual = const Center(
            child: Icon(Icons.view_in_ar, color: Color(0xFF9DE1D3), size: 54),
          );
        } else {
          final meshCamera = cameraTransform != null && cameraTransform.enabled
              ? cameraTransform
              : const ResolvedLayerTransform(
                  position: Vector3(0, 0, 0),
                  scale: Vector3(100, 100, 100),
                  rotation: Vector3(0, 0, 0),
                  opacity: 100,
                  enabled: true,
                );
          final meshCameraSettings = cameraTransform != null && cameraTransform.enabled
              ? cameraLayer?.camera ?? const CameraSettings()
              : const CameraSettings();
          final meshLights = <SceneLight>[
            for (final item in doc.layers.where(
              (candidate) => candidate.kind == LayerKind.light && candidate.enabled,
            ))
              SceneLight(
                transform: const ParentTransformResolver().resolve(
                  layer: item,
                  timeMs: timeMs,
                  layers: doc.layers,
                ),
                settings: item.light ?? const LightSettings(),
              ),
          ];
          visual = FutureBuilder<ObjMesh>(
            future: _meshFor(layer.sourceUri!),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: Color(0xFFFF8E8E), size: 38),
                );
              }
              final mesh = snapshot.data;
              if (mesh == null) {
                return const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              return Gpu3dMeshView(
                mesh: mesh,
                timeMs: math.max(0, timeMs - layer.startMs).toInt(),
                animationIndex: layer.modelAnimationIndex,
                baseWidth: baseWidth,
                baseHeight: baseHeight,
                modelTransform: resolved,
                cameraTransform: meshCamera,
                cameraSettings: meshCameraSettings,
                lights: meshLights,
                compositionWidth: doc.width.toDouble(),
                compositionHeight: doc.height.toDouble(),
              );
            },
          );
        }
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

    final isMeshLayer = layer.kind == LayerKind.threeDModel;
    final meshCameraScaleX = projected != null && resolved.scale.x.abs() > 0.0001
        ? projected.scale.x.abs() / resolved.scale.x.abs()
        : 1.0;
    final meshCameraScaleY = projected != null && resolved.scale.y.abs() > 0.0001
        ? projected.scale.y.abs() / resolved.scale.y.abs()
        : 1.0;
    final width = baseWidth *
        (isMeshLayer ? meshCameraScaleX : scaleX.abs()) /
        doc.width * canvasSize.width;
    final height = baseHeight *
        (isMeshLayer ? meshCameraScaleY : scaleY.abs()) /
        doc.height * canvasSize.height;
    final left = x / doc.width * canvasSize.width - width / 2;
    final top = y / doc.height * canvasSize.height - height / 2;

    final activeMasks = layer.masks.where((mask) => mask.enabled).toList();
    final maskedVisual = activeMasks.isEmpty
        ? visual
        : ClipPath(
            clipper: _AnimatedMaskClipper(
              masks: activeMasks,
              timeMs: timeMs,
            ),
            child: visual,
          );
    final gradeEffect = layer.effects
        .where((effect) => effect.effectId == 'color_grade')
        .firstOrNull;
    final gradeFilter = ColorGradePreview.filterFor(gradeEffect, timeMs);
    final gradedVisual = gradeFilter == null
        ? maskedVisual
        : ColorFiltered(colorFilter: gradeFilter, child: maskedVisual);

    return Positioned(
      left: left,
      top: top,
      width: width.clamp(1, canvasSize.width * 4).toDouble(),
      height: height.clamp(1, canvasSize.height * 4).toDouble(),
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: isMeshLayer ? 0 : rotation,
          child: Transform.scale(
            scaleX: isMeshLayer ? 1 : (scaleX.isNegative ? -1 : 1),
            scaleY: isMeshLayer ? 1 : (scaleY.isNegative ? -1 : 1),
            child: gradedVisual,
          ),
        ),
      ),
    );
  }

  Widget _toolChip(String label, IconData icon, bool active, {VoidCallback? onTap}) {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return ActionChip(
      avatar: Icon(icon, size: 14),
      label: Text(label),
      onPressed: onTap ?? () => setState(() => _notice = '$label tool selected'),
      backgroundColor: active ? palette.accentSoft : palette.panelRaised,
      side: BorderSide(color: active ? palette.accent : palette.border),
      labelStyle: TextStyle(color: palette.primaryText, fontWeight: FontWeight.w700),
    );
  }

  Widget _buildActivePanel(CompositionLayer? layer) {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return Container(
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(left: BorderSide(color: palette.border)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final panel in const ['Layers', 'Typography', 'Timing', 'Transform', 'Color', 'Animation', 'Shape', 'Effects', 'Masks', 'Audio', 'Bus Mixer', 'Tracking', 'Transitions', 'Parent', '3D'])
                  TextButton(
                    onPressed: () => setState(() => _panel = panel),
                    child: Text(panel, style: TextStyle(fontSize: 10, fontWeight: _panel == panel ? FontWeight.w900 : FontWeight.normal)),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.border),
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
      case 'Typography':
        return _buildTypographyPanel(layer);
      case 'Timing':
        return _buildTimingPanel(layer);
      case 'Transform':
        return _buildTransformPanel(layer);
      case 'Color':
        return _buildColorPanel(layer);
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
        if (layer.blendMode != LayerBlendMode.normal) ...[
          const SizedBox(height: 5),
          const Text(
            'Selected blend mode is applied in FFmpeg export. Canvas preview still uses normal source-over compositing.',
            style: TextStyle(fontSize: 9, color: Color(0xFFE3C28D)),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _addKeyframe('position.x'),
          icon: const Icon(Icons.key, size: 16),
          label: const Text('Add Position Keyframe'),
        ),
      ],
    );
  }


  Widget _buildTypographyPanel(CompositionLayer layer) {
    if (layer.kind != LayerKind.text) {
      return const Center(
        child: Text('Select a Text layer to edit multilingual typography.'),
      );
    }
    final manager = FontManagerService.instance;
    final fonts = manager.fonts;
    final selectedFamily = layer.textFontFamily ?? '';
    final colorText = layer.textColor;
    final normalizedWeight = (layer.textFontWeight / 100).round()
        .clamp(1, 9).toInt() * 100;

    Widget numericField(
      String label,
      double value,
      ValueChanged<double> onSubmit, {
      bool integer = false,
    }) {
      return SizedBox(
        width: 140,
        child: TextFormField(
          key: ValueKey<String>(layer.id + label + value.toString()),
          initialValue: integer ? value.round().toString() : value.toString(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, isDense: true),
          onFieldSubmitted: (raw) {
            final parsed = double.tryParse(raw);
            if (parsed != null && parsed.isFinite) onSubmit(parsed);
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('MULTILINGUAL TYPOGRAPHY', Icons.text_fields),
        TextLayerContentEditor(
          key: ValueKey<String>(layer.id),
          initialText: layer.textContent ?? '',
          onSave: (value) =>
              _controller.updateTextLayer(textContent: value),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _chooseLayerFont(layer),
          icon: const Icon(Icons.font_download_outlined, size: 17),
          label: Text(
            fonts.where((font) => font.family == selectedFamily).isNotEmpty
                ? fonts.firstWhere((font) => font.family == selectedFamily).displayName
                : (selectedFamily.isEmpty ? 'App default / automatic fallback' : selectedFamily),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _openFontManager,
          icon: const Icon(Icons.library_books_outlined, size: 16),
          label: const Text('Browse, import and preview world fonts'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            numericField(
              'Font size',
              layer.textFontSize,
              (value) => _controller.updateTextLayer(
                textFontSize: value.clamp(1, 2000).toDouble(),
              ),
            ),
            numericField(
              'Letter spacing',
              layer.textLetterSpacing,
              (value) => _controller.updateTextLayer(
                textLetterSpacing: value.clamp(-100, 500).toDouble(),
              ),
            ),
            numericField(
              'Line height',
              layer.textLineHeight,
              (value) => _controller.updateTextLayer(
                textLineHeight: value.clamp(0.1, 10).toDouble(),
              ),
            ),
            numericField(
              'Text box width',
              layer.textBoxWidth,
              (value) => _controller.updateTextLayer(
                textBoxWidth: value.clamp(1, 20000).toDouble(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: normalizedWeight,
          decoration: const InputDecoration(labelText: 'Font weight'),
          items: [
            for (var weight = 100; weight <= 900; weight += 100)
              DropdownMenuItem(
                value: weight,
                child: Text(
                  weight.toString() +
                      (weight == 400 ? ' · Regular' : weight == 700 ? ' · Bold' : ''),
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) {
              _controller.updateTextLayer(textFontWeight: value);
            }
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Italic'),
          value: layer.textItalic,
          onChanged: (value) =>
              _controller.updateTextLayer(textItalic: value),
        ),
        TextFormField(
          key: ValueKey<String>(layer.id + 'color' + colorText),
          initialValue: colorText,
          decoration: const InputDecoration(
            labelText: 'Text color · #AARRGGBB / #RRGGBB',
            isDense: true,
          ),
          onFieldSubmitted: (value) {
            final parsed = value.trim();
            if (RegExp(r'^#(?:[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$')
                .hasMatch(parsed)) {
              _controller.updateTextLayer(textColor: parsed.toUpperCase());
            }
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: const {'left', 'center', 'right', 'justify'}
                  .contains(layer.textAlign)
              ? layer.textAlign
              : 'left',
          decoration: const InputDecoration(labelText: 'Text alignment'),
          items: const [
            DropdownMenuItem(value: 'left', child: Text('Left')),
            DropdownMenuItem(value: 'center', child: Text('Center')),
            DropdownMenuItem(value: 'right', child: Text('Right')),
            DropdownMenuItem(value: 'justify', child: Text('Justify')),
          ],
          onChanged: (value) {
            if (value != null) _controller.updateTextLayer(textAlign: value);
          },
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: ValueKey<String>(layer.id + 'fallback' + layer.textFontFallback.join(',')),
          initialValue: layer.textFontFallback.join(', '),
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Layer glyph fallback families',
            hintText: 'Noto Sans Bengali, Noto Naskh Arabic, Noto Sans CJK SC',
          ),
          onFieldSubmitted: (value) => _controller.updateTextLayer(
            textFontFallback: value
                .split(RegExp(r'[,;\n]'))
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .take(32)
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'TTF/OTF fonts can be imported and embedded in .dvproj. Missing glyphs are resolved through the selected fallback chain and then the operating system.',
          style: TextStyle(fontSize: 10, color: Color(0xFF91A2BA)),
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

  Widget _buildNativeEffectParameterControl(
    EffectInstance effect,
    Map<String, Object?> parameter,
  ) {
    final matchName = parameter['matchName']?.toString() ?? '';
    final displayName = parameter['displayName']?.toString();
    final label = displayName != null && displayName.isNotEmpty
        ? displayName
        : (parameter['name']?.toString() ?? matchName);
    final value = parameter['value'];
    if (matchName.isEmpty) return const SizedBox.shrink();
    if (value is bool) {
      return SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(fontSize: 10)),
        value: value,
        onChanged: (next) => _controller.setNativeEffectParameter(
          effect.id, matchName, next,
        ),
      );
    }
    if (value is num) {
      final min = (parameter['minValue'] as num?)?.toDouble();
      final max = (parameter['maxValue'] as num?)?.toDouble();
      if (min != null && max != null && max > min && min.isFinite && max.isFinite) {
        final safeValue = value.toDouble().clamp(min, max).toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label + '  ' + safeValue.toStringAsFixed(2) +
                  (parameter['unitsText'] == null
                      ? ''
                      : ' ' + parameter['unitsText'].toString()),
              style: const TextStyle(fontSize: 10),
            ),
            Slider(
              min: min,
              max: max,
              value: safeValue,
              onChanged: (next) => _controller.setNativeEffectParameter(
                effect.id, matchName, next,
              ),
            ),
          ],
        );
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        label + ': ' + (value?.toString() ?? 'Unsupported parameter type'),
        style: const TextStyle(fontSize: 9, color: Color(0xFF9DABC3)),
      ),
    );
  }

  Widget _buildEffectsPanel(CompositionLayer layer) {
    final filtered = EffectCatalog.allEffects
        .where((effect) => _effectCategory == 'All' || effect.category == _effectCategory)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('EFFECT LIBRARY', Icons.auto_awesome),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _exportMotionPreset(layer),
                icon: const Icon(Icons.file_download_outlined, size: 15),
                label: const Text('EXPORT PRESET'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _importMotionPreset,
                icon: const Icon(Icons.file_upload_outlined, size: 15),
                label: const Text('IMPORT PRESET'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        PopupMenuButton<String>(
          tooltip: 'Apply an editable motion preset at the playhead',
          onSelected: _controller.applyMotionPreset,
          itemBuilder: (_) => MotionPresetCatalog.all.map((preset) =>
            PopupMenuItem<String>(
              value: preset.id,
              child: SizedBox(
                width: 230,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(preset.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    Text(preset.category + ' · ' + preset.description,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 9, color: Color(0xFF98A7C0))),
                  ],
                ),
              ),
            )).toList(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome_motion, size: 16),
                const SizedBox(width: 7),
                Text('BROWSE ' + MotionPresetCatalog.all.length.toString() + ' MOTION PRESETS'),
                const SizedBox(width: 8),
                const Icon(Icons.expand_more, size: 16),
              ],
            ),
          ),
        ),
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
                    if (effect.nativeDescriptor.isNotEmpty) ...[
                      Text(
                        'NATIVE · ' +
                            (effect.nativeDescriptor['hostApp']?.toString() ?? 'Adobe host') +
                            ' · ' +
                            (effect.nativeDescriptor['matchName']?.toString() ?? ''),
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFF9DABC3),
                        ),
                      ),
                      for (final rawParameter in
                          (effect.nativeDescriptor['parameters'] as List? ?? const []))
                        if (rawParameter is Map)
                          _buildNativeEffectParameterControl(
                            effect,
                            Map<String, Object?>.from(rawParameter),
                          ),
                    ] else if (effect.effectId == 'color_grade')
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Edit Lift, Gamma, Gain, Offset and primary controls in the Color panel.',
                          style: TextStyle(fontSize: 10, color: Color(0xFF9DABC3)),
                        ),
                      )
                    else
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


  Future<void> _importColorLut() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['cube'],
      );
      if (picked == null) return;
      final sourcePath = picked.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        throw StateError('The selected file has no readable local path.');
      }
      final source = File(sourcePath);
      final info = CubeLutValidator.parse(await source.readAsString());
      final documents = await getApplicationDocumentsDirectory();
      final lutDirectory = Directory(
        documents.path + Platform.pathSeparator +
            'DepthVibe' + Platform.pathSeparator + 'LUTs',
      );
      await lutDirectory.create(recursive: true);
      final safeName = picked.name.replaceAll(
        RegExp(r'[^a-zA-Z0-9._-]'),
        '_',
      );
      final target = File(
        lutDirectory.path + Platform.pathSeparator +
            DateTime.now().millisecondsSinceEpoch.toString() + '_' + safeName,
      );
      final imported = await source.copy(target.path);

      var effect = _selected?.effects
          .where((item) => item.effectId == 'color_lut')
          .firstOrNull;
      if (effect == null) {
        _controller.addEffect('color_lut');
        effect = _selected?.effects
            .where((item) => item.effectId == 'color_lut')
            .lastOrNull;
      }
      if (effect == null) {
        throw StateError('Could not attach the LUT to the selected layer.');
      }
      _controller.setEffectAssetUri(effect.id, imported.path);
      if (mounted) {
        setState(() {
          _notice = 'Imported ' + info.title + ' · ' +
              info.size.toString() + '³ LUT · ' +
              info.entryCount.toString() + ' samples';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _notice = '3D LUT import failed: ' + error.toString());
      }
    }
  }

  Future<void> _saveCompositionProject() async {
    if (_projectBusy || _rendering) return;
    setState(() {
      _projectBusy = true;
      _notice = 'Saving project and creating a version checkpoint…';
    });
    try {
      final document = _controller.document;
      final revision = _documentRevision;
      File output;
      if (_currentProjectFile != null) {
        output = _currentProjectFile!;
      } else {
        final documents = await getApplicationDocumentsDirectory();
        Directory targetDirectory;
        if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
          final selectedDirectory = await FilePicker.pickDirectory();
          targetDirectory = selectedDirectory == null
              ? Directory(
                  documents.path + Platform.pathSeparator +
                      'DepthVibe' + Platform.pathSeparator +
                      'Projects' + Platform.pathSeparator + 'Exports',
                )
              : Directory(selectedDirectory.toFilePath());
        } else {
          targetDirectory = Directory(
            documents.path + Platform.pathSeparator +
                'DepthVibe' + Platform.pathSeparator +
                'Projects' + Platform.pathSeparator + 'Exports',
          );
        }
        final safeName = document.name
            .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
            .replaceAll(RegExp(r'\s+'), '_');
        final fileName = (safeName.isEmpty ? 'Untitled_Composition' : safeName) +
            '.dvproj';
        output = File(
          targetDirectory.path + Platform.pathSeparator + fileName,
        );
      }

      final result = await _projectService.exportVersionedProject(
        document,
        outputFile: output,
      );
      _currentProjectFile = output;
      var shared = false;
      if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
        try {
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile(result.file.path)],
              text: 'DepthVibe composition project',
            ),
          );
          shared = true;
        } catch (_) {
          // The package remains saved in the app's Projects folder.
        }
      }

      if (revision == _documentRevision) {
        final recovery = await _recoveryDirectory();
        await _recoveryService.clear(recoveryDirectory: recovery);
        _recoveryDirty = false;
        _autosaveStatus = 'Project saved';
      }
      if (!mounted) return;
      setState(() {
        final base = 'Project saved · ' +
            result.embeddedAssetCount.toString() + ' assets embedded.' +
            ' Version history keeps up to ' +
            CompositionProjectService.maxVersionHistory.toString() +
            ' earlier saves.';
        final destination = shared
            ? ' Copied through the share sheet.'
            : ' File: ' + output.path;
        _notice = result.missingAssetPaths.isEmpty
            ? base + destination
            : base + ' ' + result.missingAssetPaths.length.toString() +
                ' linked files were missing and remain external.' + destination;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Project save failed: ' + error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _projectBusy = false);
        if (_recoveryDirty) unawaited(_autosaveIfNeeded());
      }
    }
  }

  Future<void> _openCompositionProject() async {
    if (_projectBusy || _rendering) return;
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['dvproj'],
      );
      if (picked == null) return;
      final path = picked.path;
      if (path == null || path.isEmpty) {
        throw StateError('The selected project has no readable local path.');
      }
      if (!mounted) return;
      setState(() {
        _projectBusy = true;
        _notice = 'Verifying project archive and restoring assets…';
      });

      final documents = await getApplicationDocumentsDirectory();
      final projects = Directory(
        documents.path + Platform.pathSeparator +
            'DepthVibe' + Platform.pathSeparator + 'Projects',
      );
      final imported = await _projectService.importProject(
        File(path),
        projectsDirectory: projects,
      );
      _controller.replaceDocument(imported.document);
      final stableName = picked.name.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );
      final stableBase = stableName.toLowerCase().endsWith('.dvproj')
          ? stableName.substring(0, stableName.length - 6)
          : stableName;
      final stableFileName =
          (stableBase.isEmpty ? 'Opened_Project' : stableBase) +
          '_local_' + DateTime.now().millisecondsSinceEpoch.toString() +
          '.dvproj';
      final stableCopy = File(
        projects.path + Platform.pathSeparator + stableFileName,
      );
      final sourceProject = File(path);
      if (sourceProject.absolute.path != stableCopy.absolute.path) {
        if (await stableCopy.exists()) await stableCopy.delete();
        await sourceProject.copy(stableCopy.path);
      }
      _currentProjectFile = stableCopy;
      final recoveryDirectory = await _recoveryDirectory();
      await _recoveryService.clear(recoveryDirectory: recoveryDirectory);
      _recoveryDirty = false;
      _autosaveStatus = 'Project opened';
      final missingAssets = await _missingMediaPaths();
      if (!mounted) return;
      setState(() {
        _notice = 'Opened "' + imported.document.name + '" · ' +
            imported.document.layers.length.toString() + ' layers · ' +
            imported.extractedAssetCount.toString() + ' restored assets.' +
            (missingAssets.isEmpty
                ? ''
                : ' ' + missingAssets.length.toString() +
                    ' external media references need relinking.');
      });
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Project open failed: ' + error.toString());
      }
    } finally {
      if (mounted) setState(() => _projectBusy = false);
    }
  }

  Future<void> _exportColorGradePreset(CompositionLayer layer) async {
    try {
      var preset = ColorGradePreset.fromLayer(
        layer,
        outputProfile: _controller.document.colorOutputProfile,
        name: layer.name,
      );
      var lutWasEmbedded = false;
      final lutPath = layer.effects
          .where((effect) => effect.effectId == 'color_lut')
          .firstOrNull
          ?.assetUri;
      if (preset.lut != null && lutPath != null) {
        final lutFile = File(lutPath);
        if (await lutFile.exists()) {
          final lutContent = await lutFile.readAsString();
          CubeLutValidator.parse(lutContent);
          preset = preset.withLutContent(lutContent);
          lutWasEmbedded = true;
        }
      }

      final safeName = preset.name
          .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final temporary = await getTemporaryDirectory();
      final output = File(
        temporary.path + Platform.pathSeparator +
            'DepthVibe_' +
            (safeName.isEmpty ? 'Color_Grade' : safeName) +
            '_' + DateTime.now().millisecondsSinceEpoch.toString() +
            '.dvgrade',
      );
      await output.writeAsString(preset.encode(), flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(output.path)],
          text: 'DepthVibe color grade preset',
        ),
      );
      if (!mounted) return;
      setState(() {
        _notice = preset.lut != null && !lutWasEmbedded
            ? 'Preset exported. Its LUT file was not available to embed; share the .cube file separately.'
            : 'Color preset exported with animated keyframes and LUT data.';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Color preset export failed: $error');
      }
    }
  }

  Future<void> _importColorGradePreset() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['dvgrade', 'json'],
      );
      if (picked == null) return;
      final sourcePath = picked.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        throw StateError('The selected preset has no readable local path.');
      }
      final preset = ColorGradePreset.decode(
        await File(sourcePath).readAsString(),
      );
      if (_selected == null) {
        throw StateError('Select a layer before applying a color preset.');
      }

      String? importedLutPath;
      final lutContent = preset.lut?.content;
      if (lutContent != null) {
        final info = CubeLutValidator.parse(lutContent);
        final documents = await getApplicationDocumentsDirectory();
        final lutDirectory = Directory(
          documents.path + Platform.pathSeparator +
              'DepthVibe' + Platform.pathSeparator + 'LUTs',
        );
        await lutDirectory.create(recursive: true);
        final fileName = (preset.lut?.fileName ?? 'preset.cube')
            .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final safeName = fileName.isEmpty ? 'preset.cube' : fileName;
        final target = File(
          lutDirectory.path + Platform.pathSeparator +
              DateTime.now().millisecondsSinceEpoch.toString() +
              '_' + safeName,
        );
        importedLutPath = (await target.writeAsString(
          lutContent,
          flush: true,
        )).path;
        _notice = 'Validated ${info.size}³ LUT · ${info.entryCount} samples';
      }

      _controller.applyColorGradePreset(
        preset,
        lutAssetUri: importedLutPath,
      );
      if (!mounted) return;
      setState(() {
        _notice = preset.lut != null && importedLutPath == null
            ? 'Applied "${preset.name}". Re-import its missing .cube LUT to render that effect.'
            : 'Applied color preset "${preset.name}" to ${_selected!.name}.';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Color preset import failed: $error');
      }
    }
  }

  Future<void> _exportMotionPreset(CompositionLayer layer) async {
    try {
      final source = MotionPresetPackage.encode(layer, name: layer.name);
      final temporary = await getTemporaryDirectory();
      final safeName = layer.name
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final output = File(
        temporary.path + Platform.pathSeparator +
            'DepthVibe_' + (safeName.isEmpty ? 'Motion' : safeName) + '_' +
            DateTime.now().microsecondsSinceEpoch.toString() + '.dvmpreset',
      );
      await output.writeAsString(source, flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(output.path)],
        text: 'DepthVibe editable motion/effect preset',
      ));
      if (mounted) setState(() => _notice =
          'Preset exported with editable keyframes, effect settings and native Adobe descriptors.');
    } catch (error) {
      if (mounted) setState(() => _notice = 'Preset export failed: $error');
    }
  }

  Future<void> _importMotionPreset() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['dvmpreset'],
      );
      if (picked == null) return;
      final path = picked.path;
      if (path == null || path.isEmpty) {
        throw StateError('The selected preset has no readable local path.');
      }
      final presetLayer = MotionPresetPackage.decode(
        await File(path).readAsString(),
      );
      if (_selected == null) {
        throw StateError('Select a target layer before applying a preset.');
      }
      _controller.applyLayerPreset(presetLayer);
      if (mounted) {
        setState(() => _notice =
            'Imported "' + presetLayer.name + '" with ' +
            presetLayer.effects.length.toString() + ' effect(s) and ' +
            presetLayer.keyframeTracks.length.toString() + ' animation track(s).');
      }
    } catch (error) {
      if (mounted) setState(() => _notice = 'Preset import failed: $error');
    }
  }

  Widget _buildColorScopes(
    CompositionLayer layer,
    EffectInstance? grade,
    int timeMs,
  ) {
    return FutureBuilder<img.Image?>(
      future: _scopeImageFor(
        layer,
        timeMs,
        _controller.document.frameRate,
      ),
      builder: (context, snapshot) {
        final image = snapshot.data;
        if (image == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _panelHeader('VIDEO SCOPES', Icons.multiline_chart),
              Text(
                snapshot.connectionState == ConnectionState.waiting
                    ? 'Reading the current frame for scopes…'
                    : 'Select an active video or image layer to inspect its pixel scopes.',
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF9BAAC1),
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _panelHeader('VIDEO SCOPES', Icons.multiline_chart),
            ColorScopesView(
              image: image,
              mode: ColorScopeMode.waveform,
              grade: grade,
              timeMs: timeMs,
            ),
            const SizedBox(height: 7),
            ColorScopesView(
              image: image,
              mode: ColorScopeMode.rgbParade,
              grade: grade,
              timeMs: timeMs,
            ),
            const SizedBox(height: 7),
            ColorScopesView(
              image: image,
              mode: ColorScopeMode.vectorscope,
              grade: grade,
              timeMs: timeMs,
            ),
            const SizedBox(height: 5),
            const Text(
              'Scopes use the current decoded frame and the primary-wheel preview approximation. Curves and LUT data are not yet included in the scope calculations.',
              style: TextStyle(fontSize: 9, color: Color(0xFF8190A8)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildColorPanel(CompositionLayer layer) {
    final grade = layer.effects
        .where((effect) => effect.effectId == 'color_grade')
        .firstOrNull;
    final curves = layer.effects
        .where((effect) => effect.effectId == 'color_curves')
        .firstOrNull;
    final lut = layer.effects
        .where((effect) => effect.effectId == 'color_lut')
        .firstOrNull;
    final definition = EffectCatalog.find('color_grade')!;
    final playheadMs = _controller.document.playheadMs;
    final outputProfile = _controller.document.colorOutputProfile;

    double value(EffectInstance activeGrade, String id) {
      final parameter = definition.parameters.firstWhere(
        (item) => item.id == id,
      );
      return activeGrade.parameterAt(
        id,
        playheadMs,
        fallback: parameter.defaultValue,
      ).clamp(parameter.min, parameter.max).toDouble();
    }

    Widget gradeSlider({
      required EffectInstance activeGrade,
      required String id,
      required String label,
      required double min,
      required double max,
      required bool keyframeable,
    }) {
      final current = value(activeGrade, id);
      final hasTrack = activeGrade.keyframeTracks.any(
        (track) => track.property == id && track.enabled,
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  current.toStringAsFixed(2),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFFB9C6D9),
                  ),
                ),
                if (keyframeable)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Add ' + label + ' keyframe',
                    onPressed: () => _controller.addEffectKeyframe(
                      activeGrade.id,
                      id,
                    ),
                    icon: Icon(
                      Icons.diamond,
                      size: 15,
                      color: hasTrack
                          ? const Color(0xFFB8A4FF)
                          : const Color(0xFF8290A8),
                    ),
                  ),
              ],
            ),
            Slider(
              min: min,
              max: max,
              value: current,
              onChanged: (nextValue) => _controller.setEffectParameter(
                activeGrade.id,
                id,
                nextValue,
                keyframe: keyframeable && hasTrack,
              ),
            ),
          ],
        ),
      );
    }

    Widget wheelCard(
      EffectInstance activeGrade,
      String title,
      String prefix,
    ) {
      final ids = [
        prefix + '_r',
        prefix + '_g',
        prefix + '_b',
      ];
      final hasWheelTrack = activeGrade.keyframeTracks.any(
        (track) => ids.contains(track.property) && track.enabled,
      );
      return SizedBox(
        width: 142,
        child: Card(
          color: const Color(0xFF182231),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 26,
                        minHeight: 26,
                      ),
                      padding: EdgeInsets.zero,
                      tooltip: 'Animate ' + title + ' wheel',
                      onPressed: () {
                        for (final id in ids) {
                          _controller.addEffectKeyframe(activeGrade.id, id);
                        }
                      },
                      icon: Icon(
                        Icons.diamond,
                        size: 14,
                        color: hasWheelTrack
                            ? const Color(0xFFB8A4FF)
                            : const Color(0xFF8290A8),
                      ),
                    ),
                  ],
                ),
                ColorWheelControl(
                  diameter: 112,
                  red: value(activeGrade, prefix + '_r'),
                  green: value(activeGrade, prefix + '_g'),
                  blue: value(activeGrade, prefix + '_b'),
                  onChanged: (wheel) {
                    _controller.setEffectParameter(
                      activeGrade.id,
                      prefix + '_r',
                      wheel.red,
                      keyframe: hasWheelTrack,
                    );
                    _controller.setEffectParameter(
                      activeGrade.id,
                      prefix + '_g',
                      wheel.green,
                      keyframe: hasWheelTrack,
                    );
                    _controller.setEffectParameter(
                      activeGrade.id,
                      prefix + '_b',
                      wheel.blue,
                      keyframe: hasWheelTrack,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget primaryGradeControls(EffectInstance activeGrade) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'PRIMARY WHEELS',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                ),
              ),
              Switch(
                value: activeGrade.enabled,
                onChanged: (enabled) => _controller.setEffectEnabled(
                  activeGrade.id,
                  enabled,
                ),
              ),
            ],
          ),
          const Text(
            'Lift · Gamma · Gain · Offset — drag a wheel to shift RGB balance. The diamond creates keyframes for all three channels.',
            style: TextStyle(fontSize: 10, color: Color(0xFF9DABC3)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              wheelCard(activeGrade, 'Lift', 'lift'),
              wheelCard(activeGrade, 'Gamma', 'gamma'),
              wheelCard(activeGrade, 'Gain', 'gain'),
              wheelCard(activeGrade, 'Offset', 'offset'),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                for (final prefix in const [
                  'lift',
                  'gamma',
                  'gain',
                  'offset',
                ]) {
                  for (final channel in const ['r', 'g', 'b']) {
                    _controller.setEffectParameter(
                      activeGrade.id,
                      prefix + '_' + channel,
                      0,
                    );
                  }
                }
                _controller.setEffectParameter(activeGrade.id, 'temperature', 0);
                _controller.setEffectParameter(activeGrade.id, 'tint', 0);
              },
              icon: const Icon(Icons.restart_alt, size: 15),
              label: const Text(
                'Reset Wheels',
                style: TextStyle(fontSize: 10),
              ),
            ),
          ),
          const Divider(color: Color(0xFF29354A)),
          _panelHeader('PRIMARY CONTROLS', Icons.tune),
          gradeSlider(
            activeGrade: activeGrade,
            id: 'contrast',
            label: 'Contrast',
            min: 0,
            max: 3,
            keyframeable: true,
          ),
          gradeSlider(
            activeGrade: activeGrade,
            id: 'brightness',
            label: 'Exposure / Brightness',
            min: -1,
            max: 1,
            keyframeable: true,
          ),
          gradeSlider(
            activeGrade: activeGrade,
            id: 'master_gamma',
            label: 'Master Gamma',
            min: 0.1,
            max: 3,
            keyframeable: true,
          ),
          gradeSlider(
            activeGrade: activeGrade,
            id: 'saturation',
            label: 'Saturation',
            min: 0,
            max: 3,
            keyframeable: true,
          ),
          const Divider(color: Color(0xFF29354A)),
          _panelHeader('WHITE BALANCE', Icons.wb_sunny_outlined),
          gradeSlider(
            activeGrade: activeGrade,
            id: 'temperature',
            label: 'Temperature · Cool / Warm',
            min: -1,
            max: 1,
            keyframeable: false,
          ),
          gradeSlider(
            activeGrade: activeGrade,
            id: 'tint',
            label: 'Tint · Green / Magenta',
            min: -1,
            max: 1,
            keyframeable: false,
          ),
        ],
      );
    }

    final curveValues = [
      for (var index = 0; index < 5; index++)
        curves?.parameters[_curveChannel + '_' + index.toString()] ??
            index * 0.25,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('COLOR PAGE · PRIMARY & SECONDARY', Icons.color_lens),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _exportColorGradePreset(layer),
                icon: const Icon(Icons.ios_share, size: 15),
                label: const Text('SAVE PRESET'),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _importColorGradePreset,
                icon: const Icon(Icons.file_open_outlined, size: 15),
                label: const Text('LOAD PRESET'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (grade == null)
          FilledButton.icon(
            onPressed: () => _controller.addEffect('color_grade'),
            icon: const Icon(Icons.add),
            label: const Text('ADD PRIMARY COLOR GRADE'),
          )
        else
          primaryGradeControls(grade),
        const Divider(color: Color(0xFF29354A)),
        _panelHeader('CUSTOM RGB CURVES', Icons.show_chart),
        if (curves == null)
          OutlinedButton.icon(
            onPressed: () => _controller.addEffect('color_curves'),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('ADD MASTER / RGB CURVES'),
          )
        else ...[
          DropdownButtonFormField<String>(
            initialValue: _curveChannel,
            decoration: const InputDecoration(
              labelText: 'Curve channel',
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'master', child: Text('Master / Luma')),
              DropdownMenuItem(value: 'red', child: Text('Red')),
              DropdownMenuItem(value: 'green', child: Text('Green')),
              DropdownMenuItem(value: 'blue', child: Text('Blue')),
            ],
            onChanged: (channel) => setState(
              () => _curveChannel = channel ?? 'master',
            ),
          ),
          const SizedBox(height: 8),
          ColorCurveEditor(
            values: curveValues,
            onChanged: (values) {
              for (var index = 0; index < values.length; index++) {
                _controller.setEffectParameter(
                  curves.id,
                  _curveChannel + '_' + index.toString(),
                  values[index],
                );
              }
            },
          ),
          const Text(
            'Curves are compiled into FFmpeg export. They are not yet included in the live preview transform.',
            style: TextStyle(fontSize: 9, color: Color(0xFF8190A8)),
          ),
        ],
        const Divider(color: Color(0xFF29354A)),
        _panelHeader('3D LUT MANAGEMENT', Icons.palette_outlined),
        if (lut?.assetUri != null)
          Row(
            children: [
              const Icon(
                Icons.check_circle,
                color: Color(0xFF73D6B2),
                size: 15,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  lut!.assetUri!.split(Platform.pathSeparator).last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10),
                ),
              ),
              Switch(
                value: lut.enabled,
                onChanged: (enabled) => _controller.setEffectEnabled(
                  lut.id,
                  enabled,
                ),
              ),
            ],
          )
        else
          const Text(
            'Import a validated 3D .cube LUT. The table is applied by the native FFmpeg export filter.',
            style: TextStyle(fontSize: 10, color: Color(0xFF9DABC3)),
          ),
        OutlinedButton.icon(
          onPressed: _importColorLut,
          icon: const Icon(Icons.file_upload_outlined, size: 16),
          label: Text(
            lut?.assetUri == null ? 'IMPORT .CUBE LUT' : 'REPLACE LUT',
          ),
        ),
        if (lut?.assetUri != null)
          DropdownButtonFormField<String>(
            initialValue: lut!.assetInterpolation,
            decoration: const InputDecoration(
              labelText: 'LUT interpolation',
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'nearest', child: Text('Nearest · fastest')),
              DropdownMenuItem(value: 'trilinear', child: Text('Trilinear · smooth')),
              DropdownMenuItem(value: 'tetrahedral', child: Text('Tetrahedral · high quality')),
              DropdownMenuItem(value: 'pyramid', child: Text('Pyramid')),
              DropdownMenuItem(value: 'prism', child: Text('Prism')),
            ],
            onChanged: (mode) {
              if (mode != null) {
                _controller.setEffectAssetInterpolation(lut.id, mode);
              }
            },
          ),
        const Divider(color: Color(0xFF29354A)),
        _panelHeader('HDR COLOR OUTPUT', Icons.hdr_on),
        DropdownButtonFormField<ColorOutputProfile>(
          initialValue: outputProfile,
          decoration: const InputDecoration(
            labelText: 'Composition output profile',
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(
              value: ColorOutputProfile.rec709,
              child: Text('SDR · Rec.709 · 8-bit MP4'),
            ),
            DropdownMenuItem(
              value: ColorOutputProfile.hdr10Pq,
              child: Text('HDR10 · BT.2020 · PQ · 10-bit MOV'),
            ),
            DropdownMenuItem(
              value: ColorOutputProfile.hlg,
              child: Text('HLG · BT.2020 · 10-bit MOV'),
            ),
          ],
          onChanged: (profile) {
            if (profile != null) _controller.setColorOutputProfile(profile);
          },
        ),
        const SizedBox(height: 5),
        const Text(
          'HDR modes export a Rec.709-to-BT.2020 PQ/HLG mapped ProRes 422 HQ 10-bit file. This is an SDR-to-HDR mapping, not native scene-referred HDR mastering; source highlight detail and dynamic HDR metadata are not created.',
          style: TextStyle(fontSize: 9, color: Color(0xFFE1C28B)),
        ),
        const Divider(color: Color(0xFF29354A)),
        _buildColorScopes(layer, grade, playheadMs),
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
              .map((kind) => PopupMenuItem(value: kind, child: Text(TransitionCatalog.displayName(kind))))
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
                            child: Text(TransitionCatalog.displayName(kind), overflow: TextOverflow.ellipsis),
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

  Widget _animatedMaskVertexPropertyRow(
    MaskModel mask,
    int vertexIndex,
    String label,
    String component,
    double min,
    double max,
  ) {
    final playhead = _controller.document.playheadMs;
    final property = 'vertex.$vertexIndex.$component';
    final value = mask.vertexValueAt(vertexIndex, component, playhead);
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
              tooltip: 'Add vertex keyframe at playhead',
              onPressed: () => _controller.setMaskVertexAnimatedValue(
                mask.id,
                vertexIndex,
                component,
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
                value.toStringAsFixed(3),
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
          onChanged: (next) => _controller.setMaskVertexAnimatedValue(
            mask.id,
            vertexIndex,
            component,
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
                  if (mask.shape == MaskShape.bezier ||
                      mask.shape == MaskShape.polygon)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        'PATH VERTICES · ${mask.vertices.length}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OutlinedButton.icon(
                            onPressed: mask.vertices.length < 3
                                ? null
                                : () => _controller.keyframeMaskPath(mask.id),
                            icon: const Icon(Icons.key, size: 15),
                            label: const Text('KEYFRAME FULL MASK'),
                          ),
                        ),
                        for (var index = 0; index < mask.vertices.length; index++)
                          Builder(
                            builder: (context) {
                              final vertex = mask.vertices[index];
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
                                  _animatedMaskVertexPropertyRow(
                                    mask,
                                    index,
                                    'Anchor X',
                                    'anchor.x',
                                    0,
                                    1,
                                  ),
                                  _animatedMaskVertexPropertyRow(
                                    mask,
                                    index,
                                    'Anchor Y',
                                    'anchor.y',
                                    0,
                                    1,
                                  ),
                                  _animatedMaskVertexPropertyRow(
                                    mask,
                                    index,
                                    'In handle X',
                                    'inHandle.x',
                                    -0.5,
                                    0.5,
                                  ),
                                  _animatedMaskVertexPropertyRow(
                                    mask,
                                    index,
                                    'In handle Y',
                                    'inHandle.y',
                                    -0.5,
                                    0.5,
                                  ),
                                  _animatedMaskVertexPropertyRow(
                                    mask,
                                    index,
                                    'Out handle X',
                                    'outHandle.x',
                                    -0.5,
                                    0.5,
                                  ),
                                  _animatedMaskVertexPropertyRow(
                                    mask,
                                    index,
                                    'Out handle Y',
                                    'outHandle.y',
                                    -0.5,
                                    0.5,
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
          'Polygon/Bezier anchors and tangent handles can be keyframed for per-frame rotoscoping. Export renders animated feather/expansion; the live canvas clip uses hard edges and does not yet preview feather or per-mask alpha.',
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
            'Camera orientation and perspective now drive image cards and imported OBJ geometry. Near/far clipping is shared by preview and FFmpeg camera projection; depth-of-field blur and shadow maps remain pending.',
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
          _settingSlider('Near Clip', camera.nearClip, 1, 2000,
              (value) => _controller.setCameraSettings(camera.copyWith(
                    nearClip: value,
                    farClip: camera.farClip <= value ? value + 1 : camera.farClip,
                  ))),
          _settingSlider('Far Clip', camera.farClip, camera.nearClip + 1, 50000,
              (value) => _controller.setCameraSettings(camera.copyWith(farClip: value))),
          _settingSlider('Aperture · f-stop', camera.aperture, 0.7, 22,
              (value) => _controller.setCameraSettings(camera.copyWith(aperture: value))),
          _settingSlider('Sensor Width · mm', camera.sensorWidthMm, 18, 70,
              (value) => _controller.setCameraSettings(camera.copyWith(sensorWidthMm: value))),
          const SizedBox(height: 8),
          const Text(
            'CAMERA ORIENTATION',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
          ),
          _animatedPropertyRow(layer, 'Orbit X', 'rotation.x', -180, 180),
          _animatedPropertyRow(layer, 'Orbit Y', 'rotation.y', -180, 180),
          _animatedPropertyRow(layer, 'Roll Z', 'rotation.z', -180, 180),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Depth of Field · CPU preview',
              style: TextStyle(fontSize: 11),
            ),
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
          const Text(
            'Directional, spot and point lights use depth-tested shadow maps with percentage-closer filtering. Mesh frames also use thin-lens depth of field and deterministic area-light sampling.',
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
          if (light.kind == LightKind.area) ...[
            _settingSlider('Area Size', light.areaSize, 1, 1000,
                (value) => _controller.setLightSettings(light.copyWith(areaSize: value))),
            _settingSlider('Area Samples', light.areaSamples.toDouble(), 1, 64,
                (value) => _controller.setLightSettings(
                    light.copyWith(areaSamples: value.round()))),
          ],
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader('3D MESH LAYER', Icons.view_in_ar),
        Text(
          layer.sourceUri == null
              ? 'Import OBJ, GLTF or GLB. GLTF scenes retain UV0, base-colour images, vertex normals, nested node transforms and embedded animation clips.'
              : 'Loaded source: ${layer.name}\nPreview and rendered frames use UV-mapped base-colour textures, transformed smooth normals, active-scene hierarchy and the selected animation clip.',
          style: const TextStyle(fontSize: 11, color: Color(0xFF98A7C0)),
        ),
        if (layer.sourceUri != null) ...[
          const SizedBox(height: 10),
          FutureBuilder<ObjMesh>(
            future: _meshFor(layer.sourceUri!),
            builder: (context, snapshot) {
              final mesh = snapshot.data;
              if (snapshot.hasError) {
                return Text(
                  'Could not inspect scene metadata: ${snapshot.error}',
                  style: const TextStyle(fontSize: 10, color: Color(0xFFFF9D9D)),
                );
              }
              if (mesh == null) {
                return const LinearProgressIndicator(minHeight: 2);
              }
              final texturedMaterials = mesh.materials.values
                  .where((material) => material.baseColorTextureBytes != null)
                  .length;
              final inventory = '${mesh.sceneNodes.length} nodes · ${mesh.triangles.length} triangles · '
                  '${mesh.materials.length} materials · $texturedMaterials base-colour maps · '
                  '${mesh.hasTextureCoordinates ? 'UV0 available' : 'no UV0 stream'}';
              if (mesh.animations.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(inventory, style: const TextStyle(fontSize: 9, color: Color(0xFF9BAAC1))),
                    const SizedBox(height: 5),
                    const Text(
                      'No embedded animation clips found. The model stays in its rest pose.',
                      style: TextStyle(fontSize: 10, color: Color(0xFF98A7C0)),
                    ),
                  ],
                );
              }
              final selectedIndex = layer.modelAnimationIndex
                  .clamp(-1, mesh.animations.length - 1)
                  .toInt();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(inventory, style: const TextStyle(fontSize: 9, color: Color(0xFF9BAAC1))),
                  const SizedBox(height: 7),
                  DropdownButtonFormField<int>(
                    key: ValueKey<String>(layer.id + ':gltf-animation'),
                    initialValue: selectedIndex,
                    decoration: const InputDecoration(labelText: 'Animation Clip'),
                    items: [
                      const DropdownMenuItem<int>(value: -1, child: Text('Rest Pose')),
                      for (final entry in mesh.animations.indexed)
                        DropdownMenuItem<int>(
                          value: entry.$1,
                          child: Text(
                            entry.$2.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) _controller.setModelAnimationIndex(value);
                    },
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${mesh.animations.length} clip(s) · translation / rotation / scale · follows the composition playhead',
                    style: const TextStyle(fontSize: 9, color: Color(0xFF98A7C0)),
                  ),
                ],
              );
            },
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _addLayer(LayerKind.threeDModel),
          icon: const Icon(Icons.file_open),
          label: const Text('IMPORT OBJ / GLTF / GLB'),
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
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return Container(
      height: 212,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.toolbar,
        border: Border(top: BorderSide(color: palette.border)),
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
          for (final mask in layer.masks)
            for (final track in mask.keyframeTracks)
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
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 15, color: palette.accent),
          const SizedBox(width: 7),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.1, color: palette.secondaryText)),
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

/// Clips a layer to its frame-evaluated polygon/Bezier mask stack.
class _AnimatedMaskClipper extends CustomClipper<Path> {
  const _AnimatedMaskClipper({
    required this.masks,
    required this.timeMs,
  });

  final List<MaskModel> masks;
  final int timeMs;

  Path _shape(MaskModel mask, Size size) {
    final left =
        mask.valueAt('left', timeMs).clamp(0.0, 1.0).toDouble();
    final top =
        mask.valueAt('top', timeMs).clamp(0.0, 1.0).toDouble();
    final width =
        mask.valueAt('width', timeMs).clamp(0.01, 1.0).toDouble();
    final height =
        mask.valueAt('height', timeMs).clamp(0.01, 1.0).toDouble();
    final bounds = Rect.fromLTWH(
      left * size.width,
      top * size.height,
      width * size.width,
      height * size.height,
    );

    switch (mask.shape) {
      case MaskShape.rectangle:
        return Path()..addRect(bounds);
      case MaskShape.ellipse:
        return Path()..addOval(bounds);
      case MaskShape.polygon:
      case MaskShape.bezier:
        if (mask.vertices.length < 3) return Path()..addRect(bounds);
        final base = _baseOutline(mask);
        if (base.isEmpty) return Path();
        final minX = base
            .map((point) => point.dx)
            .reduce((a, b) => a < b ? a : b);
        final maxX = base
            .map((point) => point.dx)
            .reduce((a, b) => a > b ? a : b);
        final minY = base
            .map((point) => point.dy)
            .reduce((a, b) => a < b ? a : b);
        final maxY = base
            .map((point) => point.dy)
            .reduce((a, b) => a > b ? a : b);
        final spanX = (maxX - minX).abs() < 0.0001 ? 1.0 : maxX - minX;
        final spanY = (maxY - minY).abs() < 0.0001 ? 1.0 : maxY - minY;
        Offset mapPoint(double x, double y) => Offset(
              bounds.left + (x - minX) / spanX * bounds.width,
              bounds.top + (y - minY) / spanY * bounds.height,
            );
        final vertices = [
          for (var index = 0; index < mask.vertices.length; index++)
            Offset(
              mask.vertexValueAt(index, 'anchor.x', timeMs),
              mask.vertexValueAt(index, 'anchor.y', timeMs),
            ),
        ];
        final path = Path()..moveTo(
            mapPoint(vertices.first.dx, vertices.first.dy).dx,
            mapPoint(vertices.first.dx, vertices.first.dy).dy,
          );
        for (var index = 0; index < vertices.length; index++) {
          final next = (index + 1) % vertices.length;
          if (mask.shape == MaskShape.polygon) {
            final point = mapPoint(vertices[next].dx, vertices[next].dy);
            path.lineTo(point.dx, point.dy);
          } else {
            final start = vertices[index];
            final end = vertices[next];
            final p1 = mapPoint(
              start.dx +
                  mask.vertexValueAt(index, 'outHandle.x', timeMs),
              start.dy +
                  mask.vertexValueAt(index, 'outHandle.y', timeMs),
            );
            final p2 = mapPoint(
              end.dx +
                  mask.vertexValueAt(next, 'inHandle.x', timeMs),
              end.dy +
                  mask.vertexValueAt(next, 'inHandle.y', timeMs),
            );
            final p3 = mapPoint(end.dx, end.dy);
            path.cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);
          }
        }
        path.close();
        return path;
    }
  }

  List<Offset> _baseOutline(MaskModel mask) {
    if (mask.shape != MaskShape.bezier) {
      return [
        for (var index = 0; index < mask.vertices.length; index++)
          Offset(
            mask.vertices[index].anchor.x,
            mask.vertices[index].anchor.y,
          ),
      ];
    }
    const subdivisions = 8;
    final points = <Offset>[];
    for (var index = 0; index < mask.vertices.length; index++) {
      final next = (index + 1) % mask.vertices.length;
      final start = mask.vertices[index];
      final end = mask.vertices[next];
      final p0 = start.anchor;
      final p1 = Offset(
        p0.x + start.outHandle.x,
        p0.y + start.outHandle.y,
      );
      final p3 = end.anchor;
      final p2 = Offset(
        p3.x + end.inHandle.x,
        p3.y + end.inHandle.y,
      );
      for (var step = 0; step < subdivisions; step++) {
        final t = step / subdivisions;
        final inverse = 1 - t;
        final a = inverse * inverse * inverse;
        final b = 3 * inverse * inverse * t;
        final c = 3 * inverse * t * t;
        final d = t * t * t;
        points.add(Offset(
          a * p0.x + b * p1.dx + c * p2.dx + d * p3.x,
          a * p0.y + b * p1.dy + c * p2.dy + d * p3.y,
        ));
      }
    }
    return points;
  }

  @override
  Path getClip(Size size) {
    if (masks.isEmpty) return Path()..addRect(Offset.zero & size);
    Path? combined;
    for (final mask in masks.where((item) => item.enabled)) {
      var shape = _shape(mask, size);
      if (mask.inverted) {
        final inverse = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & size)
          ..addPath(shape, Offset.zero);
        shape = inverse;
      }
      if (combined == null) {
        combined = mask.operation == MaskOperation.subtract
            ? Path.combine(
                PathOperation.difference,
                Path()..addRect(Offset.zero & size),
                shape,
              )
            : shape;
        continue;
      }
      final operation = switch (mask.operation) {
        MaskOperation.add => PathOperation.union,
        MaskOperation.subtract => PathOperation.difference,
        MaskOperation.intersect => PathOperation.intersect,
        MaskOperation.difference => PathOperation.xor,
      };
      try {
        combined = Path.combine(operation, combined, shape);
      } on Exception {
        // Keep the last valid path if a malformed transient path cannot combine.
      }
    }
    return combined ?? (Path()..addRect(Offset.zero & size));
  }

  @override
  bool shouldReclip(covariant _AnimatedMaskClipper oldClipper) =>
      oldClipper.timeMs != timeMs || oldClipper.masks != masks;
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
