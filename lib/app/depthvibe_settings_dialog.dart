import 'package:flutter/material.dart';

import 'depthvibe_brand_mark.dart';
import 'depthvibe_settings.dart';

class DepthVibeSettingsDialog extends StatefulWidget {
  const DepthVibeSettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const DepthVibeSettingsDialog(),
    );
  }

  @override
  State<DepthVibeSettingsDialog> createState() =>
      _DepthVibeSettingsDialogState();
}

class _DepthVibeSettingsDialogState extends State<DepthVibeSettingsDialog> {
  final DepthVibeSettingsService _settings =
      DepthVibeSettingsService.instance;
  String _section = 'View';

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 900,
        height: 590,
        child: Row(
          children: [
            SizedBox(
              width: 205,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.toolbar,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(18),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 18, 12, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          DepthVibeBrandMark(size: 30, showWordmark: false),
                          SizedBox(width: 10),
                          Text(
                            'SETTINGS',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _navItem('General', Icons.tune),
                      _navItem('View', Icons.visibility_outlined),
                      const Spacer(),
                      Text(
                        'DEPTHVIBE  •  N TECH',
                        style: TextStyle(
                          color: palette.secondaryText,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.9,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 20, 26, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _section.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _section == 'View'
                                    ? 'Personalise the workspace appearance.'
                                    : 'General application preferences.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: palette.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close settings',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    if (_section == 'View') ...[
                      const Text(
                        'APP APPEARANCE',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Choose a comfortable colour theme for Video Studio and Compositor.',
                        style: TextStyle(
                          fontSize: 11,
                          color: palette.secondaryText,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: AnimatedBuilder(
                          animation: _settings,
                          builder: (context, _) => LayoutBuilder(
                            builder: (context, constraints) {
                              final compact = constraints.maxWidth < 560;
                              final themes = [
                                _ThemeChoice(
                                  appearance: DepthVibeAppearance.dark,
                                  title: 'Dark',
                                  subtitle: 'Professional low-light workspace',
                                  background: const Color(0xFF0B0E15),
                                  panel: const Color(0xFF1D2838),
                                  text: const Color(0xFFF0F3FA),
                                  accent: const Color(0xFF8795FF),
                                  icon: Icons.dark_mode_outlined,
                                ),
                                _ThemeChoice(
                                  appearance: DepthVibeAppearance.light,
                                  title: 'White',
                                  subtitle: 'Bright, clean studio interface',
                                  background: const Color(0xFFF0F3F8),
                                  panel: Colors.white,
                                  text: const Color(0xFF1B2638),
                                  accent: const Color(0xFF5264D8),
                                  icon: Icons.light_mode_outlined,
                                ),
                                _ThemeChoice(
                                  appearance: DepthVibeAppearance.eyeComfort,
                                  title: 'Eye Comfort',
                                  subtitle: 'Warm, softer tones for long sessions',
                                  background: const Color(0xFFF0EADB),
                                  panel: const Color(0xFFFFF9EB),
                                  text: const Color(0xFF353327),
                                  accent: const Color(0xFF95713D),
                                  icon: Icons.remove_red_eye_outlined,
                                ),
                              ];
                              if (compact) {
                                return ListView(
                                  children: [
                                    for (final choice in themes)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 10),
                                        child: _themeCard(choice),
                                      ),
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var i = 0; i < themes.length; i++)
                                    Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          right: i == themes.length - 1 ? 0 : 12,
                                        ),
                                        child: _themeCard(themes[i]),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 16,
                            color: palette.accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Theme preference is saved automatically on this device.',
                              style: TextStyle(
                                fontSize: 10,
                                color: palette.secondaryText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Expanded(
                        child: Center(
                          child: Text(
                            'More general preferences will be added here.',
                            style: TextStyle(color: palette.secondaryText),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(String label, IconData icon) {
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    final active = _section == label;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => setState(() => _section = label),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            color: active ? palette.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: active ? palette.accent : palette.secondaryText,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                  color: active ? palette.primaryText : palette.secondaryText,
                ),
              ),
              const Spacer(),
              if (active)
                Icon(Icons.chevron_right, size: 16, color: palette.accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _themeCard(_ThemeChoice choice) {
    final selected = _settings.appearance == choice.appearance;
    final palette = Theme.of(context).extension<DepthVibePalette>()!;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _settings.setAppearance(choice.appearance),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? palette.accentSoft.withValues(alpha: 0.35) : palette.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? palette.accent : palette.border,
            width: selected ? 1.7 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  color: choice.background,
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      Container(
                        height: 18,
                        decoration: BoxDecoration(
                          color: choice.panel,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 7),
                            for (var i = 0; i < 3; i++)
                              Container(
                                width: 5,
                                height: 5,
                                margin: const EdgeInsets.only(right: 3),
                                decoration: BoxDecoration(
                                  color: choice.accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 7),
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 27,
                              decoration: BoxDecoration(
                                color: choice.panel,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: choice.panel,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Center(
                                  child: Text(
                                    'DV',
                                    style: TextStyle(
                                      color: choice.accent,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        height: 13,
                        decoration: BoxDecoration(
                          color: choice.panel,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(choice.icon, size: 17, color: choice.accent),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    choice.title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, size: 18, color: palette.accent),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              choice.subtitle,
              style: TextStyle(fontSize: 10, color: palette.secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeChoice {
  const _ThemeChoice({
    required this.appearance,
    required this.title,
    required this.subtitle,
    required this.background,
    required this.panel,
    required this.text,
    required this.accent,
    required this.icon,
  });

  final DepthVibeAppearance appearance;
  final String title;
  final String subtitle;
  final Color background;
  final Color panel;
  final Color text;
  final Color accent;
  final IconData icon;
}
