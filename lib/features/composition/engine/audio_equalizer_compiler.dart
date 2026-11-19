import '../domain/composition_models.dart';

/// Converts the editor's three tone controls into native FFmpeg EQ filters.
class AudioEqualizerCompiler {
  const AudioEqualizerCompiler();

  List<String> compile(AudioSettings settings) {
    final filters = <String>[];
    _addBand(
      filters,
      frequency: 120,
      q: 0.8,
      gainDb: settings.lowEqDb,
    );
    _addBand(
      filters,
      frequency: 1000,
      q: 1,
      gainDb: settings.midEqDb,
    );
    _addBand(
      filters,
      frequency: 8000,
      q: 0.8,
      gainDb: settings.highEqDb,
    );
    return List.unmodifiable(filters);
  }

  void _addBand(
    List<String> filters, {
    required int frequency,
    required double q,
    required double gainDb,
  }) {
    final gain = gainDb.clamp(-24.0, 24.0).toDouble();
    if (gain.abs() < 0.01) return;
    filters.add(
      'equalizer=f=$frequency:t=q:w=${q.toStringAsFixed(1)}:'
      'g=${gain.toStringAsFixed(2)}',
    );
  }
}
