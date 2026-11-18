import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:psdkit/psdkit.dart';

import '../domain/composition_models.dart';

class PhotoshopImportResult {
  const PhotoshopImportResult({
    required this.path,
    required this.width,
    required this.height,
    required this.layers,
  });

  final String path;
  final int width;
  final int height;
  final List<PhotoshopLayerAsset> layers;

  int get visibleLayerCount =>
      layers.where((layer) => layer.visible && !layer.isGroup).length;
}

class PhotoshopImportService {
  const PhotoshopImportService();

  Future<PhotoshopImportResult> importDocument(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Photoshop document not found.', path);
    }

    final document = PsdCodec.decode(await file.readAsBytes());
    final cache = Directory(
      '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}DepthVibe${Platform.pathSeparator}PhotoshopLayers',
    );
    await cache.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final assets = <PhotoshopLayerAsset>[];

    for (var index = 0; index < document.layers.length; index++) {
      final layer = document.layers[index];
      final rectangle = layer.rectangle;
      final isGroup = layer.sectionType.name != 'other';
      final isVisible = layer.visible;
      final textContent = layer.typeTool?.content.text;
      final isAdjustment = layer.adjustment != null;
      String assetPath = '';

      if (!isGroup && rectangle.width > 0 && rectangle.height > 0) {
        try {
          final rgba = PsdPixels.decodeLayer(document, layer);
          final raster = img.Image.fromBytes(
            width: rgba.width,
            height: rgba.height,
            bytes: rgba.bytes.buffer,
            bytesOffset: rgba.bytes.offsetInBytes,
            numChannels: 4,
          );
          final pngBytes = img.encodePng(raster, level: 3);
          final output = File(
            '${cache.path}${Platform.pathSeparator}psd_${stamp}_layer_${index}.png',
          );
          await output.writeAsBytes(pngBytes, flush: true);
          assetPath = output.path;
        } catch (_) {
          // Keep non-raster text, fill and adjustment records editable without
          // aborting the entire import when an individual channel is unsupported.
        }
      }

      assets.add(PhotoshopLayerAsset(
        sourceIndex: index,
        name: layer.name,
        assetPath: assetPath,
        left: rectangle.left,
        top: rectangle.top,
        width: rectangle.width,
        height: rectangle.height,
        opacity: layer.opacity,
        blendMode: layer.blendMode,
        visible: isVisible,
        isGroup: isGroup,
        isAdjustment: isAdjustment,
        textContent: textContent,
      ));
    }

    return PhotoshopImportResult(
      path: path,
      width: document.width,
      height: document.height,
      layers: List.unmodifiable(assets),
    );
  }
}
