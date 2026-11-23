import 'package:flutter_test/flutter_test.dart';

import 'package:depthvibe/features/composition/application/composition_controller.dart';
import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/composition_project_codec.dart';
import 'package:depthvibe/features/composition/engine/obj_mesh_loader.dart';
import 'package:depthvibe/features/composition/engine/primitive_obj_factory.dart';

void main() {
  group('After Effects layer switches', () {
    test('solo, guide and shy flags survive project round trips', () {
      final controller = CompositionController();
      final layerId = controller.addLayer(LayerKind.image, name: 'Layer A');

      controller.setLayerSolo(layerId, true);
      controller.setLayerGuide(layerId, true);
      controller.setLayerShy(layerId, true);

      final encoded = CompositionProjectCodec.encodeDocument(controller.document);
      final decoded = CompositionProjectCodec.decodeDocument(encoded);
      final layer = decoded.layers.single;

      expect(layer.solo, isTrue);
      expect(layer.guideLayer, isTrue);
      expect(layer.shy, isTrue);
    });

    test('older project manifests default guide and shy flags to false', () {
      final encoded = CompositionProjectCodec.encodeDocument(
        const CompositionDocument(
          layers: [
            CompositionLayer(
              id: 'legacy_layer',
              name: 'Legacy',
              kind: LayerKind.image,
            ),
          ],
        ),
      );
      final layers = encoded['layers'] as List;
      final legacyLayer = layers.single as Map<String, Object?>;
      legacyLayer.remove('guideLayer');
      legacyLayer.remove('shy');

      final decoded = CompositionProjectCodec.decodeDocument(encoded);
      expect(decoded.layers.single.guideLayer, isFalse);
      expect(decoded.layers.single.shy, isFalse);
    });
  });

  group('3D primitive OBJ presets', () {
    const loader = ObjMeshLoader();

    test('every built-in preset produces a mesh accepted by the OBJ loader', () {
      for (final preset in PrimitiveObjFactory.presets) {
        final materials = loader.parseMaterialLibraries([
          PrimitiveObjFactory.materialFor(preset.id),
        ]);
        final mesh = loader.parse(
          PrimitiveObjFactory.objFor(preset.id),
          materials: materials,
        );

        expect(mesh.vertices.length, greaterThanOrEqualTo(3), reason: preset.id);
        expect(mesh.triangles, isNotEmpty, reason: preset.id);
        expect(mesh.maxDimension, greaterThan(0), reason: preset.id);
        expect(
          mesh.materials.containsKey('DepthVibePrimitive'),
          isTrue,
          reason: preset.id,
        );
      }
    });

    test('standard cylinder is capped and has the expected triangulated faces', () {
      final mesh = loader.parse(PrimitiveObjFactory.objFor('cylinder'));
      // 32 side quads + 32 top cap triangles + 32 bottom cap triangles.
      // The OBJ loader triangulates each side quad into two triangles.
      expect(mesh.triangles.length, 128);
    });

    test('hollow cylinder has inner and outer radii', () {
      final mesh = loader.parse(
        PrimitiveObjFactory.objFor('cylinder_hollow'),
      );
      final xValues = mesh.vertices.map((vertex) => vertex.x.abs()).toList();
      expect(xValues.reduce((a, b) => a > b ? a : b), closeTo(0.5, 0.001));
      expect(xValues.reduce((a, b) => a < b ? a : b), closeTo(0.0, 0.001));
      expect(mesh.triangles, isNotEmpty);
    });
  });
}
