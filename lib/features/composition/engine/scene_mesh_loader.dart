import '../domain/composition_models.dart';
import 'gltf_mesh_loader.dart';
import 'obj_mesh_loader.dart';

/// Dispatches local OBJ, glTF JSON and GLB binary model imports.
class SceneMeshLoader {
  const SceneMeshLoader({
    this.objLoader = const ObjMeshLoader(),
    this.gltfLoader = const GltfMeshLoader(),
  });

  final ObjMeshLoader objLoader;
  final GltfMeshLoader gltfLoader;

  Future<ObjMesh> load(String path) {
    final extension = path.toLowerCase().split('.').last;
    return switch (extension) {
      'obj' => objLoader.load(path),
      'gltf' || 'glb' => gltfLoader.load(path),
      _ => Future<ObjMesh>.error(
          FormatException('Supported mesh formats are OBJ, GLTF and GLB.'),
        ),
    };
  }
}
