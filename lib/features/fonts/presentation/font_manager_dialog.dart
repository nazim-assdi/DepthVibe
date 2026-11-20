import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../data/font_manager_service.dart';

class FontManagerDialog extends StatefulWidget {
  const FontManagerDialog({super.key});

  @override
  State<FontManagerDialog> createState() => _FontManagerDialogState();
}

class _FontManagerDialogState extends State<FontManagerDialog> {
  final FontManagerService _fonts = FontManagerService.instance;
  final TextEditingController _search = TextEditingController();
  final TextEditingController _fallback = TextEditingController();
  String _query = '';
  String? _notice;
  bool _working = false;

  static const _preview =
      'DepthVibe  •  English  •  বাংলা  •  العربية  •  हिन्दी  •  اردو  •  中文  •  日本語  •  ไทย  •  Français  •  Ελληνικά  •  😀';

  @override
  void initState() {
    super.initState();
    _fallback.text = _fonts.fallbackFamilies.join(', ');
    _fonts.addListener(_refreshUi);
    _refresh();
  }

  void _refreshUi() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    setState(() => _working = true);
    try {
      await _fonts.refreshAvailableFonts();
    } catch (error) {
      _notice = 'Font scan failed: ' + error.toString();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _importFont() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['ttf', 'otf'],
      );
      final path = picked?.path;
      if (path == null) return;
      setState(() => _working = true);
      final entry = await _fonts.importFont(path);
      if (!mounted) return;
      setState(() => _notice = 'Imported ' + entry.displayName);
    } catch (error) {
      if (mounted) setState(() => _notice = 'Import failed: ' + error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }


  Future<void> _importFolder() async {
    try {
      final selected = await FilePicker.pickDirectory();
      final path = selected?.toFilePath();
      if (path == null) return;
      setState(() => _working = true);
      final result = await _fonts.importFontFolder(path);
      if (mounted) {
        setState(() => _notice =
            'Imported ' + result.imported.toString() +
            ' fonts; skipped ' + result.skipped.toString() + '.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Folder import failed: ' + error.toString());
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _setDefault(FontCatalogEntry? entry) async {
    try {
      await _fonts.setAppDefault(entry);
      if (mounted) {
        setState(() => _notice = entry == null
            ? 'Using the operating-system default font.'
            : 'App font set to ' + entry.displayName);
      }
    } catch (error) {
      if (mounted) setState(() => _notice = 'Could not load font: ' + error.toString());
    }
  }

  @override
  void dispose() {
    _fonts.removeListener(_refreshUi);
    _search.dispose();
    _fallback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fonts = _fonts.fonts.where((font) {
      final query = _query.toLowerCase();
      return query.isEmpty ||
          font.displayName.toLowerCase().contains(query) ||
          font.family.toLowerCase().contains(query);
    }).toList();

    return Dialog(
      child: SizedBox(
        width: 920,
        height: 680,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.font_download_outlined, size: 23),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'GLOBAL FONT MANAGER',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Scan installed system fonts',
                    onPressed: _working ? null : _refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                  OutlinedButton.icon(
                    onPressed: _working ? null : _importFolder,
                    icon: const Icon(Icons.folder_open, size: 17),
                    label: const Text('Import folder'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: _working ? null : _importFont,
                    icon: const Icon(Icons.add, size: 17),
                    label: const Text('Import TTF / OTF'),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search installed and imported font files…',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _setDefault(null),
                    icon: const Icon(Icons.settings_backup_restore, size: 15),
                    label: const Text('System default'),
                  ),
                  Text(
                    _fonts.activeFamily == null
                        ? 'Current app font: System default'
                        : 'Current app font: ' + _fonts.activeFamily!,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9EAEC5)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_working) const LinearProgressIndicator(),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _notice!,
                    style: const TextStyle(fontSize: 11, color: Color(0xFFB9C9E1)),
                  ),
                ),
              Expanded(
                child: fonts.isEmpty
                    ? const Center(
                        child: Text('No fonts found. Import a licensed .ttf or .otf file.'),
                      )
                    : ListView.separated(
                        itemCount: fonts.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: Color(0xFF29354A)),
                        itemBuilder: (context, index) {
                          final font = fonts[index];
                          final active = _fonts.activeFamily == font.family;
                          return ListTile(
                            dense: true,
                            title: Text(
                              font.displayName,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _preview,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: font.family,
                                    fontFamilyFallback: _fonts.fallbackFamilies,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  font.isImported ? 'Imported into DepthVibe' : font.path,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Color(0xFF8292A9),
                                  ),
                                ),
                              ],
                            ),
                            isThreeLine: true,
                            trailing: Wrap(
                              spacing: 3,
                              children: [
                                if (active)
                                  const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: Icon(Icons.check_circle, color: Color(0xFF69D6A0)),
                                  )
                                else
                                  IconButton(
                                    tooltip: 'Use as global app font',
                                    onPressed: () => _setDefault(font),
                                    icon: const Icon(Icons.check_circle_outline),
                                  ),
                                if (font.isImported)
                                  IconButton(
                                    tooltip: 'Remove imported font',
                                    onPressed: () async {
                                      await _fonts.removeImportedFont(font);
                                      if (mounted) {
                                        setState(() => _notice =
                                            'Removed ' + font.displayName +
                                            '. Restart DepthVibe to release its in-memory face.');
                                      }
                                    },
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const Divider(color: Color(0xFF29354A)),
              const Text(
                'LANGUAGE FALLBACK FAMILIES',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              TextField(
                controller: _fallback,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Comma-separated font family names',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Fallback is tried in order, then the device OS fallback is used. Font files remain subject to their licences.',
                      style: TextStyle(fontSize: 10, color: Color(0xFF8D9DB5)),
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: () async {
                      await _fonts.setFallbackFamilies(_fallback.text);
                      if (mounted) setState(() => _notice = 'Language fallback list saved.');
                    },
                    child: const Text('Save fallback'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
