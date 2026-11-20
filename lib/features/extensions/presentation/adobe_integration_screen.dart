import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../data/adobe_bridge_service.dart';

class AdobeIntegrationScreen extends StatefulWidget {
  const AdobeIntegrationScreen({super.key});

  @override
  State<AdobeIntegrationScreen> createState() => _AdobeIntegrationScreenState();
}

class _AdobeIntegrationScreenState extends State<AdobeIntegrationScreen> {
  final AdobeBridgeService _bridge = AdobeBridgeService.instance;

  @override
  void initState() {
    super.initState();
    _bridge.addListener(_refresh);
    _bridge.start();
  }

  @override
  void dispose() {
    _bridge.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
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

  Future<void> _configureHttps() async {
    final certificate = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pem', 'crt', 'cer'],
    );
    final certificatePath = certificate?.path;
    if (certificatePath == null || certificatePath.isEmpty) return;

    final key = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['key', 'pem'],
    );
    final keyPath = key?.path;
    if (keyPath == null || keyPath.isEmpty) return;

    await _bridge.startSecure(
      certificateChain: File(certificatePath),
      privateKey: File(keyPath),
    );
    if (_bridge.isRunning && _bridge.scheme == 'https') {
      _message('HTTPS Adobe bridge is ready. Re-pair your Adobe panel.');
    } else {
      _message('HTTPS bridge could not start: ' + (_bridge.lastError ?? 'unknown error'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bridge,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Adobe Integration')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.hub_outlined,
                          color: Color(0xFF9CB5FF),
                          size: 25,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'DepthVibe Adobe Bridge',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Icon(
                          _bridge.isRunning
                              ? Icons.check_circle
                              : Icons.warning_amber,
                          color: _bridge.isRunning
                              ? const Color(0xFF76D7B0)
                              : Colors.orange,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _bridge.isRunning
                          ? 'Listening on ' + _bridge.baseUrl
                          : 'Bridge is not available on this platform.',
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (_bridge.lastError != null)
                      Text(
                        _bridge.lastError!,
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 11,
                        ),
                      ),
                    if (_bridge.isRunning) ...[
                      const SizedBox(height: 14),
                      const Text(
                        'ONE-TIME PAIRING CODE',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.2,
                          color: Color(0xFF9BAAC2),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        _bridge.pairingCode ?? '------',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                        ),
                      ),
                      const Text(
                        'Enter this code inside the DepthVibe panel in Premiere Pro '
                        'or After Effects. The bridge only listens on localhost.',
                        style: TextStyle(
                          color: Color(0xFF9BAAC2),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _configureHttps,
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Configure HTTPS for Adobe UXP'),
                      ),
                      const Text(
                        'On macOS, UXP requires HTTPS for local network requests. '
                        'Create a certificate with 127.0.0.1 in its SAN, add it to '
                        'your operating-system trust store, then choose its PEM/CRT '
                        'certificate and private key here.',
                        style: TextStyle(
                          color: Color(0xFF9BAAC2),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'CONNECTED ADOBE PANELS',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.2,
                color: Color(0xFF9BAAC2),
                fontWeight: FontWeight.w800,
              ),
            ),
            if (_bridge.sessions.isEmpty)
              const Card(
                child: ListTile(
                  title: Text('No Adobe panels connected'),
                  subtitle: Text(
                    'Pair a Premiere Pro or After Effects panel with the code above.',
                  ),
                ),
              )
            else
              for (final session in _bridge.sessions)
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.link,
                      color: Color(0xFF76D7B0),
                    ),
                    title: Text(session.hostApp),
                    subtitle: Text('Version: ' + session.hostVersion),
                    trailing: IconButton(
                      tooltip: 'Disconnect panel',
                      onPressed: () {
                        _bridge.disconnectSession(session.sessionId);
                      },
                      icon: const Icon(Icons.link_off),
                    ),
                  ),
                ),
            const SizedBox(height: 8),
            const Text(
              'SUPPORTED HOST CONNECTIONS',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.2,
                color: Color(0xFF9BAAC2),
                fontWeight: FontWeight.w800,
              ),
            ),
            for (final item in const [
              (
                name: 'Premiere Pro',
                route: 'UXP panel · 25.6 and later',
                status: 'Supported host adapter',
              ),
              (
                name: 'After Effects',
                route: 'CEP panel · current stable releases',
                status: 'Legacy compatibility adapter',
              ),
              (
                name: 'After Effects Beta',
                route: 'UXP panel · 27.1 public beta',
                status: 'Experimental adapter',
              ),
            ])
              Card(
                child: ListTile(
                  leading: const Icon(Icons.extension),
                  title: Text(item.name),
                  subtitle: Text(item.route + '\n' + item.status),
                  isThreeLine: true,
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'The Adobe panel runs inside Adobe, not inside Flutter. It can '
              'pair with this bridge, read the current DepthVibe composition, '
              'read the effect catalog, and send a composition JSON document '
              'back after an explicit action. Native .aex/.prm plug-ins and '
              'Adobe-only effects still execute only inside their Adobe host.',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF97A6BD),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
