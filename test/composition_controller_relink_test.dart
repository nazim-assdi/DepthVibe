import 'package:depthvibe/features/composition/application/composition_controller.dart';
import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('relinks source, document, smart object and effect asset references', () {
    const document = CompositionDocument(
      layers: [
        CompositionLayer(
          id: 'layer_1',
          name: 'PSD Layer',
          kind: LayerKind.video,
          sourceUri: '/old/source.mov',
          sourceDocumentUri: '/old/source.psd',
          smartObjectSourceUri: '/old/source.psd',
          effects: [
            EffectInstance(
              id: 'effect_2',
              effectId: 'color_lut',
              name: 'Film LUT',
              assetUri: '/old/source.psd',
            ),
          ],
        ),
        CompositionLayer(
          id: 'layer_3',
          name: 'Linked duplicate',
          kind: LayerKind.image,
          sourceUri: '/old/source.psd',
        ),
      ],
      selectedLayerId: 'layer_1',
    );
    final controller = CompositionController(document: document);

    controller.relinkAssetReference('/old/source.psd', '/new/source.psd');

    expect(controller.document.layers.first.sourceUri, '/old/source.mov');
    expect(controller.document.layers.first.sourceDocumentUri, '/new/source.psd');
    expect(controller.document.layers.first.smartObjectSourceUri, '/new/source.psd');
    expect(controller.document.layers.first.effects.single.assetUri, '/new/source.psd');
    expect(controller.document.layers.last.sourceUri, '/new/source.psd');
  });

  test('relink ignores empty or identical paths', () {
    const document = CompositionDocument(
      layers: [
        CompositionLayer(
          id: 'layer',
          name: 'Layer',
          kind: LayerKind.video,
          sourceUri: '/same.mp4',
        ),
      ],
    );
    final controller = CompositionController(document: document);
    controller.relinkAssetReference('', '/new.mp4');
    controller.relinkAssetReference('/same.mp4', '/same.mp4');
    expect(controller.document.layers.single.sourceUri, '/same.mp4');
  });
}
