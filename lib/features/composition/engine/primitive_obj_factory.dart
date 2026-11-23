import 'dart:math' as math;

/// Procedural OBJ meshes share the normal model import, preview and export path.
class PrimitiveMeshPreset {
  const PrimitiveMeshPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.segmentCount,
  });

  final String id;
  final String name;
  final String description;
  final int segmentCount;
}

class PrimitiveObjFactory {
  PrimitiveObjFactory._();

  static const presets = <PrimitiveMeshPreset>[
    PrimitiveMeshPreset(id: 'cylinder', name: 'Cylinder', description: '32-sided capped cylinder', segmentCount: 32),
    PrimitiveMeshPreset(id: 'cylinder_smooth', name: 'Cylinder · Smooth', description: '64 radial segments', segmentCount: 64),
    PrimitiveMeshPreset(id: 'cylinder_low_poly', name: 'Cylinder · Low Poly', description: 'Eight-sided stylized cylinder', segmentCount: 8),
    PrimitiveMeshPreset(id: 'cylinder_hollow', name: 'Cylinder · Hollow', description: 'Open bore with inner wall and annular caps', segmentCount: 32),
    PrimitiveMeshPreset(id: 'cone', name: 'Cone', description: 'Capped cone with a pointed apex', segmentCount: 32),
    PrimitiveMeshPreset(id: 'cube', name: 'Cube', description: 'Six-sided quad cube', segmentCount: 0),
    PrimitiveMeshPreset(id: 'sphere', name: 'Sphere', description: 'UV sphere with 24 latitude and 32 longitude segments', segmentCount: 32),
    PrimitiveMeshPreset(id: 'torus', name: 'Torus', description: '32 × 12 segment donut mesh', segmentCount: 32),
    PrimitiveMeshPreset(id: 'plane', name: 'Plane', description: 'Two-sided rectangular plane', segmentCount: 0),
    PrimitiveMeshPreset(id: 'pyramid', name: 'Pyramid', description: 'Square pyramid with a quad base', segmentCount: 0),
    PrimitiveMeshPreset(id: 'triangular_prism', name: 'Triangular Prism', description: 'Triangular prism with quad side faces', segmentCount: 0),
  ];

  static PrimitiveMeshPreset? find(String id) {
    for (final preset in presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  static String objFor(String id) {
    final preset = find(id);
    if (preset == null) {
      throw ArgumentError.value(id, 'id', 'Unknown primitive preset.');
    }
    final mesh = _ObjBuilder(id);
    switch (id) {
      case 'cylinder':
      case 'cylinder_smooth':
      case 'cylinder_low_poly':
        _cylinder(mesh, preset.segmentCount);
        break;
      case 'cylinder_hollow':
        _hollowCylinder(mesh, preset.segmentCount);
        break;
      case 'cone':
        _cone(mesh, preset.segmentCount);
        break;
      case 'cube':
        _cube(mesh);
        break;
      case 'sphere':
        _sphere(mesh, preset.segmentCount, 24);
        break;
      case 'torus':
        _torus(mesh, preset.segmentCount, 12);
        break;
      case 'plane':
        _plane(mesh);
        break;
      case 'pyramid':
        _pyramid(mesh);
        break;
      case 'triangular_prism':
        _triangularPrism(mesh);
        break;
      default:
        throw ArgumentError.value(id, 'id', 'Unknown primitive preset.');
    }
    return mesh.build();
  }

  static void _cylinder(_ObjBuilder mesh, int segments) {
    final bottom = <int>[];
    final top = <int>[];
    for (var index = 0; index < segments; index++) {
      final angle = 2 * math.pi * index / segments;
      final x = 0.5 * math.cos(angle);
      final z = 0.5 * math.sin(angle);
      bottom.add(mesh.vertex(x, -0.5, z));
      top.add(mesh.vertex(x, 0.5, z));
    }
    final bottomCenter = mesh.vertex(0, -0.5, 0);
    final topCenter = mesh.vertex(0, 0.5, 0);
    for (var index = 0; index < segments; index++) {
      final next = (index + 1) % segments;
      mesh.face([bottom[index], top[index], top[next], bottom[next]]);
      mesh.face([bottomCenter, bottom[next], bottom[index]]);
      mesh.face([topCenter, top[index], top[next]]);
    }
  }

  static void _hollowCylinder(_ObjBuilder mesh, int segments) {
    final outerBottom = <int>[];
    final outerTop = <int>[];
    final innerBottom = <int>[];
    final innerTop = <int>[];
    const innerRadius = 0.27;
    for (var index = 0; index < segments; index++) {
      final angle = 2 * math.pi * index / segments;
      final cosine = math.cos(angle);
      final sine = math.sin(angle);
      outerBottom.add(mesh.vertex(0.5 * cosine, -0.5, 0.5 * sine));
      outerTop.add(mesh.vertex(0.5 * cosine, 0.5, 0.5 * sine));
      innerBottom.add(mesh.vertex(innerRadius * cosine, -0.5, innerRadius * sine));
      innerTop.add(mesh.vertex(innerRadius * cosine, 0.5, innerRadius * sine));
    }
    for (var index = 0; index < segments; index++) {
      final next = (index + 1) % segments;
      mesh.face([outerBottom[index], outerTop[index], outerTop[next], outerBottom[next]]);
      mesh.face([innerBottom[index], innerBottom[next], innerTop[next], innerTop[index]]);
      mesh.face([outerTop[index], innerTop[index], innerTop[next], outerTop[next]]);
      mesh.face([outerBottom[index], outerBottom[next], innerBottom[next], innerBottom[index]]);
    }
  }

  static void _cone(_ObjBuilder mesh, int segments) {
    final base = <int>[];
    for (var index = 0; index < segments; index++) {
      final angle = 2 * math.pi * index / segments;
      base.add(mesh.vertex(0.5 * math.cos(angle), -0.5, 0.5 * math.sin(angle)));
    }
    final center = mesh.vertex(0, -0.5, 0);
    final apex = mesh.vertex(0, 0.5, 0);
    for (var index = 0; index < segments; index++) {
      final next = (index + 1) % segments;
      mesh.face([base[index], apex, base[next]]);
      mesh.face([center, base[next], base[index]]);
    }
  }

  static void _cube(_ObjBuilder mesh) {
    final v = <int>[
      mesh.vertex(-0.5, -0.5, -0.5),
      mesh.vertex(0.5, -0.5, -0.5),
      mesh.vertex(0.5, 0.5, -0.5),
      mesh.vertex(-0.5, 0.5, -0.5),
      mesh.vertex(-0.5, -0.5, 0.5),
      mesh.vertex(0.5, -0.5, 0.5),
      mesh.vertex(0.5, 0.5, 0.5),
      mesh.vertex(-0.5, 0.5, 0.5),
    ];
    mesh.face([v[0], v[3], v[2], v[1]]);
    mesh.face([v[4], v[5], v[6], v[7]]);
    mesh.face([v[0], v[1], v[5], v[4]]);
    mesh.face([v[3], v[7], v[6], v[2]]);
    mesh.face([v[0], v[4], v[7], v[3]]);
    mesh.face([v[1], v[2], v[6], v[5]]);
  }

  static void _sphere(_ObjBuilder mesh, int longitudeSegments, int latitudeSegments) {
    final rings = <List<int>>[];
    for (var latitude = 1; latitude < latitudeSegments; latitude++) {
      final phi = -math.pi / 2 + math.pi * latitude / latitudeSegments;
      final ring = <int>[];
      final radius = 0.5 * math.cos(phi);
      final y = 0.5 * math.sin(phi);
      for (var longitude = 0; longitude < longitudeSegments; longitude++) {
        final theta = 2 * math.pi * longitude / longitudeSegments;
        ring.add(mesh.vertex(radius * math.cos(theta), y, radius * math.sin(theta)));
      }
      rings.add(ring);
    }
    final bottom = mesh.vertex(0, -0.5, 0);
    final top = mesh.vertex(0, 0.5, 0);
    final first = rings.first;
    final last = rings.last;
    for (var index = 0; index < longitudeSegments; index++) {
      final next = (index + 1) % longitudeSegments;
      mesh.face([bottom, first[next], first[index]]);
      mesh.face([last[index], last[next], top]);
    }
    for (var ringIndex = 0; ringIndex < rings.length - 1; ringIndex++) {
      final lower = rings[ringIndex];
      final upper = rings[ringIndex + 1];
      for (var index = 0; index < longitudeSegments; index++) {
        final next = (index + 1) % longitudeSegments;
        mesh.face([lower[index], lower[next], upper[next], upper[index]]);
      }
    }
  }

  static void _torus(_ObjBuilder mesh, int majorSegments, int minorSegments) {
    const majorRadius = 0.34;
    const minorRadius = 0.16;
    final rings = <List<int>>[];
    for (var major = 0; major < majorSegments; major++) {
      final u = 2 * math.pi * major / majorSegments;
      final ring = <int>[];
      for (var minor = 0; minor < minorSegments; minor++) {
        final v = 2 * math.pi * minor / minorSegments;
        final radial = majorRadius + minorRadius * math.cos(v);
        ring.add(mesh.vertex(radial * math.cos(u), minorRadius * math.sin(v), radial * math.sin(u)));
      }
      rings.add(ring);
    }
    for (var major = 0; major < majorSegments; major++) {
      final nextMajor = (major + 1) % majorSegments;
      for (var minor = 0; minor < minorSegments; minor++) {
        final nextMinor = (minor + 1) % minorSegments;
        mesh.face([rings[major][minor], rings[nextMajor][minor], rings[nextMajor][nextMinor], rings[major][nextMinor]]);
      }
    }
  }

  static void _plane(_ObjBuilder mesh) {
    final a = mesh.vertex(-0.5, -0.5, 0);
    final b = mesh.vertex(0.5, -0.5, 0);
    final c = mesh.vertex(0.5, 0.5, 0);
    final d = mesh.vertex(-0.5, 0.5, 0);
    mesh.face([a, b, c, d]);
    mesh.face([d, c, b, a]);
  }

  static void _pyramid(_ObjBuilder mesh) {
    final a = mesh.vertex(-0.5, -0.5, -0.5);
    final b = mesh.vertex(0.5, -0.5, -0.5);
    final c = mesh.vertex(0.5, -0.5, 0.5);
    final d = mesh.vertex(-0.5, -0.5, 0.5);
    final apex = mesh.vertex(0, 0.5, 0);
    mesh.face([a, d, c, b]);
    mesh.face([a, b, apex]);
    mesh.face([b, c, apex]);
    mesh.face([c, d, apex]);
    mesh.face([d, a, apex]);
  }

  static void _triangularPrism(_ObjBuilder mesh) {
    final a = mesh.vertex(-0.5, -0.5, -0.35);
    final b = mesh.vertex(0.5, -0.5, -0.35);
    final c = mesh.vertex(0, -0.5, 0.5);
    final d = mesh.vertex(-0.5, 0.5, -0.35);
    final e = mesh.vertex(0.5, 0.5, -0.35);
    final f = mesh.vertex(0, 0.5, 0.5);
    mesh.face([a, c, b]);
    mesh.face([d, e, f]);
    mesh.face([a, b, e, d]);
    mesh.face([b, c, f, e]);
    mesh.face([c, a, d, f]);
  }
}

class _ObjBuilder {
  _ObjBuilder(this.name);

  final String name;
  final List<String> _vertices = [];
  final List<String> _faces = [];

  int vertex(double x, double y, double z) {
    _vertices.add('${_number(x)} ${_number(y)} ${_number(z)}');
    return _vertices.length;
  }

  void face(List<int> indices) {
    if (indices.length >= 3) _faces.add('f ${indices.join(' ')}');
  }

  String build() {
    if (_vertices.length < 3 || _faces.isEmpty) {
      throw StateError('Primitive "$name" did not produce a valid mesh.');
    }
    return '# DepthVibe procedural primitive: $name\n'
        '${_vertices.map((value) => 'v $value').join('\n')}\n'
        '${_faces.join('\n')}\n';
  }

  String _number(double value) {
    final safe = value.abs() < 1e-10 ? 0.0 : value;
    return safe.toStringAsFixed(6);
  }
}
