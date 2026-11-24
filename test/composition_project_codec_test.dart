import 'package:depthvibe/features/composition/domain/composition_models.dart';
import 'package:depthvibe/features/composition/engine/composition_project_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips opaque Adobe native effect schemas, values and keyframe data', () {
    final document = CompositionDocument(
      layers: [
        CompositionLayer(
          id: 'native-layer',
          name: 'Native layer',
          kind: LayerKind.video,
          effects: const [
            EffectInstance(
              id: 'effect-1',
              effectId: 'native_effect',
              name: 'Third-party glow',
              nativeDescriptor: {
                'hostApp': 'aftereffects-beta',
                'matchName': 'Vendor.Glow',
                'displayName': 'Glow Plus',
                'category': 'Stylize',
                'parameters': [
                  {
                    'matchName': 'Vendor.Glow-0001',
                    'name': 'Radius',
                    'displayName': 'Radius',
                    'value': 24.5,
                    'minValue': 0,
                    'maxValue': 100,
                    'unitsText': 'px',
                    'keyframes': [
                      {'timeMs': 0, 'value': 10.0},
                      {'timeMs': 1000, 'value': 24.5},
                    ],
                  },
                ],
              },
            ),
          ],
        ),
      ],
    );
    final decoded = CompositionProjectCodec.decodeDocument(
      CompositionProjectCodec.encodeDocument(document),
    );
    final descriptor = decoded.layers.single.effects.single.nativeDescriptor;
    expect(descriptor['matchName'], 'Vendor.Glow');
    expect((descriptor['parameters'] as List).single['maxValue'], 100);
    expect(
      ((descriptor['parameters'] as List).single['keyframes'] as List).length,
      2,
    );
  });

  test('round-trips layers, masks, effects, keyframes, audio, transitions and HDR', () {
    const document = CompositionDocument(
      name: 'Feature Film',
      width: 3840,
      height: 2160,
      frameRate: 23.976,
      durationMs: 90000,
      colorOutputProfile: ColorOutputProfile.hdr10Pq,
      playheadMs: 12500,
      selectedLayerId: 'video_1',
      layers: [
        CompositionLayer(
          id: 'video_1',
          name: 'Hero footage',
          kind: LayerKind.video,
          startMs: 250,
          durationMs: 60000,
          sourceInMs: 1000,
          locked: true,
          parentId: 'null_2',
          sourceUri: '/media/hero.mp4',
          sourceDocumentUri: '/media/source.psd',
          sourceWidth: 3840,
          sourceHeight: 2160,
          modelAnimationIndex: 2,
          transform: LayerTransform(
            position: Vector3(1200, 900, 3),
            scale: Vector3(120, 110, 100),
            rotation: Vector3(0, 0, 12),
            opacity: 78,
          ),
          blendMode: LayerBlendMode.softLight,
          masks: [
            MaskModel(
              id: 'mask_3',
              name: 'Subject matte',
              shape: MaskShape.bezier,
              operation: MaskOperation.subtract,
              inverted: true,
              feather: 12,
              vertices: [
                MaskVertex(
                  anchor: Vector2(0.2, 0.3),
                  inHandle: Vector2(-0.05, 0),
                  outHandle: Vector2(0.06, 0.03),
                  smooth: true,
                ),
                MaskVertex(anchor: Vector2(0.8, 0.7)),
                MaskVertex(anchor: Vector2(0.3, 0.8)),
              ],
              keyframeTracks: [
                KeyframeTrack(
                  property: 'feather',
                  keyframes: [
                    ScalarKeyframe(timeMs: 0, value: 4),
                    ScalarKeyframe(timeMs: 1000, value: 18),
                  ],
                ),
              ],
            ),
          ],
          effects: [
            EffectInstance(
              id: 'grade_4',
              effectId: 'color_grade',
              name: 'Primary Grade',
              enabled: false,
              parameters: {'lift_r': 0.2, 'contrast': 1.4, 'saturation': 1.1},
              keyframeTracks: [
                KeyframeTrack(
                  property: 'contrast',
                  keyframes: [
                    ScalarKeyframe(timeMs: 0, value: 1),
                    ScalarKeyframe(
                      timeMs: 3000,
                      value: 1.8,
                      interpolation: Interpolation.easeInOut,
                    ),
                  ],
                ),
              ],
            ),
            EffectInstance(
              id: 'lut_5',
              effectId: 'color_lut',
              name: 'Film LUT',
              assetUri: '/media/warm.cube',
              assetInterpolation: 'tetrahedral',
            ),
          ],
          keyframeTracks: [
            KeyframeTrack(
              property: 'position.x',
              keyframes: [
                ScalarKeyframe(timeMs: 0, value: 100),
                ScalarKeyframe(timeMs: 5000, value: 400),
              ],
            ),
          ],
          audioSettings: AudioSettings(
            gainDb: -4,
            pan: 0.25,
            muted: true,
            fadeInMs: 300,
            fadeOutMs: 900,
            duckingRole: AudioDuckingRole.trigger,
            lowEqDb: 1.5,
            busId: 'dialogue',
          ),
        ),
        CompositionLayer(
          id: 'null_2',
          name: 'Camera Parent',
          kind: LayerKind.nullObject,
          shapeStyle: ShapeStyle(
            primitive: ShapePrimitive.star,
            fillColor: '#112233',
            strokeColor: '#FFCC00',
            strokeWidth: 2,
            cornerRadius: 4,
            points: 7,
          ),
          camera: CameraSettings(
            projection: 'orthographic',
            cameraMode: 'twoNode',
            pointOfInterestX: 1820,
            pointOfInterestY: 940,
            pointOfInterestZ: 640,
            fieldOfView: 45,
            focalLength: 35,
            focusDistance: 200,
            nearClip: 5,
            farClip: 9000,
            aperture: 1.8,
            sensorWidthMm: 24,
            depthOfField: true,
          ),
          light: LightSettings(
            kind: LightKind.area,
            color: '#ABCDEF',
            intensity: 220,
            coneAngle: 60,
            castShadows: false,
            shadowSoftness: 33,
            areaSize: 320,
            areaSamples: 32,
          ),
        ),
      ],
      transitions: [
        CompositionTransition(
          id: 'transition_6',
          fromLayerId: 'video_1',
          toLayerId: 'null_2',
          kind: TransitionKind.zoomIn,
          durationMs: 750,
          startMs: 1800,
        ),
      ],
      audioBuses: [
        AudioBus(
          id: 'master',
          name: 'Master',
          isMaster: true,
          gainDb: -1,
          limiterEnabled: true,
          limiterCeilingDb: -0.5,
        ),
        AudioBus(
          id: 'dialogue',
          name: 'Dialogue',
          compressorEnabled: true,
          compressorThresholdDb: -22,
          compressorRatio: 4,
          keyframeTracks: [
            KeyframeTrack(
              property: 'gainDb',
              keyframes: [ScalarKeyframe(timeMs: 0, value: 0)],
            ),
          ],
        ),
      ],
    );

    final json = CompositionProjectCodec.encodeDocument(
      document,
      rewriteAssetUri: (uri) =>
          uri == '/media/hero.mp4' ? 'assets/hero.mp4' : uri,
    );
    expect((json['layers'] as List).first['sourceUri'], 'assets/hero.mp4');

    final restored = CompositionProjectCodec.decodeDocument(
      json,
      resolveAssetUri: (uri) =>
          uri == 'assets/hero.mp4' ? '/project/assets/hero.mp4' : uri,
    );
    expect(restored.name, document.name);
    expect(restored.width, 3840);
    expect(restored.height, 2160);
    expect(restored.frameRate, 23.976);
    expect(restored.durationMs, 90000);
    expect(restored.playheadMs, 12500);
    expect(restored.colorOutputProfile, ColorOutputProfile.hdr10Pq);
    expect(restored.selectedLayerId, 'video_1');
    expect(restored.layers, hasLength(2));

    final video = restored.layers.first;
    expect(video.sourceUri, '/project/assets/hero.mp4');
    expect(video.sourceDocumentUri, '/media/source.psd');
    expect(video.blendMode, LayerBlendMode.softLight);
    expect(video.parentId, 'null_2');
    expect(video.transform.position.x, 1200);
    expect(video.transform.position.y, 900);
    expect(video.transform.position.z, 3);
    expect(video.masks.single.shape, MaskShape.bezier);
    expect(video.masks.single.vertices.first.smooth, isTrue);
    expect(video.masks.single.vertices.first.outHandle.x, 0.06);
    expect(video.masks.single.vertices.first.outHandle.y, 0.03);
    expect(video.masks.single.keyframeTracks.single.keyframes, hasLength(2));
    expect(video.effects.first.enabled, isFalse);
    expect(video.effects.first.parameters['contrast'], 1.4);
    expect(video.effects.first.keyframeTracks.single.keyframes.last.value, 1.8);
    expect(video.effects.last.assetUri, '/media/warm.cube');
    expect(video.effects.last.assetInterpolation, 'tetrahedral');
    expect(video.keyframeTracks.single.property, 'position.x');
    expect(video.audioSettings.gainDb, -4);
    expect(video.audioSettings.busId, 'dialogue');
    expect(restored.transitions.single.kind, TransitionKind.zoomIn);
    expect(restored.transitions.single.durationMs, 750);
    expect(restored.audioBuses, hasLength(2));
    expect(restored.audioBuses.last.compressorEnabled, isTrue);
    expect(restored.audioBuses.last.keyframeTracks.single.property, 'gainDb');
    expect(restored.layers.last.shapeStyle!.primitive, ShapePrimitive.star);
    expect(restored.layers.last.camera!.depthOfField, isTrue);
    expect(restored.layers.last.camera!.cameraMode, 'twoNode');
    expect(restored.layers.last.camera!.pointOfInterestX, 1820);
    expect(restored.layers.last.camera!.pointOfInterestY, 940);
    expect(restored.layers.last.camera!.pointOfInterestZ, 640);
    expect(restored.layers.last.light!.areaSamples, 32);
  });

  test('rejects duplicate layer ids and invalid parameter numbers', () {
    const duplicate = CompositionDocument(
      layers: [
        CompositionLayer(id: 'same', name: 'A', kind: LayerKind.video),
        CompositionLayer(id: 'same', name: 'B', kind: LayerKind.image),
      ],
    );
    expect(
      () => CompositionProjectCodec.decodeDocument(
        CompositionProjectCodec.encodeDocument(duplicate),
      ),
      throwsA(isA<FormatException>()),
    );

    final json = CompositionProjectCodec.encodeDocument(
      const CompositionDocument(
        layers: [
          CompositionLayer(
            id: 'layer',
            name: 'Layer',
            kind: LayerKind.video,
            effects: [
              EffectInstance(
                id: 'effect',
                effectId: 'color_grade',
                name: 'Grade',
                parameters: {'contrast': 1},
              ),
            ],
          ),
        ],
      ),
    );
    final layer = (json['layers'] as List).single as Map<String, Object?>;
    final effect = (layer['effects'] as List).single as Map<String, Object?>;
    effect['parameters'] = {'contrast': double.infinity};
    expect(
      () => CompositionProjectCodec.decodeDocument(json),
      throwsA(isA<FormatException>()),
    );
  });

  test('round-trips editable Bezier vector shape paths and tangent handles', () {
    const document = CompositionDocument(
      layers: [
        CompositionLayer(
          id: 'shape-path',
          name: 'Custom Vector',
          kind: LayerKind.shape,
          shapeStyle: ShapeStyle(
            primitive: ShapePrimitive.path,
            fillColor: '#FF336699',
            strokeColor: '#FFFFFFFF',
            strokeWidth: 4,
            pathClosed: true,
            pathVertices: [
              MaskVertex(
                anchor: Vector2(0.1, 0.2),
                inHandle: Vector2(-0.1, 0),
                outHandle: Vector2(0.2, 0.1),
                smooth: true,
              ),
              MaskVertex(anchor: Vector2(0.8, 0.2)),
              MaskVertex(anchor: Vector2(0.5, 0.9)),
            ],
          ),
        ),
      ],
    );
    final restored = CompositionProjectCodec.decodeDocument(
      CompositionProjectCodec.encodeDocument(document),
    );
    final style = restored.layers.single.shapeStyle!;
    expect(style.primitive, ShapePrimitive.path);
    expect(style.pathClosed, isTrue);
    expect(style.pathVertices, hasLength(3));
    expect(style.pathVertices.first.smooth, isTrue);
    expect(style.pathVertices.first.outHandle.x, 0.2);
    expect(style.pathVertices.first.outHandle.y, 0.1);
    expect(style.pathVertices.first.inHandle.x, -0.1);

    const openDocument = CompositionDocument(
      layers: [
        CompositionLayer(
          id: 'open-path',
          name: 'Open Stroke',
          kind: LayerKind.shape,
          shapeStyle: ShapeStyle(
            primitive: ShapePrimitive.path,
            pathClosed: false,
            pathVertices: [
              MaskVertex(anchor: Vector2(0.1, 0.5)),
              MaskVertex(anchor: Vector2(0.9, 0.5)),
            ],
          ),
        ),
      ],
    );
    final openRestored = CompositionProjectCodec.decodeDocument(
      CompositionProjectCodec.encodeDocument(openDocument),
    );
    expect(openRestored.layers.single.shapeStyle!.pathClosed, isFalse);
  });

}
