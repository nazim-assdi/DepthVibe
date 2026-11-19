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

  int get groupCount => layers.where((layer) => layer.isGroup).length;

  int get clippedLayerCount =>
      layers.where((layer) => layer.clipping != 0).length;

  int get smartObjectCount =>
      layers.where((layer) => layer.smartObjectResourceId != null).length;
}

class PhotoshopImportService {
  const PhotoshopImportService();

  List<EffectInstance> _adjustmentEffects(
    PsdAdjustment? adjustment,
    int sourceIndex,
  ) {
    if (adjustment == null) return const [];
    final effects = <EffectInstance>[];
    final prefix = 'psd_${sourceIndex}_';

    void add(String effectId, String name, Map<String, double> parameters) {
      effects.add(EffectInstance(
        id: prefix + effectId,
        effectId: effectId,
        name: name,
        parameters: parameters,
      ));
    }

    if (adjustment case PsdBrightnessContrastAdjustment value) {
      final brightness = (value.brightness / 100)
          .clamp(-1.0, 1.0)
          .toDouble();
      final contrast = (1 + value.contrast / 100)
          .clamp(0.0, 3.0)
          .toDouble();
      if (brightness.abs() >= 0.001) {
        add('brightness', 'Photoshop Brightness', {'value': brightness});
      }
      if ((contrast - 1).abs() >= 0.001) {
        add('contrast', 'Photoshop Contrast', {'value': contrast});
      }
    } else if (adjustment case PsdSingleValueAdjustment value) {
      if (value.type == PsdAdjustmentType.posterize) {
        add('posterize', 'Photoshop Posterize', {
          'levels': value.value.clamp(2, 32).toDouble(),
        });
      } else if (value.type == PsdAdjustmentType.threshold) {
        add('threshold', 'Photoshop Threshold', {
          'value': value.value.clamp(0, 255).toDouble(),
        });
      }
    } else if (adjustment is PsdInvertAdjustment) {
      add('invert', 'Photoshop Invert', const {});
    }

    return List.unmodifiable(effects);
  }

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

    final groupStack = <int>[];
    for (var index = 0; index < document.layers.length; index++) {
      final layer = document.layers[index];
      final sectionType = layer.sectionType;

      // PSD layer records are flat. A folder-opening record starts a group;
      // its matching boundingDivider closes that group and is not a visual layer.
      if (sectionType == PsdSectionType.boundingDivider) {
        if (groupStack.isNotEmpty) groupStack.removeLast();
        continue;
      }

      final isGroup = sectionType == PsdSectionType.openFolder ||
          sectionType == PsdSectionType.closedFolder;
      final parentGroup = groupStack.isEmpty ? null : groupStack.last;
      final rectangle = layer.rectangle;
      final isVisible = layer.visible;
      final textContent = layer.typeTool?.content.text;
      final adjustment = layer.adjustment;
      final isAdjustment = adjustment != null;
      String assetPath = '';
      String? smartObjectSourceUri;
      String? smartObjectResourceId;

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
            cache.path +
                Platform.pathSeparator +
                'psd_' +
                stamp.toString() +
                '_layer_' +
                index.toString() +
                '.png',
          );
          await output.writeAsBytes(pngBytes, flush: true);
          assetPath = output.path;
        } catch (_) {
          // A non-raster text, fill, adjustment or smart-object record remains
          // editable metadata even when this decoder has no raster fallback.
        }
      }

      final smartObject = layer.smartObject;
      smartObjectResourceId = smartObject?.linkedResourceId;
      if (smartObject != null) {
        final linkedResource = document.linkedResourceFor(layer);
        final embeddedBytes = linkedResource?.data;
        if (linkedResource?.type == PsdLinkedResourceType.embedded &&
            embeddedBytes != null &&
            embeddedBytes.isNotEmpty) {
          final extension = linkedResource!.name.toLowerCase().endsWith('.psb')
              ? '.psb'
              : '.psd';
          final safeName = linkedResource.name
              .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
              .replaceAll(RegExp(r'\.+$'), '');
          final objectFile = File(
            cache.path +
                Platform.pathSeparator +
                'smart_' +
                stamp.toString() +
                '_' +
                index.toString() +
                '_' +
                (safeName.isEmpty ? 'embedded' : safeName) +
                extension,
          );
          await objectFile.writeAsBytes(embeddedBytes, flush: true);
          smartObjectSourceUri = objectFile.path;
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
        parentGroupSourceIndex: parentGroup,
        clipping: layer.clipping,
        smartObjectSourceUri: smartObjectSourceUri,
        smartObjectResourceId: smartObjectResourceId,
        adjustmentKey: adjustment?.blockKey,
        adjustmentEffects: _adjustmentEffects(adjustment, index),
      ));

      if (isGroup) groupStack.add(index);
    }

    // In PSD order, a clipping chain sits above its base layer. Scan from the
    // bottom of each group upward so every clipped layer points to that base.
    final clippingBases = <int?, int>{};
    final indexedAssets = <PhotoshopLayerAsset>[];
    for (final asset in assets.reversed) {
      int? baseIndex = asset.clippingBaseSourceIndex;
      if (!asset.isGroup) {
        if (asset.clipping != 0) {
          baseIndex = clippingBases[asset.parentGroupSourceIndex];
        } else {
          clippingBases[asset.parentGroupSourceIndex] = asset.sourceIndex;
        }
      }
      indexedAssets.add(PhotoshopLayerAsset(
        sourceIndex: asset.sourceIndex,
        name: asset.name,
        assetPath: asset.assetPath,
        left: asset.left,
        top: asset.top,
        width: asset.width,
        height: asset.height,
        opacity: asset.opacity,
        blendMode: asset.blendMode,
        visible: asset.visible,
        isGroup: asset.isGroup,
        isAdjustment: asset.isAdjustment,
        textContent: asset.textContent,
        parentGroupSourceIndex: asset.parentGroupSourceIndex,
        clippingBaseSourceIndex: baseIndex,
        clipping: asset.clipping,
        smartObjectSourceUri: asset.smartObjectSourceUri,
        smartObjectResourceId: asset.smartObjectResourceId,
        adjustmentKey: asset.adjustmentKey,
        adjustmentEffects: asset.adjustmentEffects,
      ));
    }
    assets
      ..clear()
      ..addAll(indexedAssets.reversed);

    return PhotoshopImportResult(
      path: path,
      width: document.width,
      height: document.height,
      layers: List.unmodifiable(assets),
    );
  }
}
