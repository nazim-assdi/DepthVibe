import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/depthvibe_brand_mark.dart';
import '../../../app/depthvibe_settings.dart';
import '../../../app/depthvibe_settings_dialog.dart';
import '../../../features/composition/presentation/composition_workspace.dart';
import '../../../features/extensions/presentation/extension_manager_screen.dart';
import '../../fonts/presentation/font_manager_dialog.dart';
import '../../../features/media/data/media_picker_service.dart';
import '../../../features/media/data/media_duration_parser.dart';
import '../../../features/media/presentation/camera_capture_screen.dart';
import '../application/editor_controller.dart';
import '../data/video_export_service.dart';
import '../domain/editor_project.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    this.startupWarning,
    this.mediaPlaybackAvailable = true,
    this.mediaProcessingAvailable = true,
  });

  final String? startupWarning;
  final bool mediaPlaybackAvailable;
  final bool mediaProcessingAvailable;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final EditorController _editor = EditorController();
  Player? _player;
  VideoController? _videoController;
  DepthVibePerformanceMode? _videoControllerProfile;
  String? _currentVideoPath;
  bool _reconfiguringPreview = false;
  bool _openingVideo = false;
  bool _profileChangedDuringOpen = false;
  bool _checkingFirstVideoFrame = false;
  int _videoRendererFallbackStep = 0;
  final VideoExportService _exporter = const VideoExportService();

  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  Duration _position = Duration.zero;
  bool _ready = false;
  bool _playbackAvailable = false;
  String? _previewError;
  bool _exporting = false;
  double _exportProgress = 0;
  String? _status;

  @override
  void initState() {
    super.initState();
    _status = widget.startupWarning;
    DepthVibeSettingsService.instance.addListener(_onPreviewSettingsChanged);

    // The project editor and file picker do not depend on a media player.
    // Create Player only after the app has confirmed MediaKit initialised.
    if (widget.mediaPlaybackAvailable) {
      try {
        final player = Player();
        _player = player;
        _attachPlayerStreams(player);
      } catch (error, stackTrace) {
        _previewError = error.toString();
        debugPrint('DepthVibe media player unavailable: $error\\n$stackTrace');
      }
    } else {
      _previewError = 'The optional media playback engine did not initialise.';
    }

    _editor.addListener(_refresh);
  }

  void _attachPlayerStreams(Player player) {
    _durationSubscription = player.stream.duration.listen((duration) {
      _editor.setSourceDuration(duration);
    });
    _positionSubscription = player.stream.position.listen((position) {
      if (!mounted) return;
      setState(() => _position = position);
      _editor.setPlayhead(position);
    });
  }

  void _onPreviewSettingsChanged() {
    if (!mounted) return;
    final profile = DepthVibeSettingsService.instance.performanceMode;
    if (_videoControllerProfile != null &&
        _videoControllerProfile != profile) {
      _videoRendererFallbackStep = 0;
    }
    if (_openingVideo &&
        _videoControllerProfile != null &&
        _videoControllerProfile != profile) {
      _profileChangedDuringOpen = true;
    } else if (_currentVideoPath != null &&
        _videoControllerProfile != null &&
        _videoControllerProfile != profile) {
      unawaited(_reconfigureVideoPreview());
    }
    setState(() {});
  }

  Future<void> _reconfigureVideoPreview() async {
    if (_reconfiguringPreview ||
        !mounted ||
        _currentVideoPath == null ||
        _player == null) {
      return;
    }

    _reconfiguringPreview = true;
    final path = _currentVideoPath!;
    final oldPlayer = _player!;
    final resumePlaying = oldPlayer.state.playing;
    final resumePosition = _position > Duration.zero
        ? _position
        : oldPlayer.state.position;

    setState(() {
      _playbackAvailable = false;
      _videoController = null;
      _videoControllerProfile = null;
      _status = 'Updating video preview renderer…';
    });

    try {
      // Wait until the old Video widget is unmounted before releasing the
      // native output texture owned by its Player.
      await WidgetsBinding.instance.endOfFrame;
      await _durationSubscription?.cancel();
      await _positionSubscription?.cancel();
      _durationSubscription = null;
      _positionSubscription = null;
      await oldPlayer.dispose();

      if (!mounted) return;
      final player = Player();
      _player = player;
      _attachPlayerStreams(player);

      await player.open(Media(path), play: false).timeout(
        const Duration(seconds: 20),
      );
      await player.setRate(_editor.project.speed).timeout(
        const Duration(seconds: 5),
      );
      await player.setVolume(_editor.project.muted ? 0 : 100).timeout(
        const Duration(seconds: 5),
      );
      if (resumePosition > Duration.zero) {
        await player.seek(resumePosition).timeout(
          const Duration(seconds: 8),
        );
      }
      if (resumePlaying) await player.play().timeout(
        const Duration(seconds: 8),
      );

      if (!mounted) return;
      _videoControllerProfile =
          DepthVibeSettingsService.instance.performanceMode;
      _previewError = null;
      setState(() {
        _playbackAvailable = true;
        _position = resumePosition;
        _status = 'Video preview renderer updated';
      });
    } catch (error, stackTrace) {
      debugPrint(
        'DepthVibe preview renderer reconfiguration failed: '
        '$error\\n$stackTrace',
      );
      if (mounted) {
        _previewError = error.toString();
        setState(() {
          _playbackAvailable = false;
          _status =
              'Preview renderer could not be restarted; timeline editing remains available';
        });
      }
    } finally {
      _reconfiguringPreview = false;
      if (mounted &&
          _profileChangedDuringOpen &&
          _videoControllerProfile !=
              DepthVibeSettingsService.instance.performanceMode) {
        _profileChangedDuringOpen = false;
        unawaited(_reconfigureVideoPreview());
      }
    }
  }

  Future<void> _verifyFirstVideoFrame(VideoController controller) async {
    if (_checkingFirstVideoFrame) return;
    _checkingFirstVideoFrame = true;
    try {
      await controller.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 8),
      );
      if (!mounted || !identical(_videoController, controller)) return;
      if (_videoRendererFallbackStep > 0) {
        setState(() {
          _status = 'Video preview recovered with alternate renderer';
        });
      }
    } catch (error, stackTrace) {
      if (!mounted ||
          !identical(_videoController, controller) ||
          _player?.state.playing != true) {
        return;
      }
      debugPrint(
        'DepthVibe first video frame was not rendered: $error\\n$stackTrace',
      );
      if (_videoRendererFallbackStep == 0) {
        final profile = DepthVibeSettingsService.instance.performanceMode;
        _videoRendererFallbackStep =
            profile.enableVideoHardwareAcceleration ? 1 : 2;
        if (mounted) {
          setState(() {
            _status = _videoRendererFallbackStep == 1
                ? 'Video surface stalled; switching to CPU renderer…'
                : 'CPU video surface stalled; switching to GPU renderer…';
          });
        }
        await _reconfigureVideoPreview();
      } else if (mounted) {
        _previewError =
            'The selected video renderer did not produce a frame. '
            'Try another Performance mode or reload this video.';
        setState(() {
          _playbackAvailable = false;
          _status = 'Video preview could not render the first frame';
        });
      }
    } finally {
      _checkingFirstVideoFrame = false;
    }
  }

  Future<void> _primePausedVideoPreview() async {
    if (!mounted || !_playbackAvailable || _player == null) return;

    // Build the Video widget and its native output surface before requesting
    // the first rendered frame. Keep audio muted while warming the surface.
    await WidgetsBinding.instance.endOfFrame;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!mounted || !_playbackAvailable) return;
      final player = _player;
      final controller = _videoControllerForPreview();
      if (player == null || controller == null) return;

      try {
        await player.setVolume(0).timeout(const Duration(seconds: 3));
        await player.play().timeout(const Duration(seconds: 5));
        await _verifyFirstVideoFrame(controller);
      } catch (error, stackTrace) {
        debugPrint(
          'DepthVibe initial paused-preview warm-up failed: '
          '$error\\n$stackTrace',
        );
        if (mounted &&
            identical(_player, player) &&
            _videoRendererFallbackStep == 0) {
          final profile = DepthVibeSettingsService.instance.performanceMode;
          _videoRendererFallbackStep =
              profile.enableVideoHardwareAcceleration ? 1 : 2;
          await _reconfigureVideoPreview();
        } else {
          _previewError = error.toString();
          if (mounted) setState(() => _playbackAvailable = false);
          return;
        }
      }

      if (!mounted || !_playbackAvailable) return;
      // A failed first renderer may have been replaced by the automatic
      // fallback. Prime the replacement on the next pass.
      if (!identical(_player, player) ||
          !identical(_videoController, controller)) {
        await WidgetsBinding.instance.endOfFrame;
        continue;
      }

      try {
        await player.pause().timeout(const Duration(seconds: 5));
        await player.seek(Duration.zero).timeout(const Duration(seconds: 5));
        await player
            .setVolume(_editor.project.muted ? 0 : 100)
            .timeout(const Duration(seconds: 3));
        if (mounted) {
          setState(() {
            _position = Duration.zero;
            _status = 'Video preview ready';
          });
        }
      } catch (error, stackTrace) {
        debugPrint(
          'DepthVibe paused-preview restore failed: $error\\n$stackTrace',
        );
        if (mounted) {
          _previewError = error.toString();
          setState(() {
            _status = 'Preview frame rendered; playback controls need a retry';
          });
        }
      }
      return;
    }
  }

  VideoController? _videoControllerForPreview() {
    final player = _player;
    if (player == null || !_playbackAvailable || _reconfiguringPreview) {
      return null;
    }
    final profile = DepthVibeSettingsService.instance.performanceMode;
    if (_videoController != null && _videoControllerProfile != profile) {
      unawaited(_reconfigureVideoPreview());
      return null;
    }
    if (_videoController != null) return _videoController;

    _videoControllerProfile = profile;
    _videoController = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: switch (_videoRendererFallbackStep) {
          1 => false,
          2 => true,
          _ => profile.enableVideoHardwareAcceleration,
        },
        hwdec: switch (_videoRendererFallbackStep) {
          1 => 'no',
          2 => 'auto-safe',
          _ => profile.videoHardwareDecoder,
        },
        scale: profile.videoOutputScale,
      ),
    );
    final controller = _videoController!;
    if (player.state.playing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_videoController, controller)) {
          unawaited(_verifyFirstVideoFrame(controller));
        }
      });
    }
    return controller;
  }

  Future<Duration?> _probeMediaDuration(String path) async {
    if (!widget.mediaProcessingAvailable) return null;
    try {
      final session = await FFprobeKit
          .getMediaInformationAsync(path)
          .timeout(const Duration(seconds: 20));
      if (session is! MediaInformationSession) return null;
      final seconds = session.getMediaInformation()?.duration;
      return MediaDurationParser.parseSeconds(seconds);
    } catch (error, stackTrace) {
      debugPrint('DepthVibe media metadata probe failed: $error\\n$stackTrace');
      return null;
    }
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
    _currentVideoPath = path;
    _videoRendererFallbackStep = 0;
    _openingVideo = true;
    _profileChangedDuringOpen = false;
    _editor.loadVideo(path);

    // Activate the project and timeline immediately. Native playback and
    // metadata probing are optional enhancements, never a prerequisite for
    // importing media or editing project properties.
    if (mounted) {
      setState(() {
        _ready = true;
        _playbackAvailable = false;
        _position = Duration.zero;
        _status = 'Media imported — preparing preview; timeline is ready';
      });
    }

    var playbackReady = false;
    final player = _player;
    if (player != null) {
      try {
        await player
            .open(Media(path), play: false)
            .timeout(const Duration(seconds: 20));
        await player
            .setRate(_editor.project.speed)
            .timeout(const Duration(seconds: 5));
        await player
            .setVolume(_editor.project.muted ? 0 : 100)
            .timeout(const Duration(seconds: 5));
        playbackReady = true;
        _previewError = null;
      } catch (error, stackTrace) {
        _previewError = error.toString();
        debugPrint(
          'DepthVibe video preview failed; keeping edit mode active: $error\\n$stackTrace',
        );
      }
    }

    // FFprobe reads duration without creating a GPU video surface. This keeps
    // the timeline usable when the playback/output backend cannot start.
    if (!playbackReady && _editor.project.sourceDurationMs <= 0) {
      final duration = await _probeMediaDuration(path);
      if (duration != null) _editor.setSourceDuration(duration);
    }

    _openingVideo = false;
    if (!mounted) return;
    setState(() {
      _playbackAvailable = playbackReady;
      _position = Duration.zero;
      _status = playbackReady
          ? 'Media loaded'
          : 'Media imported — CPU timeline editing remains available; preview is unavailable';
    });
    if (_profileChangedDuringOpen) {
      _profileChangedDuringOpen = false;
      unawaited(_reconfigureVideoPreview());
    } else if (playbackReady) {
      unawaited(_primePausedVideoPreview());
    }
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

  void _openExtensions() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ExtensionManagerScreen(),
      ),
    );
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
    if (mounted) setState(() => _position = position);
    _editor.setPlayhead(position);
    final player = _player;
    if (_playbackAvailable && player != null) {
      try {
        await player.seek(position);
      } catch (error) {
        _showMessage('Preview seek unavailable: $error');
      }
    }
  }

  Future<void> _setMuted(bool value) async {
    _editor.setMuted(value);
    final player = _player;
    if (_playbackAvailable && player != null) {
      try {
        await player.setVolume(value ? 0 : 100);
      } catch (error) {
        _showMessage('Preview audio control unavailable: $error');
      }
    }
  }

  Future<void> _changeSpeed(double value) async {
    _editor.setSpeed(value);
    final player = _player;
    if (_playbackAvailable && player != null) {
      try {
        await player.setRate(value);
      } catch (error) {
        _showMessage('Preview speed control unavailable: $error');
      }
    }
  }

  Future<void> _export() async {
    if (_exporting) return;
    if (!widget.mediaProcessingAvailable) {
      _showMessage(
        'The video processing engine is unavailable. Import and editing remain available.',
      );
      return;
    }
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
            ? 'Saved to Movies/DepthVibe'
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
              ? 'MP4 saved to Movies/DepthVibe.\nGallery reference: ${result.galleryUri}\nApp copy: ${file.path}'
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
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: primary ? Colors.white : palette.primaryText,
        backgroundColor: primary ? palette.accent : palette.panelRaised,
        side: BorderSide(
          color: primary ? palette.accent : palette.border,
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
              Builder(
                builder: (context) {
                  final palette = Theme.of(context).extension<DepthVibePalette>()!;
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    color: palette.toolbar,
                child: Text(
                  _status!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.secondaryText, fontSize: 11),
                  ),
                );
                },
              ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: palette.toolbar,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          const DepthVibeBrandMark(size: 40),
          const Spacer(),
          if (MediaQuery.sizeOf(context).width > 700)
            Text('VIDEO STUDIO  /  PRO WORKSPACE', style: TextStyle(color: palette.secondaryText, fontSize: 10, letterSpacing: 1)),
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
          if (MediaQuery.sizeOf(context).width > 720)
            _toolButton(
              icon: Icons.extension,
              label: 'Extensions',
              onPressed: _openExtensions,
            )
          else
            IconButton(
              tooltip: 'Extensions',
              onPressed: _openExtensions,
              icon: const Icon(Icons.extension),
            ),
          if (MediaQuery.sizeOf(context).width > 720)
            _toolButton(
              icon: Icons.font_download_outlined,
              label: 'Fonts',
              onPressed: _openFontManager,
            )
          else
            IconButton(
              tooltip: 'Global Font Manager',
              onPressed: _openFontManager,
              icon: const Icon(Icons.font_download_outlined),
            ),
          _toolButton(
            icon: Icons.layers,
            label: 'Compositor',
            onPressed: _exporting
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CompositionWorkspace(),
                      ),
                    ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Settings · View and appearance',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          _toolButton(
            icon: Icons.ios_share,
            label: 'Export MP4',
            onPressed: _exporting ||
                    !_editor.project.hasVideo ||
                    !widget.mediaProcessingAvailable
                ? null
                : _export,
            primary: true,
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewArea({bool compact = false}) {
    final project = _editor.project;
    final width = compact ? double.infinity : null;
    final videoController = _videoControllerForPreview();
    final previewContent = AspectRatio(
      aspectRatio: project.aspect.ratio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: const Color(0xFF070A10),
              child: !_ready
                  ? _buildEmptyPreview()
                  : videoController == null
                      ? _buildSoftwareFallbackPreview()
                      : Transform.rotate(
                          angle: project.rotationDegrees * math.pi / 180,
                          child: Video(
                            controller: videoController,
                            controls: NoVideoControls,
                            fit: project.canvasFit == CanvasFit.fit
                                ? BoxFit.contain
                                : BoxFit.cover,
                          ),
                        ),
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
                          textDirection: RegExp(r'[\u0590-\u08FF\uFB1D-\uFEFF]')
                                  .hasMatch(project.title)
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, shadows: [Shadow(blurRadius: 8, color: Colors.black)]),
                        ),
                      if (project.caption.isNotEmpty)
                        Text(
                          project.caption,
                          textAlign: TextAlign.center,
                          textDirection: RegExp(r'[\u0590-\u08FF\uFB1D-\uFEFF]')
                                  .hasMatch(project.caption)
                              ? TextDirection.rtl
                              : TextDirection.ltr,
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
    final player = _player;
    final canPlay = _ready && _playbackAvailable && player != null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          onPressed: !_ready ? null : () => _seek(0),
          icon: const Icon(Icons.replay),
        ),
        const SizedBox(width: 12),
        IconButton.filled(
          onPressed: !canPlay
              ? null
              : () async {
                  final activePlayer = _player;
                  if (activePlayer == null) return;
                  try {
                    if (activePlayer.state.playing) {
                      await activePlayer.pause();
                    } else {
                      await activePlayer.play();
                      final controller = _videoController;
                      if (controller != null) {
                        unawaited(_verifyFirstVideoFrame(controller));
                      }
                    }
                    if (mounted) setState(() {});
                  } catch (error) {
                    if (mounted) {
                      setState(() {
                        _playbackAvailable = false;
                        _previewError = error.toString();
                        _status = 'Playback stopped; timeline editing remains active';
                      });
                    }
                  }
                },
          icon: Icon(
            player?.state.playing == true ? Icons.pause : Icons.play_arrow,
          ),
        ),
        const SizedBox(width: 12),
        IconButton.filledTonal(
          onPressed: _ready ? _editor.rotateClockwise : null,
          icon: const Icon(Icons.rotate_right),
        ),
      ],
    );
  }

  Widget _buildSoftwareFallbackPreview() {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_filter_outlined, size: 48, color: palette.accent),
            const SizedBox(height: 12),
            Text(
              'CPU EDITING MODE',
              style: TextStyle(
                color: palette.primaryText,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              _previewError ??
                  'Media is imported. Playback preview is unavailable, but the timeline and project controls remain active.',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.secondaryText, fontSize: 11),
            ),
            if (_currentVideoPath != null) ...[
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(
                    onPressed: _reconfiguringPreview
                        ? null
                        : () => _openVideo(_currentVideoPath!),
                    icon: const Icon(Icons.refresh, size: 15),
                    label: const Text('RETRY PREVIEW'),
                  ),
                  TextButton(
                    onPressed: _reconfiguringPreview
                        ? null
                        : () {
                            final profile =
                                DepthVibeSettingsService.instance.performanceMode;
                            _videoRendererFallbackStep =
                                _videoRendererFallbackStep == 1 ? 2 : 1;
                            _videoControllerProfile = profile;
                            unawaited(_reconfigureVideoPreview());
                          },
                    child: const Text('SWITCH RENDERER'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
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

    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(left: BorderSide(color: palette.border)),
      ),
      child: scrollable ? SingleChildScrollView(child: content) : content,
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return Row(
      children: [
        Icon(icon, size: 15, color: palette.secondaryText),
        const SizedBox(width: 7),
        Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: palette.secondaryText)),
      ],
    );
  }

  Widget _aspectSelector() {
    final current = _editor.project.aspect;
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: OutputAspect.values.map((aspect) {
        final selected = current == aspect;
        return ChoiceChip(
          label: Text(aspect.label),
          selected: selected,
          onSelected: (_) => _editor.setAspect(aspect),
          selectedColor: palette.accent,
          backgroundColor: palette.panelRaised,
          labelStyle: TextStyle(fontSize: 11, color: selected ? Colors.white : palette.primaryText),
          side: BorderSide(color: selected ? palette.accent : palette.border),
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
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    final duration = project.sourceDurationMs;
    final max = duration > 0 ? duration.toDouble() : 1.0;
    return Container(
      height: compact ? 190 : 205,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
      decoration: BoxDecoration(
        color: palette.toolbar,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('TIMELINE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.4, color: palette.secondaryText)),
              const Spacer(),
              Text('${_time(_position.inMilliseconds)} / ${_time(duration)}', style: TextStyle(fontSize: 11, color: palette.primaryText)),
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
              Icon(Icons.video_file_outlined, size: 16, color: palette.secondaryText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  project.videoPath?.split(Platform.pathSeparator).last ?? 'No media loaded',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.primaryText, fontSize: 11),
                ),
              ),
              Text('SPLIT MARKERS  ${project.splitMarkersMs.length}', style: TextStyle(color: palette.secondaryText, fontSize: 9, letterSpacing: 0.8)),
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
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: palette.appBackground,
      child: Row(
        children: [
          Text('DEPTHVIBE', style: TextStyle(fontSize: 9, color: palette.secondaryText, letterSpacing: 1.5, fontWeight: FontWeight.w900)),
          const Spacer(),
          Text('CROSS-PLATFORM VIDEO & 3D STUDIO', style: TextStyle(fontSize: 9, color: palette.secondaryText, letterSpacing: 0.8)),
          const Spacer(),
          Text('N TECH', style: TextStyle(fontSize: 9, color: palette.secondaryText, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    DepthVibeSettingsService.instance.removeListener(_onPreviewSettingsChanged);
    _editor.removeListener(_refresh);
    _editor.dispose();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _player?.dispose();
    super.dispose();
  }
}
