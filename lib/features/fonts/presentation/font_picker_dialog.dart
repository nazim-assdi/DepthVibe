import 'package:flutter/material.dart';

import '../../../app/depthvibe_settings.dart';
import '../data/font_manager_service.dart';

class FontPickerDialog extends StatefulWidget {
  const FontPickerDialog({super.key, this.currentFamily});

  final String? currentFamily;

  static Future<FontCatalogEntry?> show(
    BuildContext context, {
    String? currentFamily,
  }) {
    return showDialog<FontCatalogEntry>(
      context: context,
      builder: (_) => FontPickerDialog(currentFamily: currentFamily),
    );
  }

  @override
  State<FontPickerDialog> createState() => _FontPickerDialogState();
}

class _FontPickerDialogState extends State<FontPickerDialog> {
  final FontManagerService _fonts = FontManagerService.instance;
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _fonts.addListener(_refresh);
    _fonts.refreshAvailableFonts();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _fonts.removeListener(_refresh);
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    final query = _query.trim().toLowerCase();
    final entries = _fonts.fonts.where((font) {
      return query.isEmpty ||
          font.displayName.toLowerCase().contains(query) ||
          (font.actualFamily ?? '').toLowerCase().contains(query) ||
          font.family.toLowerCase().contains(query);
    }).toList();

    return Dialog(
      child: SizedBox(
        width: 660,
        height: 620,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.text_fields, color: palette.accent),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      'SELECT FONT',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  Text(
                    _fonts.fonts.length.toString() + ' installed / imported',
                    style: TextStyle(
                      color: palette.secondaryText,
                      fontSize: 10,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close font picker',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search font family or style…',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              if (_fonts.isScanning) const LinearProgressIndicator(),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Text(
                          _fonts.isScanning
                              ? 'Scanning installed fonts…'
                              : 'No matching fonts found. Open Font Manager to import a font.',
                          style: TextStyle(color: palette.secondaryText),
                        ),
                      )
                    : ListView.separated(
                        itemCount: entries.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: palette.border),
                        itemBuilder: (context, index) {
                          final font = entries[index];
                          final selected = widget.currentFamily == font.family;
                          final firstLetter = font.displayName.isEmpty
                              ? 'F'
                              : font.displayName.substring(0, 1).toUpperCase();
                          return ListTile(
                            dense: true,
                            selected: selected,
                            selectedTileColor: palette.accentSoft,
                            onTap: () => Navigator.of(context).pop(font),
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: palette.accentSoft,
                              child: Text(
                                firstLetter,
                                style: TextStyle(
                                  color: palette.accent,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            title: Text(
                              font.displayName,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: palette.primaryText,
                              ),
                            ),
                            subtitle: Text(
                              'The quick brown fox  •  Aa Bb 123  •  বাংলা العربية',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: font.family,
                                fontFamilyFallback: _fonts.fallbackFamilies,
                                fontSize: 13,
                                color: palette.secondaryText,
                              ),
                            ),
                            trailing: selected
                                ? Icon(Icons.check_circle, color: palette.accent)
                                : Icon(
                                    Icons.chevron_right,
                                    color: palette.secondaryText,
                                  ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Installed PC fonts are read from the operating-system font folders. A font must support the selected script to render every glyph.',
                      style: TextStyle(
                        color: palette.secondaryText,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
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
