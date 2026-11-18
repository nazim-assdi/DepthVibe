import 'package:camera/camera.dart';
import 'package:material_ui/material_ui.dart';

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _controller;
  bool _initializing = true;
  bool _recording = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('no_camera', 'No camera was detected on this device.');
      }
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: true,
        fps: 30,
        videoBitrate: 8000000,
        audioBitrate: 128000,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
        _error = null;
      });
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.description ?? error.code;
        _initializing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _initializing = false;
      });
    }
  }

  Future<void> _toggleRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      if (_recording) {
        final file = await controller.stopVideoRecording();
        if (!mounted) return;
        Navigator.of(context).pop(file.path);
      } else {
        await controller.startVideoRecording();
        if (mounted) setState(() => _recording = true);
      }
    } on CameraException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.description ?? error.code)),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Camera Capture'),
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: _initializing
            ? const CircularProgressIndicator()
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  )
                : controller == null
                    ? const Text('Camera unavailable')
                    : AspectRatio(
                        aspectRatio: controller.value.aspectRatio,
                        child: CameraPreview(controller),
                      ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(20),
        child: FilledButton.icon(
          onPressed: controller == null ? null : _toggleRecording,
          icon: Icon(_recording ? Icons.stop_circle : Icons.fiber_manual_record),
          label: Text(_recording ? 'Stop and use recording' : 'Start recording'),
          style: FilledButton.styleFrom(
            backgroundColor: _recording
                ? const Color(0xFFB32636)
                : const Color(0xFF6F7DFF),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
    );
  }
}
