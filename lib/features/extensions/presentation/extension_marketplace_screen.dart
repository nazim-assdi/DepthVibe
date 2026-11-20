import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../data/extension_marketplace_service.dart';
import '../data/marketplace_models.dart';
import '../data/publisher_trust_store.dart';

class ExtensionMarketplaceScreen extends StatefulWidget {
  const ExtensionMarketplaceScreen({super.key});

  @override
  State<ExtensionMarketplaceScreen> createState() =>
      _ExtensionMarketplaceScreenState();
}

class _ExtensionMarketplaceScreenState
    extends State<ExtensionMarketplaceScreen> {
  final ExtensionMarketplaceService _market =
      ExtensionMarketplaceService.instance;
  final PublisherTrustStore _trust = PublisherTrustStore.instance;
  final TextEditingController _urlController = TextEditingController();
  bool _keyBusy = false;

  @override
  void initState() {
    super.initState();
    _urlController.text = _market.catalogUrl;
    _market.addListener(_refresh);
    _trust.addListener(_refresh);
    _market.initialize().then((_) {
      if (mounted) _urlController.text = _market.catalogUrl;
    });
  }

  @override
  void dispose() {
    _market.removeListener(_refresh);
    _trust.removeListener(_refresh);
    _urlController.dispose();
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

  Future<void> _refreshCatalog() async {
    try {
      await _market.setCatalogUrl(_urlController.text);
      final catalog = await _market.refreshCatalog();
      if (_market.autoUpdateEnabled) {
        final updated = await _market.applyAutomaticDepthVibeUpdates();
        _message(
          'Loaded ' +
              catalog.entries.length.toString() +
              ' signed entries. Applied ' +
              updated.toString() +
              ' automatic updates.',
        );
      } else {
        _message(
          'Loaded ' + catalog.entries.length.toString() + ' signed entries.',
        );
      }
    } catch (error) {
      _message('Marketplace refresh failed: ' + error.toString());
    }
  }

  Future<void> _importPublisherKey() async {
    if (_keyBusy) return;
    setState(() => _keyBusy = true);
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['dvpub', 'json'],
      );
      final path = picked?.path;
      if (path == null || path.isEmpty) return;
      final candidate = await _trust.parsePublisherKeyFile(File(path));
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Trust this publisher key?'),
          content: SelectableText(
            candidate.displayName +
                '\n' +
                candidate.publisherId +
                '\nKey ID: ' +
                candidate.keyId +
                '\nSHA-256 fingerprint:\n' +
                candidate.fingerprint +
                '\n\nOnly trust a key whose fingerprint you verified with its '
                    'publisher through a separate trusted channel.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Trust publisher'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
      await _trust.trustPublisher(candidate);
      _message('Publisher trusted. Refresh the signed catalog.');
    } catch (error) {
      _message('Publisher key rejected: ' + error.toString());
    } finally {
      if (mounted) setState(() => _keyBusy = false);
    }
  }

  Future<void> _toggleAutoUpdate(bool enabled) async {
    try {
      await _market.setAutoUpdateEnabled(enabled);
      if (enabled && _urlController.text.trim().isNotEmpty) {
        await _market.refreshCatalog();
        await _market.applyAutomaticDepthVibeUpdates();
      }
    } catch (error) {
      _message('Automatic update check failed: ' + error.toString());
    }
  }

  Future<void> _revokePublisher(TrustedPublisher publisher) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revoke publisher key?'),
        content: Text(
          'Future marketplace catalogs from ' +
              publisher.displayName +
              ' signed by key ' +
              publisher.keyId +
              ' will no longer be accepted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Revoke key'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await _trust.revokePublisher(publisher.publisherId, publisher.keyId);
      _message('Publisher key revoked.');
    }
  }

  Future<void> _install(MarketplaceExtension entry) async {
    try {
      await _market.install(entry);
      switch (entry.packageType) {
        case MarketplacePackageType.depthVibe:
          _message('Installed ' + entry.name + ' ' + entry.version + '.');
          break;
        case MarketplacePackageType.premiereUxp:
          _message(
            'Opened the .ccx installer. Confirm installation in Creative Cloud Desktop.',
          );
          break;
        case MarketplacePackageType.afterEffectsCep:
          _message(
            'Downloaded the CEP package. Follow the included installation guide.',
          );
          break;
        case MarketplacePackageType.afterEffectsUxpBeta:
          _message(
            'Downloaded the After Effects Beta UXP adapter package. Install through Adobe UXP tooling.',
          );
          break;
      }
      if (mounted) await _market.refreshCatalog();
    } catch (error) {
      _message('Install/update failed: ' + error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _market,
      builder: (context, _) {
        final catalog = _market.catalog;
        final updates = _market.updates.map((item) => item.entry.id).toSet();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Extension Marketplace'),
            actions: [
              IconButton(
                tooltip: 'Import trusted publisher key',
                onPressed: _keyBusy ? null : _importPublisherKey,
                icon: const Icon(Icons.verified_user_outlined),
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Signed marketplace feed',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _urlController,
                        decoration: const InputDecoration(
                          labelText: 'HTTPS catalog URL',
                          hintText: 'https://publisher.example/index.json',
                          isDense: true,
                        ),
                        keyboardType: TextInputType.url,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _market.isBusy ? null : _refreshCatalog,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Refresh catalog'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text('Auto-update'),
                          Switch.adaptive(
                            value: _market.autoUpdateEnabled,
                            onChanged: _toggleAutoUpdate,
                          ),
                        ],
                      ),
                      Text(
                        _trust.publishers.length.toString() +
                            ' trusted publisher keys · ' +
                            updates.length.toString() +
                            ' updates available',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF93A2BA),
                        ),
                      ),
                      if (_market.lastError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _market.lastError!,
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_trust.publishers.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Text(
                    'TRUSTED PUBLISHERS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.3,
                      color: Color(0xFF94A5C1),
                    ),
                  ),
                ),
                for (final publisher in _trust.publishers)
                  Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.verified_user,
                        color: Color(0xFF76D7B0),
                      ),
                      title: Text(publisher.displayName),
                      subtitle: Text(
                        publisher.keyId +
                            '\nSHA-256: ' +
                            publisher.fingerprint,
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: 'Revoke publisher key',
                        onPressed: () => _revokePublisher(publisher),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ),
                  ),
              ],
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 16, 4, 8),
                child: Text(
                  'AVAILABLE EXTENSIONS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                    color: Color(0xFF94A5C1),
                  ),
                ),
              ),
              if (catalog == null)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      'No verified catalog loaded. Import a publisher .dvpub key, '
                      'verify its fingerprint with the publisher, then refresh '
                      'an HTTPS feed signed by that key.',
                    ),
                  ),
                )
              else if (catalog.entries.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      'This trusted catalog has no published packages yet.',
                    ),
                  ),
                ),
              for (final entry in catalog?.entries ??
                  const <MarketplaceExtension>[])
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (updates.contains(entry.id))
                              const Chip(
                                label: Text('Update'),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.publisherName + ' · v' + entry.version,
                          style: const TextStyle(
                            color: Color(0xFF9BAAC1),
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          entry.description,
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final host in entry.targetHosts)
                              Chip(
                                label: Text(host),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                        if (entry.minimumHostVersion.isNotEmpty)
                          Text(
                            'Minimum host version: ' + entry.minimumHostVersion,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF95A4BA),
                            ),
                          ),
                        if (entry.releaseNotes.isNotEmpty)
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text(
                              'Release notes',
                              style: TextStyle(fontSize: 11),
                            ),
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  entry.releaseNotes,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonalIcon(
                            onPressed:
                                _market.isBusy ? null : () => _install(entry),
                            icon: const Icon(Icons.download, size: 16),
                            label: Text(entry.installLabel),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              const Text(
                'Publisher signatures use Ed25519. The catalog is verified before '
                'display; each downloaded archive is checked against its signed '
                'SHA-256 digest. Auto-update installs only DepthVibe .dvext '
                'packages. Adobe packages are opened through Adobe/OS installers '
                'and still require host-side user confirmation.',
                style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFF8C9BB2),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
