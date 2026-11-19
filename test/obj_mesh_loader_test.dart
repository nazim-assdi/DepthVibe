import 'package:depthvibe/features/composition/engine/obj_mesh_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const loader = ObjMeshLoader();

  test('triangulates polygon faces and computes mesh bounds', () {
    final mesh = loader.parse('''
v -1 -1 0
v 1 -1 0
v 1 1 0
v -1 1 0
f 1 2 3 4
''');

    expect(mesh.vertices, hasLength(4));
    expect(mesh.triangles, hasLength(2));
    expect(mesh.center.x, 0);
    expect(mesh.center.y, 0);
    expect(mesh.maxDimension, 2);
  });

  test('supports negative OBJ vertex indices', () {
    final mesh = loader.parse('''
v 0 0 0
v 1 0 0
v 0 1 0
f -3 -2 -1
''');

    expect(mesh.triangles, hasLength(1));
    expect(mesh.triangles.single.a, 0);
    expect(mesh.triangles.single.b, 1);
    expect(mesh.triangles.single.c, 2);
  });

  test('applies MTL diffuse colour and transparency to a face', () {
    final materials = loader.parseMaterialLibraries([
      '''
newmtl ocean
Kd 0.10 0.35 0.80
d 0.65
''',
    ]);
    final mesh = loader.parse('''
v 0 0 0
v 1 0 0
v 0 1 0
usemtl ocean
f 1 2 3
''', materials: materials);

    final material = mesh.materialFor(mesh.triangles.single);
    expect(material.red, closeTo(0.10, 0.0001));
    expect(material.green, closeTo(0.35, 0.0001));
    expect(material.blue, closeTo(0.80, 0.0001));
    expect(material.alpha, closeTo(0.65, 0.0001));
  });

  test('rejects OBJ files without a valid triangle', () {
    expect(
      () => loader.parse('v 0 0 0\nv 1 0 0\n'),
      throwsFormatException,
    );
  });
}
