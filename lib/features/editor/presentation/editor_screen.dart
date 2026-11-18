import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:share_plus/share_plus.dart';

import '../../../features/media/data/media_picker_service.dart';
import '../../../features/media/presentation/camera_capture_screen.dart';
import '../application/editor_controller.dart';
import '../data/video_export_service.dart';
import '../domain/editor_project.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final EditorController _editor = EditorController();
  final Player _player = Player();
  late final VideoController _videoController = VideoController(_player);
  final VideoExportService _exporter = const VideoExportService();

  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  Duration _position = Duration.zero;
  bool _ready = false;
  bool _exporting = false;
  double _exportProgress = 0;
  String? _status;

  @override
  void initState() {
    super.initState();
    _durationSubscription = _player.stream.duration.listen((duration) {
      _editor.setSourceDuration(duration);
    });
    _positionSubscription = _player.stream.position.listen((position) {
      if (!mounted) return;
      setState(() => _position = position);
      _editor.setPlayhead(position);
    });
    _editor.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _importVideo() async {
    try {
      final path = await MediaPickerService.pickVideo();
      if (path == null) return;
      await _openVideo(path);
    } catch (error) {
      _showMessage('Could not open video: $error');
    }
  }

  Future<void> _openVideo(String path) async {
    _editor.loadVideo(path);
    await _player.open(Media(path), play: false);
    await _player.setRate(_editor.project.speed);
    await _player.setVolume(_editor.project.muted ? 0 : 100);
    if (!mounted) return;
    setState(() {
      _ready = true;
      _position = Duration.zero;
      _status = 'Media loaded';
    });
  }

  Future<void> _recordVideo() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
    );
    if (result != null && result.isNotEmpty) {
      await _openVideo(result);
    }
  }

  Future<void> _seek(double value) async {
    final position = Duration(milliseconds: value.round());
    await _player.seek(position);
    _editor.setPlayhead(position);
  }

  Future<void> _setMuted(bool value) async {
    _editor.setMuted(value);
    if (_ready) await _player.setVolume(value ? 0 : 100);
  }

  Future<void> _changeSpeed(double value) async {
    _editor.setSpeed(value);
    if (_ready) await _player.setRate(value);
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _exportProgress = 0;
      _status = 'Preparing MP4 export…';
    });
    try {
      final result = await _exporter.export(
        _editor.project,
        onProgress: (value) {
          if (mounted) setState(() => _exportProgress = value);
        },
      );
      if (!mounted) return;
      setState(() {
        _status = result.galleryUri != null
            ? 'Saved to Movies/DepthVibe/videos'
            : result.gallerySaveError != null
                ? 'Saved in app storage; gallery save needs permission'
                : 'Saved to Documents/DepthVibe/Exports';
        _exportProgress = 1;
      });
      await _showExportComplete(result);
    } catch (error) {
      _showMessage('Export failed: $error');
      if (mounted) setState(() => _status = 'Export failed');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _showExportComplete(VideoExportResult result) async {
    final file = result.file;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Export complete'),
        content: SelectableText(
          result.galleryUri != null
              ? 'MP4 saved to Movies/DepthVibe/videos.\nGallery reference: ${result.galleryUri}\nApp copy: ${file.path}'
              : result.gallerySaveError != null
                  ? 'The MP4 was exported successfully, but saving to the gallery failed.\n\nApp copy: ${file.path}\n\n${result.gallerySaveError}'
                  : 'MP4 saved to:\n${file.path}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await SharePlus.instance.share(
                ShareParams(
                  files: [XFile(file.path)],
                  text: 'Created with DepthVibe by N Tech',
                ),
              );
            },
            icon: const Icon(Icons.ios_share),
            label: const Text('Share'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String _time(int ms) {
    final seconds = ms ~/ 1000;
    final minutes = seconds ~/ 60;
    return '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _toolButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool primary = false,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: primary ? Colors.white : const Color(0xFFD8DEEA),
        backgroundColor: primary ? const Color(0xFF6F7DFF) : const Color(0xFF151D2B),
        side: BorderSide(
          color: primary ? const Color(0xFF6F7DFF) : const Color(0xFF2A3549),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 980;
                  if (wide) {
                    return Column(
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 7, child: _buildPreviewArea()),
                              SizedBox(
                                width: 340,
                                child: _buildInspector(scrollable: true),
                              ),
                            ],
                          ),
                        ),
                        _buildTimeline(),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            children: [
                              _buildPreviewArea(compact: true),
                              const SizedBox(height: 12),
                              _buildInspector(scrollable: false),
                            ],
                          ),
                        ),
                      ),
                      _buildTimeline(compact: true),
                    ],
                  );
                },
              ),
            ),
            if (_exporting) _buildExportProgress(),
            if (_status != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                color: const Color(0xFF0E1520),
                child: Text(
                  _status!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF9BA9C0), fontSize: 11),
                ),
              ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF101722),
        border: Border(bottom: BorderSide(color: Color(0xFF273247))),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              gradient: const LinearGradient(
                colors: [Color(0xFF7183FF), Color(0xFF9C68E8)],
              ),
            ),
            child: const Icon(Icons.view_in_ar, color: Colors.white),
          ),
          const SizedBox(width: 11),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DEPTHVIBE', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
              Text('N TECH CREATIVE STUDIO', style: TextStyle(fontSize: 9, color: Color(0xFF8F9CB2), letterSpacing: 1)),
            ],
          ),
          const Spacer(),
          if (MediaQuery.sizeOf(context).width > 700)
            const Text('VIDEO STUDIO  /  PRO WORKSPACE', style: TextStyle(color: Color(0xFF8795AD), fontSize: 10, letterSpacing: 1)),
          const SizedBox(width: 14),
          _toolButton(
            icon: Icons.folder_open,
            label: 'Import',
            onPressed: _exporting ? null : _importVideo,
          ),
          const SizedBox(width: 8),
          _toolButton(
            icon: Icons.videocam,
            label: 'Record',
            onPressed: _exporting ? null : _recordVideo,
          ),
          const SizedBox(width: 8),
          _toolButton(
            icon: Icons.ios_share,
            label: 'Export MP4',
            onPressed: _exporting || !_editor.project.hasVideo ? null : _export,
            primary: true,
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewArea({bool compact = false}) {
    final project = _editor.project;
    final width = compact ? double.infinity : null;
    final previewContent = AspectRatio(
      aspectRatio: project.aspect.ratio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: const Color(0xFF070A10),
              child: _ready
                  ? Transform.rotate(
                      angle: project.rotationDegrees * math.pi / 180,
                      child: Video(
                        controller: _videoController,
                        controls: NoVideoControls,
                        fit: project.canvasFit == CanvasFit.fit ? BoxFit.contain : BoxFit.cover,
                      ),
                    )
                  : _buildEmptyPreview(),
            ),
            if (project.title.isNotEmpty || project.caption.isNotEmpty)
              Positioned(
                left: 18,
                right: 18,
                bottom: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      if (project.title.isNotEmpty)
                        Text(
                          project.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, shadows: [Shadow(blurRadius: 8, color: Colors.black)]),
                        ),
                      if (project.caption.isNotEmpty)
                        Text(
                          project.caption,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFE3E8F2), fontSize: 13),
                        ),
                    ],
                  ),
                ),
              ),
            Positioned(
              top: 12,
              left: 12,
              child: _previewChip(project.aspect.label),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: _previewChip(project.canvasFit == CanvasFit.fit ? 'FIT' : 'FILL'),
            ),
          ],
        ),
      ),
    );

    return Container(
      width: width,
      padding: EdgeInsets.all(compact ? 0 : 18),
      child: compact
          ? Column(
              children: [
                previewContent,
                const SizedBox(height: 8),
                _buildPlaybackControls(),
              ],
            )
          : Column(
              children: [
                Expanded(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 920), child: previewContent))),
                const SizedBox(height: 12),
                _buildPlaybackControls(),
              ],
            ),
    );
  }

  Widget _buildPlaybackControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          onPressed: !_ready ? null : () => _player.seek(Duration.zero),
          icon: const Icon(Icons.replay),
        ),
        const SizedBox(width: 12),
        IconButton.filled(
          onPressed: !_ready
              ? null
              : () async {
                  if (_player.state.playing) {
                    await _player.pause();
                  } else {
                    await _player.play();
                  }
                  if (mounted) setState(() {});
                },
          icon: Icon(_player.state.playing ? Icons.pause : Icons.play_arrow),
        ),
        const SizedBox(width: 12),
        IconButton.filledTonal(
          onPressed: _ready ? _editor.rotateClockwise : null,
          icon: const Icon(Icons.rotate_right),
        ),
      ],
    );
  }

  Widget _buildEmptyPreview() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.movie_creation_outlined, size: 56, color: Color(0xFF65738D)),
          SizedBox(height: 14),
          Text('Your creative canvas', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          SizedBox(height: 5),
          Text('Import a video or record from your camera', style: TextStyle(color: Color(0xFF8593AA), fontSize: 12)),
          SizedBox(height: 14),
          Text('DEPTHVIBE  •  N TECH', style: TextStyle(color: Color(0xFF68768E), fontSize: 9, letterSpacing: 2)),
        ],
      ),
    );
  }

  Widget _previewChip(String label) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(label, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildInspector({required bool scrollable}) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('PROJECT SETTINGS', Icons.tune),
        const SizedBox(height: 12),
        _aspectSelector(),
        const SizedBox(height: 12),
        _fitSelector(),
        const SizedBox(height: 12),
        _sectionTitle('TRANSFORM', Icons.transform),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: Text('Rotation  ${_editor.project.rotationDegrees}°', style: const TextStyle(color: Color(0xFFB7C2D4), fontSize: 12))),
            IconButton.filledTonal(
              tooltip: 'Rotate 90 degrees',
              onPressed: !_ready ? null : _editor.rotateClockwise,
              icon: const Icon(Icons.rotate_90_degrees_cw),
            ),
            IconButton.filledTonal(
              tooltip: 'Mute original audio',
              onPressed: !_ready ? null : () => _setMuted(!_editor.project.muted),
              icon: Icon(_editor.project.muted ? Icons.volume_off : Icons.volume_up),
            ),
          ],
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Remove original audio', style: TextStyle(fontSize: 13)),
          value: _editor.project.muted,
          onChanged: !_ready ? null : _setMuted,
        ),
        const SizedBox(height: 6),
        _sectionTitle('PLAYBACK SPEED', Icons.speed),
        Slider(
          value: _editor.project.speed,
          min: 0.25,
          max: 2,
          divisions: 7,
          label: '${_editor.project.speed.toStringAsFixed(2)}×',
          onChanged: !_ready ? null : (value) => _changeSpeed(value),
        ),
        Center(
          child: Text(
            '${_editor.project.speed.toStringAsFixed(2)}×',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFFAEB9FF)),
          ),
        ),
        const SizedBox(height: 8),
        _sectionTitle('TRIM IN / OUT', Icons.content_cut),
        _trimControls(),
        const SizedBox(height: 10),
        _sectionTitle('TITLES & CAPTIONS', Icons.title),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(labelText: 'Title', hintText: 'Add a title overlay'),
          onChanged: _editor.setTitle,
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(labelText: 'Caption', hintText: 'Add a caption'),
          maxLines: 2,
          onChanged: _editor.setCaption,
        ),
        const SizedBox(height: 16),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        color: Color(0xFF101722),
        border: Border(left: BorderSide(color: Color(0xFF273247))),
      ),
      child: scrollable ? SingleChildScrollView(child: content) : content,
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF8998B2)),
        const SizedBox(width: 7),
        Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: Color(0xFF8998B2))),
      ],
    );
  }

  Widget _aspectSelector() {
    final current = _editor.project.aspect;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: OutputAspect.values.map((aspect) {
        final selected = current == aspect;
        return ChoiceChip(
          label: Text(aspect.label),
          selected: selected,
          onSelected: (_) => _editor.setAspect(aspect),
          selectedColor: const Color(0xFF4958AF),
          backgroundColor: const Color(0xFF1A2433),
          labelStyle: TextStyle(fontSize: 11, color: selected ? Colors.white : const Color(0xFFB5C0D2)),
          side: BorderSide(color: selected ? const Color(0xFF8694FF) : const Color(0xFF303B50)),
          showCheckmark: false,
        );
      }).toList(),
    );
  }

  Widget _fitSelector() {
    return SegmentedButton<CanvasFit>(
      segments: const [
        ButtonSegment(value: CanvasFit.fit, label: Text('Fit'), icon: Icon(Icons.fit_screen)),
        ButtonSegment(value: CanvasFit.fill, label: Text('Fill / Crop'), icon: Icon(Icons.crop)),
      ],
      selected: {_editor.project.canvasFit},
      onSelectionChanged: (value) => _editor.setCanvasFit(value.first),
      showSelectedIcon: false,
    );
  }

  Widget _trimControls() {
    final project = _editor.project;
    final duration = project.sourceDurationMs;
    if (!_ready || duration <= 0) {
      return const Text('Import a video to set the trim range.', style: TextStyle(color: Color(0xFF8190A8), fontSize: 11));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('IN   ${_time(project.trimInMs)}', style: const TextStyle(fontSize: 11, color: Color(0xFFBAC5D7))),
        Slider(
          value: project.trimInMs.toDouble().clamp(0, (duration - 1).toDouble()).toDouble(),
          min: 0,
          max: (duration - 1).toDouble(),
          onChanged: _editor.setTrimIn,
        ),
        Text('OUT   ${_time(project.trimOutMs)}', style: const TextStyle(fontSize: 11, color: Color(0xFFBAC5D7))),
        Slider(
          value: project.trimOutMs.toDouble().clamp(1, duration.toDouble()).toDouble(),
          min: 1,
          max: duration.toDouble(),
          onChanged: _editor.setTrimOut,
        ),
      ],
    );
  }

  Widget _buildTimeline({bool compact = false}) {
    final project = _editor.project;
    final duration = project.sourceDurationMs;
    final max = duration > 0 ? duration.toDouble() : 1.0;
    return Container(
      height: compact ? 190 : 205,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
      decoration: const BoxDecoration(
        color: Color(0xFF101722),
        border: Border(top: BorderSide(color: Color(0xFF273247))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('TIMELINE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.4, color: Color(0xFF8998B2))),
              const Spacer(),
              Text('${_time(_position.inMilliseconds)} / ${_time(duration)}', style: const TextStyle(fontSize: 11, color: Color(0xFFB6C2D4))),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Add split marker at playhead',
                visualDensity: VisualDensity.compact,
                onPressed: !_ready ? null : _editor.addSplitMarker,
                icon: const Icon(Icons.add_box_outlined, size: 19),
              ),
            ],
          ),
          Slider(
            value: _position.inMilliseconds.toDouble().clamp(0, max).toDouble(),
            min: 0,
            max: max,
            onChanged: !_ready || duration <= 0 ? null : _seek,
          ),
          Row(
            children: [
              const Icon(Icons.video_file_outlined, size: 16, color: Color(0xFF94A4C1)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  project.videoPath?.split(Platform.pathSeparator).last ?? 'No media loaded',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFC3CCDA), fontSize: 11),
                ),
              ),
              Text('SPLIT MARKERS  ${project.splitMarkersMs.length}', style: const TextStyle(color: Color(0xFF8695AD), fontSize: 9, letterSpacing: 0.8)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: project.splitMarkersMs.map((marker) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: InputChip(
                      label: Text(_time(marker)),
                      onDeleted: () => _editor.removeSplitMarker(marker),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: const Color(0xFF202B42),
                      side: const BorderSide(color: Color(0xFF4B5C84)),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportProgress() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
      color: const Color(0xFF111927),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          const Text('Rendering MP4', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(width: 12),
          Expanded(child: LinearProgressIndicator(value: _exportProgress)),
          const SizedBox(width: 12),
          Text('${(_exportProgress * 100).round()}%', style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF090D13),
      child: const Row(
        children: [
          Text('DEPTHVIBE', style: TextStyle(fontSize: 9, color: Color(0xFF66748C), letterSpacing: 1.5, fontWeight: FontWeight.w900)),
          Spacer(),
          Text('CROSS-PLATFORM VIDEO & 3D STUDIO', style: TextStyle(fontSize: 9, color: Color(0xFF66748C), letterSpacing: 0.8)),
          Spacer(),
          Text('N TECH', style: TextStyle(fontSize: 9, color: Color(0xFF9AA7BD), fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _editor.removeListener(_refresh);
    _editor.dispose();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }
}
