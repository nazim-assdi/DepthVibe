
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../data/extension_manager_service.dart';

class ExtensionManagerScreen extends StatefulWidget {
  const ExtensionManagerScreen({super.key});

  @override
  State<ExtensionManagerScreen> createState() =>
      _ExtensionManagerScreenState();
}

class _ExtensionManagerScreenState extends State<ExtensionManagerScreen> {
  final ExtensionManagerService _manager = ExtensionManagerService.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _manager.addListener(_refresh);
    _manager.initialize();
  }

  @override
  void dispose() {
    _manager.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _install() async {
    if (_busy) return;
    setState(() => _busy = true);
    File? temporaryCopy;
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['dvext', 'zip'],
      );
      if (picked == null) return;

      final packagePath = picked.path;
      final File packageFile;
      if (packagePath != null && packagePath.isNotEmpty) {
        packageFile = File(packagePath);
      } else {
        final temporaryDirectory = await getTemporaryDirectory();
        temporaryCopy = File(
          temporaryDirectory.path +
              Platform.pathSeparator +
              'depthvibe_extension_' +
              DateTime.now().microsecondsSinceEpoch.toString() +
              '.dvext',
        );
        final output = temporaryCopy.openWrite();
        try {
          await for (final chunk in picked.readAsByteStream()) {
            output.add(chunk);
          }
          await output.flush();
        } finally {
          await output.close();
        }
        packageFile = temporaryCopy;
      }

      final installed = await _manager.installFromFile(packageFile);
      if (mounted) {
        _message(
          'Installed ' +
              installed.manifest.name +
              ' · ' +
              installed.effectCount.toString() +
              ' effects',
        );
      }
    } catch (error) {
      if (mounted) _message('Install failed: ' + error.toString());
    } finally {
      if (temporaryCopy != null && await temporaryCopy.exists()) {
        await temporaryCopy.delete();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uninstall(InstalledExtension extension) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove extension?'),
        content: Text(
          'Remove "' +
              extension.manifest.name +
              '" and its installed files? Projects using its effects will '
                  'keep their saved effect references.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _manager.uninstall(extension.manifest.id);
      if (mounted) _message('Extension removed.');
    } catch (error) {
      if (mounted) _message('Could not remove extension: ' + error.toString());
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _manager,
      builder: (context, _) {
        final extensions = _manager.installed;
        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Extension Manager',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            actions: [
              IconButton(
                tooltip: 'Refresh extensions',
                onPressed: _busy ? null : _manager.refresh,
                icon: const Icon(Icons.refresh),
              ),
              const SizedBox(width: 6),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _busy ? null : _install,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            label: Text(_busy ? 'Installing…' : 'Install .dvext'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.extension, color: Color(0xFF9CAEFF)),
                          SizedBox(width: 10),
                          Text(
                            'Extend your studio',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Install effect packs and bundled LUT looks. Installed '
                        'effects appear in the Compositor effect library.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFABB8CC),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _InfoPill(
                            icon: Icons.check_circle_outline,
                            label: extensions.length.toString() + ' installed',
                          ),
                          _InfoPill(
                            icon: Icons.auto_awesome,
                            label: _manager.enabledEffectCount.toString() +
                                ' enabled effects',
                          ),
                          const _InfoPill(
                            icon: Icons.shield_outlined,
                            label: 'No external code execution',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_manager.initializationError != null)
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.warning_amber,
                      color: Colors.orange,
                    ),
                    title: const Text('Extension storage unavailable'),
                    subtitle: Text(_manager.initializationError!),
                    trailing: TextButton(
                      onPressed: _manager.refresh,
                      child: const Text('Retry'),
                    ),
                  ),
                ),
              for (final warning in _manager.loadWarnings)
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.warning_amber,
                      color: Colors.orange,
                    ),
                    title: const Text('An extension could not be loaded'),
                    subtitle: Text(warning),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 16, 4, 8),
                child: Text(
                  'INSTALLED EXTENSIONS',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF94A5C1),
                  ),
                ),
              ),
              if (extensions.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.extension_outlined,
                          size: 34,
                          color: Color(0xFF71809B),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'No extensions installed',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Install a .dvext package to add effects to your studio.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF97A6BD),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              for (final extension in extensions)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFF26304A),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(
                                Icons.extension,
                                color: Color(0xFFB7C4FF),
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    extension.manifest.name,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    extension.manifest.author +
                                        ' · v' +
                                        extension.manifest.version,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF94A3BA),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: extension.enabled,
                              onChanged: _busy
                                  ? null
                                  : (value) async {
                                      try {
                                        await _manager.setEnabled(
                                          extension.manifest.id,
                                          value,
                                        );
                                      } catch (error) {
                                        _message(
                                          'Could not update extension: ' +
                                              error.toString(),
                                        );
                                      }
                                    },
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'remove') {
                                  _uninstall(extension);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Uninstall'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (extension.manifest.description.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 49, top: 4),
                            child: Text(
                              extension.manifest.description,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFABB8CC),
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(left: 49, top: 8),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final effect in extension.manifest.effects)
                                _InfoPill(
                                  icon: Icons.auto_awesome,
                                  label: effect.name,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              const Text(
                'Security: .dvext packages may contain a manifest and .cube LUT '
                'assets only. Scripts, native libraries, arbitrary FFmpeg '
                'commands and executable code are rejected.',
                style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFF7F8EA7),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF202A3D),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFFB8C5E1)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Color(0xFFCBD5E6),
            ),
          ),
        ],
      ),
    );
  }
}
