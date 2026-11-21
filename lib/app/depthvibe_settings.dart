import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

enum DepthVibeAppearance { dark, light, eyeComfort }

enum DepthVibePerformanceMode {
  compatibility(320, 0.55),
  balanced(480, 0.75),
  quality(640, 1.0);

  const DepthVibePerformanceMode(
    this.maximumPreviewDimension,
    this.gpuRenderScale,
  );

  final int maximumPreviewDimension;
  final double gpuRenderScale;

  String get title => switch (this) {
        DepthVibePerformanceMode.compatibility => 'Compatibility',
        DepthVibePerformanceMode.balanced => 'Balanced',
        DepthVibePerformanceMode.quality => 'Quality',
      };

  String get description => switch (this) {
        DepthVibePerformanceMode.compatibility => '320 px 3D preview · lowest preview pixel load',
        DepthVibePerformanceMode.balanced => '480 px 3D preview · recommended for most PCs',
        DepthVibePerformanceMode.quality => '640 px 3D preview · sharper detail, higher GPU load',
      };
}

class DepthVibePalette extends ThemeExtension<DepthVibePalette> {
  const DepthVibePalette({
    required this.appBackground,
    required this.toolbar,
    required this.panel,
    required this.panelRaised,
    required this.border,
    required this.primaryText,
    required this.secondaryText,
    required this.accent,
    required this.accentSoft,
  });

  final Color appBackground;
  final Color toolbar;
  final Color panel;
  final Color panelRaised;
  final Color border;
  final Color primaryText;
  final Color secondaryText;
  final Color accent;
  final Color accentSoft;

  @override
  DepthVibePalette copyWith({
    Color? appBackground,
    Color? toolbar,
    Color? panel,
    Color? panelRaised,
    Color? border,
    Color? primaryText,
    Color? secondaryText,
    Color? accent,
    Color? accentSoft,
  }) =>
      DepthVibePalette(
        appBackground: appBackground ?? this.appBackground,
        toolbar: toolbar ?? this.toolbar,
        panel: panel ?? this.panel,
        panelRaised: panelRaised ?? this.panelRaised,
        border: border ?? this.border,
        primaryText: primaryText ?? this.primaryText,
        secondaryText: secondaryText ?? this.secondaryText,
        accent: accent ?? this.accent,
        accentSoft: accentSoft ?? this.accentSoft,
      );

  @override
  DepthVibePalette lerp(ThemeExtension<DepthVibePalette>? other, double t) {
    if (other is! DepthVibePalette) return this;
    return DepthVibePalette(
      appBackground: Color.lerp(appBackground, other.appBackground, t)!,
      toolbar: Color.lerp(toolbar, other.toolbar, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      panelRaised: Color.lerp(panelRaised, other.panelRaised, t)!,
      border: Color.lerp(border, other.border, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
    );
  }
}

class DepthVibeSettingsService extends ChangeNotifier {
  DepthVibeSettingsService._();

  static final DepthVibeSettingsService instance = DepthVibeSettingsService._();

  DepthVibeAppearance _appearance = DepthVibeAppearance.dark;
  DepthVibePerformanceMode _performanceMode = DepthVibePerformanceMode.balanced;
  Directory? _settingsDirectory;
  bool _initialized = false;

  DepthVibeAppearance get appearance => _appearance;
  DepthVibePerformanceMode get performanceMode => _performanceMode;

  Future<void> initialize() async {
    if (_initialized) return;
    final support = await getApplicationSupportDirectory();
    _settingsDirectory = Directory(
      support.path + Platform.pathSeparator + 'DepthVibe' +
          Platform.pathSeparator + 'Settings',
    );
    await _settingsDirectory!.create(recursive: true);
    final file = File(
      _settingsDirectory!.path + Platform.pathSeparator + 'preferences.json',
    );
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          final value = decoded['appearance'];
          _appearance = DepthVibeAppearance.values.firstWhere(
            (item) => item.name == value,
            orElse: () => DepthVibeAppearance.dark,
          );
          final performanceValue = decoded['performanceMode'];
          _performanceMode = DepthVibePerformanceMode.values.firstWhere(
            (item) => item.name == performanceValue,
            orElse: () => DepthVibePerformanceMode.balanced,
          );
        }
      } catch (_) {
        _appearance = DepthVibeAppearance.dark;
      }
    }
    _initialized = true;
  }

  Future<void> setAppearance(DepthVibeAppearance value) async {
    if (_appearance == value) return;
    _appearance = value;
    await _save();
    notifyListeners();
  }

  Future<void> setPerformanceMode(DepthVibePerformanceMode value) async {
    if (_performanceMode == value) return;
    _performanceMode = value;
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final directory = _settingsDirectory;
    if (directory == null) return;
    final file = File(
      directory.path + Platform.pathSeparator + 'preferences.json',
    );
    final temporary = File(file.path + '.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 2,
        'appearance': _appearance.name,
        'performanceMode': _performanceMode.name,
      }),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}

class DepthVibeTheme {
  static DepthVibePalette paletteFor(DepthVibeAppearance appearance) {
    switch (appearance) {
      case DepthVibeAppearance.dark:
        return const DepthVibePalette(
          appBackground: Color(0xFF0B0E15),
          toolbar: Color(0xFF111723),
          panel: Color(0xFF151D2A),
          panelRaised: Color(0xFF1D2838),
          border: Color(0xFF303C50),
          primaryText: Color(0xFFF0F3FA),
          secondaryText: Color(0xFFA2AEC2),
          accent: Color(0xFF8795FF),
          accentSoft: Color(0xFF28345A),
        );
      case DepthVibeAppearance.light:
        return const DepthVibePalette(
          appBackground: Color(0xFFF0F3F8),
          toolbar: Color(0xFFE5EAF2),
          panel: Color(0xFFF8FAFD),
          panelRaised: Color(0xFFFFFFFF),
          border: Color(0xFFD1D9E5),
          primaryText: Color(0xFF1B2638),
          secondaryText: Color(0xFF65738A),
          accent: Color(0xFF5264D8),
          accentSoft: Color(0xFFE0E6FF),
        );
      case DepthVibeAppearance.eyeComfort:
        return const DepthVibePalette(
          appBackground: Color(0xFFF0EADB),
          toolbar: Color(0xFFE5DDC9),
          panel: Color(0xFFF7F1E3),
          panelRaised: Color(0xFFFFF9EB),
          border: Color(0xFFD3C7AF),
          primaryText: Color(0xFF353327),
          secondaryText: Color(0xFF766F5D),
          accent: Color(0xFF95713D),
          accentSoft: Color(0xFFE9DDC4),
        );
    }
  }

  static ThemeData build({
    required DepthVibeAppearance appearance,
    String? fontFamily,
    required List<String> fontFallback,
  }) {
    final palette = paletteFor(appearance);
    final brightness = appearance == DepthVibeAppearance.dark
        ? Brightness.dark
        : Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: brightness,
      surface: palette.panelRaised,
    ).copyWith(
      primary: palette.accent,
      onPrimary: Colors.white,
      secondary: palette.accent,
      onSurface: palette.primaryText,
      surface: palette.panelRaised,
      outline: palette.border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      scaffoldBackgroundColor: palette.appBackground,
      canvasColor: palette.appBackground,
      dividerColor: palette.border,
      visualDensity: VisualDensity.standard,
      extensions: [palette],
      appBarTheme: AppBarTheme(
        backgroundColor: palette.toolbar,
        foregroundColor: palette.primaryText,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: palette.primaryText,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          fontFamily: fontFamily,
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.panelRaised,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: palette.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.panelRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: palette.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.panel,
        labelStyle: TextStyle(color: palette.secondaryText),
        hintStyle: TextStyle(color: palette.secondaryText),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.accent, width: 1.5),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: palette.accent,
        selectionColor: palette.accent.withValues(alpha: 0.25),
        selectionHandleColor: palette.accent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.panelRaised,
        contentTextStyle: TextStyle(color: palette.primaryText),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
