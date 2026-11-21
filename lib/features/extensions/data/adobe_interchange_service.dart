import 'dart:convert';
import '../../composition/data/effect_catalog.dart';
import '../../composition/data/transition_catalog.dart';
import '../../composition/domain/composition_models.dart';
import '../../composition/engine/composition_project_codec.dart';

class AdobeImportReport {
  const AdobeImportReport({required this.document,required this.mappedEffects,required this.unsupportedEffects,required this.warnings});
  final CompositionDocument document;
  final List<String> mappedEffects,unsupportedEffects,warnings;
  Map<String,Object?> toJson()=>{'ok':true,'composition':{'name':document.name,'width':document.width,'height':document.height,'frameRate':document.frameRate,'durationMs':document.durationMs,'layerCount':document.layers.length},'mappedEffects':mappedEffects,'unsupportedEffects':unsupportedEffects,'warnings':warnings};
}

class AdobeInterchangeService {
  AdobeInterchangeService._();
  static const int _ticksPerSecond=254016000000;
  static const Map<String,String> afterEffectsMatchNames={
    'brightness':'ADBE Brightness & Contrast 2','contrast':'ADBE Brightness & Contrast 2',
    'gaussian_blur':'ADBE Gaussian Blur 2','sharpen':'ADBE Sharpen','invert':'ADBE Invert','saturation':'ADBE Hue/Saturation',
  };
  static Map<String,Object?> _map(Object? v)=>v is Map?{for(final e in v.entries)if(e.key is String)e.key as String:e.value}:{};
  static List<Map<String,Object?>> _maps(Object? v)=>v is List?v.whereType<Map>().map(_map).toList():const[];
  static String _s(Object? v,[String d=''])=>v is String&&v.trim().isNotEmpty?v.trim():d;
  static double? _n(Object? v)=>v is num&&v.isFinite?v.toDouble():null;
  static double _d(Object? v,[double d=0])=>_n(v)??d;
  static int _i(Object? v,[int d=0])=>v is num&&v.isFinite?v.round():d;
  static bool _b(Object? v,[bool d=false])=>v is bool?v:d;
  static int _ms(Object? v,[int fallback=0])=>(_d(v,fallback/1000)*1000).round();
  static int _dim(Object? v,int d)=>_i(v,d).clamp(1,16384).toInt();
  static String? _path(Object? v){
    final p=_s(v);
    if(p.startsWith('file://')||RegExp(r'^[A-Za-z]:[\\/]').hasMatch(p)||p.startsWith(r'\\')||p.startsWith('/'))return p;
    return null;
  }
  static String _id(String prefix,Object? src,int index,Set<String> used){
    final raw=_s(src,index.toString()).replaceAll(RegExp(r'[^A-Za-z0-9_-]'),'_');
    final base=prefix+'_'+raw;var candidate=base;var suffix=2;
    while(!used.add(candidate)){candidate=base+'_'+suffix.toString();suffix++;}
    return candidate;
  }
  static AdobeImportReport importSnapshot(Map<String,Object?> snap){
    if(snap['schemaVersion']!=1)throw const FormatException('Unsupported Adobe snapshot schema.');
    final host=_s(snap['hostApp']),p=_map(snap['payload']);
    if(host=='premierepro')return _premiere(p);
    if(host=='aftereffects'||host=='aftereffects-beta')return _afterEffects(snap,p);
    throw FormatException('Unsupported Adobe host: '+host);
  }

  static TransitionKind _premiereTransitionKind(String name) {
    final value = name.toLowerCase();
    if (value.contains('dip to black') || value.contains('dip to white') ||
        value.contains('fade through')) return TransitionKind.fadeThroughColor;
    if (value.contains('wipe')) {
      if (value.contains('left')) return TransitionKind.wipeLeft;
      if (value.contains('right')) return TransitionKind.wipeRight;
      if (value.contains('up')) return TransitionKind.wipeUp;
      if (value.contains('down')) return TransitionKind.wipeDown;
    }
    if (value.contains('slide')) {
      if (value.contains('left')) return TransitionKind.slideLeft;
      if (value.contains('right')) return TransitionKind.slideRight;
      if (value.contains('up')) return TransitionKind.slideUp;
      if (value.contains('down')) return TransitionKind.slideDown;
    }
    if (value.contains('radial') || value.contains('iris')) return TransitionKind.radial;
    return TransitionKind.dissolve;
  }

  static AdobeImportReport _premiere(Map<String,Object?> payload){
    final seq=_map(payload['sequence']),warnings=<String>[],mapped=<String>[],unsupported=<String>[];
    final used=<String>{},layers=<CompositionLayer>[];
    double? fps=_n(seq['frameRate']);
    if(fps==null||fps<1||fps>240){
      final ticks=double.tryParse(_s(seq['timebase']));
      if(ticks!=null&&ticks>0)fps=_ticksPerSecond/ticks;
    }
    if(fps==null||fps<1||fps>240){fps=30;warnings.add('Premiere frame rate unavailable; used 30 fps.');}
    final tracks=<({Map<String,Object?> t,bool audio})>[
      for(final t in _maps(payload['videoTracks']))(t:t,audio:false),
      for(final t in _maps(payload['audioTracks']))(t:t,audio:true),
    ];
    var maxEnd=0;
    for(var ti=0;ti<tracks.length;ti++){
      final entry=tracks[ti],track=entry.t,trackIndex=_i(track['index'],ti),clips=_maps(track['clips']);
      for(var ci=0;ci<clips.length;ci++){
        final clip=clips[ci],start=_ms(clip['startSeconds']),end=_n(clip['endSeconds']);
        final duration=_ms(clip['durationSeconds'],end==null?1000:(end*1000).round()-start).clamp(1,86400000).toInt();
        final audio=entry.audio||_s(clip['mediaType']).toLowerCase()=='audio',path=_path(clip['sourcePath']);
        final sourceId=_s(clip['id'],_s(clip['sourceId'],'$trackIndex-$ci'));
        final name=_s(clip['name'],_s(clip['sourceName'],'Adobe Clip '+(ci+1).toString()));
        final mappedResult=_mapEffects(_maps(clip['effects']),host:'premierepro',layerIndex:layers.length);
        mapped.addAll(mappedResult.mapped);unsupported.addAll(mappedResult.unsupported);
        final muted=_b(track['muted']);
        layers.add(CompositionLayer(
          id:_id('premiere',_s(track['id'],trackIndex.toString())+'_'+sourceId,layers.length,used),
          name:name,kind:audio?LayerKind.audio:LayerKind.video,startMs:start,durationMs:duration,
          sourceInMs:_ms(clip['sourceInSeconds']),enabled:_b(clip['enabled'],!muted),
          solo:_b(clip['solo']),locked:_b(clip['locked']),sourceUri:path,
          sourceWidth:_i(clip['sourceWidth']),sourceHeight:_i(clip['sourceHeight']),
          effects:mappedResult.effects,audioSettings:AudioSettings(muted:audio&&muted),
          externalSourceId:sourceId,externalSourceName:_s(clip['sourceName'],name),
          externalHostApp:'premierepro',externalLayerIndex:trackIndex,
          interchangeMetadata:{'hostApp':'premierepro','trackIndex':trackIndex,'trackName':_s(track['name'],'Track '+trackIndex.toString()),
            'clipIndex':ci,'speed':_d(clip['speed'],1),'sourceName':_s(clip['sourceName'],name),'sourcePath':path,
            'unsupportedEffects':mappedResult.rawUnsupported},
        ));
        if(start+duration>maxEnd)maxEnd=start+duration;
        if(path==null&&!audio)warnings.add('Missing media: '+name+' (use Relink).');
      }
    }
    final importedTransitions = <CompositionTransition>[];
    for (final entry in tracks.where((item) => !item.audio)) {
      final trackIndex = _i(entry.t['index']);
      final trackLayers = layers.where((layer) =>
        layer.kind != LayerKind.audio &&
        _i(layer.interchangeMetadata['trackIndex'], -1) == trackIndex).toList()
        ..sort((a,b) => a.startMs.compareTo(b.startMs));
      final sourceTransitions = _maps(entry.t['transitions']);
      for (var ti = 0; ti < sourceTransitions.length; ti++) {
        final raw = sourceTransitions[ti];
        if (trackLayers.length < 2) {
          warnings.add('Premiere transition could not be attached: ' + _s(raw['name'], 'Transition'));
          continue;
        }
        final startMs = _ms(raw['startSeconds']);
        final durationMs = _ms(raw['durationSeconds'], 500).clamp(1, 60000).toInt();
        var pairIndex = 0, bestDistance = 1 << 62;
        for (var pair = 0; pair < trackLayers.length - 1; pair++) {
          final distance = (trackLayers[pair + 1].startMs - startMs).abs();
          if (distance < bestDistance) {
            bestDistance = distance;
            pairIndex = pair;
          }
        }
        final name = _s(raw['name'], 'Premiere Transition');
        final matchName = _s(raw['matchName'], name);
        importedTransitions.add(CompositionTransition(
          id: _id('premiere_transition', _s(raw['id'], '$trackIndex-$ti'), ti, used),
          fromLayerId: trackLayers[pairIndex].id,
          toLayerId: trackLayers[pairIndex + 1].id,
          kind: _premiereTransitionKind(name + ' ' + matchName),
          startMs: startMs,
          durationMs: durationMs,
          externalMatchName: matchName,
          metadata: {
            'hostApp': 'premierepro',
            'trackIndex': trackIndex,
            'sourceName': name,
            'sourceTransition': raw,
          },
        ));
      }
    }
    final seqDuration=_ms(seq['durationSeconds']),project=_map(payload['project']);
    if(layers.isEmpty)warnings.add('No clips found in active Premiere sequence.');
    return AdobeImportReport(document:CompositionDocument(
      name:_s(seq['name'],_s(project['name'],'Premiere Sequence')),width:_dim(seq['width'],1920),
      height:_dim(seq['height'],1080),frameRate:fps,durationMs:(seqDuration>0?seqDuration:maxEnd).clamp(1,86400000).toInt(),
      layers:layers,transitions:importedTransitions),
      mappedEffects:mapped,unsupportedEffects:unsupported,warnings:warnings);
  }

  static AdobeImportReport _afterEffects(Map<String,Object?> snap,Map<String,Object?> payload){
    final comp=_map(payload['composition']),rawLayers=_maps(payload['layers']);
    final warnings=<String>[],mapped=<String>[],unsupported=<String>[],used=<String>{};
    final sourceIds=<String,String>{},parents=<({String id,String parent})>[],layers=<CompositionLayer>[];
    final fps=_d(comp['frameRate'],30).clamp(1,240).toDouble();
    for(var index=0;index<rawLayers.length;index++){
      final raw=rawLayers[index],extId=_s(raw['id'],_i(raw['index'],index+1).toString());
      final id=_id('aftereffects',extId,index,used);sourceIds[extId]=id;
      final name=_s(raw['name'],'AE Layer '+(index+1).toString()),match=_s(raw['matchName']);
      final audioOnly=_b(raw['hasAudio'])&&!_b(raw['hasVideo'],true);
      final kind=_aeKind(raw,audioOnly),inPoint=_d(raw['inPointSeconds'],_d(raw['startTimeSeconds']));
      final startTime=_d(raw['startTimeSeconds'],inPoint),outPoint=_d(raw['outPointSeconds'],inPoint+1);
      final duration=((outPoint-inPoint).abs()<0.0001?1:((outPoint-inPoint)*1000).round()).clamp(1,86400000).toInt();
      final source=_map(raw['source']),path=_path(raw['sourcePath']??source['path']);
      final mappedResult=_mapEffects(_maps(raw['effects']),host:'aftereffects',layerIndex:index);
      mapped.addAll(mappedResult.mapped);unsupported.addAll(mappedResult.unsupported);
      final parent=_s(raw['parentLayerId']);if(parent.isNotEmpty)parents.add((id:id,parent:parent));
      final text=_s(raw['textContent']);
      layers.add(CompositionLayer(
        id:id,name:name,kind:kind,startMs:(inPoint*1000).round(),durationMs:duration,
        sourceInMs:((inPoint-startTime)*1000).round().clamp(0,86400000).toInt(),
        enabled:_b(raw['enabled'],true),solo:_b(raw['solo']),locked:_b(raw['locked']),sourceUri:path,
        sourceWidth:_i(raw['sourceWidth']??source['width']),sourceHeight:_i(raw['sourceHeight']??source['height']),
        textContent:text.isEmpty?null:text,transform:_readTransform(_map(raw['transform'])),
        keyframeTracks:_readKeyframeTracks(raw['keyframeTracks']),
        effects:mappedResult.effects,camera:kind==LayerKind.camera?const CameraSettings():null,
        light:kind==LayerKind.light?const LightSettings():null,
        externalSourceId:extId,externalSourceName:_s(source['name'],name),externalHostApp:_s(snap['hostApp']),
        externalLayerIndex:_i(raw['index'],index+1),
        interchangeMetadata:{'hostApp':_s(snap['hostApp']),'matchName':match,'layerIndex':_i(raw['index'],index+1),
          'startTimeSeconds':startTime,'inPointSeconds':inPoint,'outPointSeconds':outPoint,
          'threeDLayer':_b(raw['threeDLayer']),'adjustmentLayer':_b(raw['adjustmentLayer']),
          'nullLayer':_b(raw['nullLayer']),'sourcePath':path,'unsupportedEffects':mappedResult.rawUnsupported,
          'expressions':_maps(raw['expressions'])},
      ));
      if(path==null&&[LayerKind.video,LayerKind.audio,LayerKind.image].contains(kind))warnings.add('Missing footage: '+name+' (use Relink).');
    }
    final linked=layers.map((layer){
      final r=parents.where((p)=>p.id==layer.id);if(r.isEmpty)return layer;
      final parentId=sourceIds[r.first.parent];return parentId==null?layer:layer.copyWith(parentId:parentId);
    }).toList();
    final maxEnd=linked.fold<int>(0,(m,l)=>l.endMs>m?l.endMs:m),compDuration=_ms(comp['durationSeconds'],maxEnd);
    if(linked.isEmpty)warnings.add('No layers found in active After Effects composition.');
    return AdobeImportReport(document:CompositionDocument(name:_s(comp['name'],'After Effects Composition'),
      width:_dim(comp['width'],1920),height:_dim(comp['height'],1080),frameRate:fps,
      durationMs:(compDuration>0?compDuration:maxEnd).clamp(1,86400000).toInt(),layers:linked),
      mappedEffects:mapped,unsupportedEffects:unsupported,warnings:warnings);
  }

  static Interpolation _interpolation(Object? raw) {
    switch (_s(raw).toLowerCase()) {
      case 'hold': return Interpolation.hold;
      case 'cubicbezier':
      case 'bezier': return Interpolation.cubicBezier;
      case 'easein': return Interpolation.easeIn;
      case 'easeout': return Interpolation.easeOut;
      case 'easeinout': return Interpolation.easeInOut;
      case 'linear':
      default: return Interpolation.linear;
    }
  }
  static List<ScalarKeyframe> _scalarKeyframes(Object? raw, {double Function(double)? mapValue}) {
    final result = <ScalarKeyframe>[];
    for (final item in _maps(raw).take(10000)) {
      final value = _n(item['value']);
      if (value == null) continue;
      final ms = item['timeMs'] is num ? _i(item['timeMs']) : _ms(item['timeSeconds']);
      final mapped = mapValue == null ? value : mapValue(value);
      if (!mapped.isFinite) continue;
      final metadata = <String, Object>{};
      const metadataKeys = {
        'inInterpolation', 'outInterpolation',
        'inTemporalEase', 'outTemporalEase',
        'inSpatialTangent', 'outSpatialTangent',
        'roving', 'spatialAutoBezier', 'spatialContinuous',
        'temporalAutoBezier', 'temporalContinuous',
      };
      for (final entry in item.entries) {
        if (metadataKeys.contains(entry.key) && entry.value != null) {
          metadata[entry.key] = entry.value as Object;
        }
      }
      result.add(ScalarKeyframe(
        timeMs: ms,
        value: mapped,
        interpolation: _interpolation(item['interpolation']),
        metadata: metadata,
      ));
    }
    result.sort((a,b) => a.timeMs.compareTo(b.timeMs));
    return result;
  }
  static List<KeyframeTrack> _readKeyframeTracks(Object? raw) {
    final result = <KeyframeTrack>[];
    for (final item in _maps(raw).take(256)) {
      final property = _s(item['property']);
      if (property.isEmpty) continue;
      final frames = _scalarKeyframes(item['keyframes']);
      if (frames.isNotEmpty) result.add(KeyframeTrack(property: property, keyframes: frames));
    }
    return result;
  }
  static List<KeyframeTrack> _effectKeyframeTracks(
    List<Map<String,Object?>> properties, List<String> tokens, String targetProperty, {
    double Function(double)? mapValue,
  }) {
    for (final property in properties) {
      final label = (_s(property['matchName']) + ' ' + _s(property['name'])).toLowerCase();
      if (!tokens.any(label.contains)) continue;
      final frames = _scalarKeyframes(property['keyframes'], mapValue: mapValue);
      if (frames.isNotEmpty) return [KeyframeTrack(property: targetProperty, keyframes: frames)];
    }
    return const [];
  }

  static LayerKind _aeKind(Map<String,Object?> raw,bool audioOnly){
    final n=_s(raw['matchName']).toLowerCase();
    if(_b(raw['nullLayer'])||n.contains('null'))return LayerKind.nullObject;
    if(_b(raw['adjustmentLayer']))return LayerKind.adjustment;
    if(n.contains('camera'))return LayerKind.camera;if(n.contains('light'))return LayerKind.light;
    if(audioOnly)return LayerKind.audio;if(n.contains('text'))return LayerKind.text;
    if(n.contains('shape'))return LayerKind.shape;
    if(raw['sourcePath']!=null||raw['source']!=null)return LayerKind.video;
    return LayerKind.nullObject;
  }
  static LayerTransform _readTransform(Map<String,Object?> raw){
    List<num> vec(Object? v,List<num> d){if(v is! List)return d;final a=v.whereType<num>().take(3).toList();return a.isEmpty?d:a;}
    final p=vec(raw['position'],const [960,540,0]),a=vec(raw['anchorPoint'],const [0,0,0]),s=vec(raw['scale'],const [100,100,100]);
    return LayerTransform(position:Vector3(p[0].toDouble(),p.length>1?p[1].toDouble():540,p.length>2?p[2].toDouble():0),
      anchor:Vector3(a[0].toDouble(),a.length>1?a[1].toDouble():0,a.length>2?a[2].toDouble():0),
      scale:Vector3(s[0].toDouble(),s.length>1?s[1].toDouble():100,s.length>2?s[2].toDouble():100),
      rotation:Vector3(0,0,_d(raw['rotation'])),opacity:_d(raw['opacity'],100).clamp(0,100).toDouble());
  }

  static ({List<EffectInstance> effects,List<String> mapped,List<String> unsupported,List<Map<String,Object?>> rawUnsupported}) _mapEffects(
    List<Map<String,Object?>> input,{required String host,required int layerIndex}){
    final effects=<EffectInstance>[],mapped=<String>[],unsupported=<String>[],rawUnsupported=<Map<String,Object?>>[];var id=0;
    for(final raw in input){
      final match=_s(raw['matchName'],_s(raw['name'],'Unknown Effect')),
        lower=match.toLowerCase(),
        props=_maps(raw['properties']).isNotEmpty
          ? _maps(raw['properties'])
          : _maps(raw['parameters']);
      final nativeParameters = _maps(
        raw['parameters'] is List ? raw['parameters'] : raw['properties'],
      );
      Map<String,Object?> nativeDescriptor() => {
        'hostApp': host,
        'matchName': match,
        'displayName': _s(raw['displayName'],_s(raw['name'],match)),
        'category': _s(raw['category']),
        'version': _s(raw['version']),
        'mediaType': _s(raw['mediaType'], 'video'),
        'isMotionGraphicsTemplate': _b(raw['isMotionGraphicsTemplate']) || match == 'AE.ADBE Capsule',
        'parameterSchemaVersion': _i(raw['parameterSchemaVersion'], 2),
        'parameters': nativeParameters,
        if (raw['parameterTree'] is List)
          'parameterTree': raw['parameterTree'],
      };
      double param(List<String> keys,double fallback){
        for(final p in props){final n=(_s(p['matchName'])+' '+_s(p['name'])+' '+_s(p['displayName'])).toLowerCase();
          if(keys.any(n.contains)){final v=_n(p['value']);if(v!=null)return v;}}return fallback;
      }
      final additions=<EffectInstance>[];
      if(lower.contains('gaussian blur')||lower.contains('fast blur')){
        additions.add(EffectInstance(id:'adobe_'+layerIndex.toString()+'_'+id.toString(),effectId:'gaussian_blur',name:'Gaussian Blur',
          parameters:{'sigma':param(['blurriness','blur amount','radius'],2).clamp(0,30).toDouble()},
          keyframeTracks:_effectKeyframeTracks(props,['blurriness','blur amount','radius'],'sigma',mapValue:(v)=>v.clamp(0,30).toDouble()),enabled:_b(raw['enabled'],true)));id++;
      }else if(lower.contains('brightness')&&lower.contains('contrast')){
        additions.add(EffectInstance(id:'adobe_'+layerIndex.toString()+'_'+id.toString(),effectId:'brightness',name:'Brightness',
          parameters:{'value':(param(['brightness'],0)/100).clamp(-1,1).toDouble()},
          keyframeTracks:_effectKeyframeTracks(props,['brightness'],'value',mapValue:(v)=>(v/100).clamp(-1,1).toDouble()),enabled:_b(raw['enabled'],true)));id++;
        additions.add(EffectInstance(id:'adobe_'+layerIndex.toString()+'_'+id.toString(),effectId:'contrast',name:'Contrast',
          parameters:{'value':(1+param(['contrast'],0)/100).clamp(0,3).toDouble()},
          keyframeTracks:_effectKeyframeTracks(props,['contrast'],'value',mapValue:(v)=>(1+v/100).clamp(0,3).toDouble()),enabled:_b(raw['enabled'],true)));id++;
      }else if(lower.contains('sharpen')){
        additions.add(EffectInstance(id:'adobe_'+layerIndex.toString()+'_'+id.toString(),effectId:'sharpen',name:'Sharpen',
          parameters:{'amount':param(['amount','sharpness'],1).clamp(0,5).toDouble()},
          keyframeTracks:_effectKeyframeTracks(props,['amount','sharpness'],'amount',mapValue:(v)=>v.clamp(0,5).toDouble()),enabled:_b(raw['enabled'],true)));id++;
      }else if(lower.contains('invert')){
        additions.add(EffectInstance(id:'adobe_'+layerIndex.toString()+'_'+id.toString(),effectId:'invert',name:'Invert',enabled:_b(raw['enabled'],true)));id++;
      }else if(lower.contains('hue/saturation')||lower.contains('hue saturation')){
        additions.add(EffectInstance(id:'adobe_'+layerIndex.toString()+'_'+id.toString(),effectId:'saturation',name:'Saturation',
          parameters:{'value':(1+param(['master saturation','saturation'],0)/100).clamp(0,3).toDouble()},
          keyframeTracks:_effectKeyframeTracks(props,['master saturation','saturation'],'value',mapValue:(v)=>(1+v/100).clamp(0,3).toDouble()),enabled:_b(raw['enabled'],true)));id++;
      }
      if(additions.isEmpty) {
        final nativeName = _s(raw['displayName'], _s(raw['name'], match));
        additions.add(EffectInstance(
          id: 'adobe_' + layerIndex.toString() + '_' + id.toString(),
          effectId: 'native_effect',
          name: nativeName,
          enabled: _b(raw['enabled'], true),
          nativeDescriptor: nativeDescriptor(),
        ));
        id++;
        // Keep the effect visible/editable in DepthVibe, while clearly marking
        // that its renderer remains the original Adobe host/plugin.
        effects.addAll(additions);
        unsupported.add(host + ': ' + match + ' (native host effect)');
        mapped.add(host + ': ' + match + ' -> native parameter descriptor');
      } else if(additions.any((e)=>EffectCatalog.findBuiltin(e.effectId)==null)) {
        unsupported.add(host+': '+match);
        rawUnsupported.add(raw);
      } else {
        // One native component may map to multiple DepthVibe renderable effects.
        // Keep its full native parameter tree on the first effect instance only.
        if (additions.isNotEmpty) {
          additions[0] = additions[0].copyWith(
            nativeDescriptor: nativeDescriptor(),
          );
        }
        effects.addAll(additions);
        mapped.add(host+': '+match+' -> '+additions.map((e)=>e.effectId).join(', '));
      }
    }
    return(effects:effects,mapped:mapped,unsupported:unsupported,rawUnsupported:rawUnsupported);
  }

  static Map<String,Object?> buildInterchangeBundle(CompositionDocument doc){
    final ae=<Map<String,Object?>>[],unknown=<Map<String,Object?>>[];
    final premiereMapped=<Map<String,Object?>>[],premiereUnsupported=<Map<String,Object?>>[];
    for(final l in doc.layers){for(final e in l.effects){
      final name=afterEffectsMatchNames[e.effectId];
      final entry=<String,Object?>{'layerId':l.id,'effectId':e.effectId,'effectName':e.name,
        'afterEffectsMatchName':name,'parameters':e.parameters};
      if(name==null||EffectCatalog.findBuiltin(e.effectId)==null)unknown.add(entry);else ae.add(entry);
      final filterEntry=<String,Object?>{
        'layerId':l.id,'layerName':l.name,'effectId':e.effectId,'effectName':e.name,
        'enabled':e.enabled,'parameters':e.parameters,
      };
      // Only the documented static Gaussian Blur XMEML mapping is emitted.
      if(e.effectId=='gaussian_blur' && l.kind!=LayerKind.audio &&
          e.keyframeTracks.every((track)=>track.keyframes.isEmpty)){
        premiereMapped.add(filterEntry);
      }else{
        premiereUnsupported.add({...filterEntry,
          'reason':e.effectId=='gaussian_blur'
            ? 'Animated Gaussian Blur curves are not yet emitted in XMEML.'
            : 'No verified portable XMEML effect identifier/parameter schema.'});
      }
    }}
    return{'format':'DepthVibe.AdobeInterchange','schemaVersion':1,'document':CompositionProjectCodec.encodeDocument(doc),
      'effectMapping':{'afterEffects':{'mapped':ae,'unsupported':unknown},
        'premiereFcpXml':{'mapped':premiereMapped,'unsupported':premiereUnsupported,
          'note':'Premiere XML emits the verified static Gaussian Blur mapping. Other effects remain unsupported rather than using guessed plugin IDs.'}},
      'media':{'embedded':false,'note':'Only local media references are exported. Relink missing media on the target machine.'}};
  }

  static List<List<CompositionLayer>> _groupPremiereTracks(List<CompositionLayer> layers) {
    final groups = <String, List<CompositionLayer>>{};
    for (final layer in layers) {
      final meta = layer.interchangeMetadata;
      final host = _s(meta['hostApp'], _s(layer.externalHostApp));
      final index = meta['trackIndex'];
      final key = host == 'premierepro' && index is num
          ? 'premiere:' + index.toInt().toString()
          : 'layer:' + layer.id;
      groups.putIfAbsent(key, () => <CompositionLayer>[]).add(layer);
    }
    for (final track in groups.values) {
      track.sort((a,b) {
        final byTime = a.startMs.compareTo(b.startMs);
        return byTime == 0 ? a.name.compareTo(b.name) : byTime;
      });
    }
    return groups.values.toList();
  }

  static String _premiereFiltersXml(CompositionLayer layer) {
    if (layer.kind == LayerKind.audio || layer.effects.isEmpty) return '';
    String number(double value) => value.toStringAsFixed(4)
        .replaceFirst(RegExp(r'\.?0+$'), '');
    final filters = <String>[];
    for (final effect in layer.effects) {
      if (effect.effectId != 'gaussian_blur' ||
          effect.keyframeTracks.any((track) => track.keyframes.isNotEmpty)) continue;
      final radius = (effect.parameters['sigma'] ?? 2).clamp(0, 100).toDouble();
      filters.add('<filter><enabled>' + (effect.enabled ? 'TRUE' : 'FALSE') +
        '</enabled><start>-1</start><end>-1</end><effect>' +
        '<name>Gaussian Blur</name><effectid>Gaussian Blur</effectid>' +
        '<effectcategory>Blur</effectcategory><effecttype>filter</effecttype>' +
        '<mediatype>video</mediatype>' +
        '<parameter><parameterid>channel</parameterid><name>Channel</name>' +
        '<valuemin>1</valuemin><valuemax>7</valuemax><value>1</value></parameter>' +
        '<parameter><parameterid>radius</parameterid><name>Radius</name>' +
        '<valuemin>0</valuemin><valuemax>100</valuemax><value>' + number(radius) +
        '</value></parameter></effect></filter>');
    }
    return filters.join();
  }

  static String buildPremiereXml(CompositionDocument doc){
    String esc(String value) => value.replaceAll('&','&amp;')
        .replaceAll('<','&lt;').replaceAll('>','&gt;')
        .replaceAll('"','&quot;').replaceAll("'","&apos;");
    final fps=doc.frameRate.clamp(1,240),base=fps.round(),ntsc=(fps-base).abs()>0.001;
    int frame(int ms)=>(ms*fps/1000).round();
    final rate='<rate><timebase>'+base.toString()+'</timebase><ntsc>'+
        (ntsc?'TRUE':'FALSE')+'</ntsc></rate>';
    final video=doc.layers.where((l)=>l.kind!=LayerKind.audio).toList();
    final audio=doc.layers.where((l)=>l.kind==LayerKind.audio).toList();
    final videoTracks=_groupPremiereTracks(video),audioTracks=_groupPremiereTracks(audio);
    var clipOrdinal=0;
    String clip(CompositionLayer layer){
      final index=++clipOrdinal;
      final st=frame(layer.startMs),en=st+frame(layer.durationMs);
      final ins=frame(layer.sourceInMs),outs=ins+frame(layer.durationMs);
      final path=layer.sourceUri;
      final name=layer.externalSourceName ??
          (path==null?layer.name:path.split(RegExp(r'[/\\]')).last);
      final file=path==null
          ? '<file id="file-'+index.toString()+'"><name>'+esc(name)+'</name><offline>true</offline></file>'
          : '<file id="file-'+index.toString()+'"><name>'+esc(name)+'</name><pathurl>'+
              esc(path.startsWith('file://')?path:Uri.file(path).toString())+
              '</pathurl></file>';
      return '<clipitem id="clip-'+index.toString()+'"><name>'+esc(layer.name)+'</name>'+
          rate+'<start>'+st.toString()+'</start><end>'+en.toString()+'</end><in>'+
          ins.toString()+'</in><out>'+outs.toString()+'</out>'+file+
          _premiereFiltersXml(layer)+'</clipitem>';
    }
    String transitionXml(CompositionTransition transition) {
      final start = frame(transition.startMs);
      final end = start + frame(transition.durationMs);
      final display = _s(
        transition.metadata['sourceName'],
        TransitionCatalog.displayName(transition.kind),
      );
      final effectId = _s(
        transition.externalMatchName,
        TransitionCatalog.xfadeName(transition.kind),
      );
      return '<transitionitem>' + rate +
        '<start>' + start.toString() + '</start>' +
        '<end>' + end.toString() + '</end>' +
        '<alignment>center</alignment>' +
        '<effect><name>' + esc(display) + '</name>' +
        '<effectid>' + esc(effectId) + '</effectid>' +
        '<effectcategory>Transition</effectcategory>' +
        '<effecttype>transition</effecttype><mediatype>video</mediatype>' +
        '</effect></transitionitem>';
    }
    String trackXml(List<CompositionLayer> track) {
      final ids = track.map((layer) => layer.id).toSet();
      final timelineItems = <({int startMs, int order, String xml})>[];
      for (final layer in track) {
        timelineItems.add((startMs: layer.startMs, order: 0, xml: clip(layer)));
      }
      for (final transition in doc.transitions) {
        if (ids.contains(transition.fromLayerId) &&
            ids.contains(transition.toLayerId)) {
          timelineItems.add((
            startMs: transition.startMs,
            order: 1,
            xml: transitionXml(transition),
          ));
        }
      }
      timelineItems.sort((a,b) {
        final byTime = a.startMs.compareTo(b.startMs);
        return byTime == 0 ? a.order.compareTo(b.order) : byTime;
      });
      return '<track>' + timelineItems.map((item) => item.xml).join() + '</track>';
    }
    final v=videoTracks.map(trackXml).join(),a=audioTracks.map(trackXml).join();
    return '<?xml version="1.0" encoding="UTF-8"?>'+
      '<!DOCTYPE xmeml><xmeml version="5"><sequence id="depthvibe"><name>'+
      esc(doc.name)+'</name><duration>'+frame(doc.durationMs).toString()+
      '</duration>'+rate+'<media><video><format><samplecharacteristics>'+
      rate+'<width>'+doc.width.toString()+'</width><height>'+
      doc.height.toString()+'</height></samplecharacteristics></format>'+
      v+'</video><audio>'+a+'</audio></media></sequence>'+
      '<!-- Premiere track grouping, supported transitionitems and verified static Gaussian Blur filters are emitted. Native transition identifiers are retained when imported from Adobe. -->'+
      '</xmeml>';
  }

  static String buildAfterEffectsScript(CompositionDocument doc){
    final encoded=jsonEncode(jsonEncode(buildInterchangeBundle(doc)));
    return '''
(function(){
 var bundle=JSON.parse(__DATA__),d=bundle.document;
 app.beginUndoGroup("DepthVibe Interchange Import");
 var comp=app.project.items.addComp(String(d.name||"DepthVibe Composition"),Number(d.width)||1920,
  Number(d.height)||1080,1,Math.max(1,Number(d.durationMs)/1000),Number(d.frameRate)||30);
 var made={},warnings=[];
 function put(g,n,v){try{var p=g.property(n);if(p&&v!==undefined)p.setValue(v);}catch(_){}}
 function layerVector(value,fallback,dimensions) {
  var result=value?[value.x,value.y,value.z]:fallback;
  return dimensions===3?result:result.slice(0,2);
 }
 function interpolation(mode) {
  if(mode==="hold") return KeyframeInterpolationType.HOLD;
  if(mode==="cubicBezier" || mode==="bezier") return KeyframeInterpolationType.BEZIER;
  return KeyframeInterpolationType.LINEAR;
 }
 function easeObjects(raw) {
  if(!raw || !raw.length) return null;
  var result=[];
  for(var i=0;i<raw.length;i++) {
   var speed=Number(raw[i].speed),influence=Number(raw[i].influence);
   if(!isFinite(speed)||!isFinite(influence)) return null;
   result.push(new KeyframeEase(speed,Math.max(0.1,Math.min(100,influence))));
  }
  return result;
 }
 function applyKeyMetadata(property,keyIndex,key,dimensions) {
  if(!property || !key) return;
  var meta=key.metadata||{};
  var inMode=meta.inInterpolation||key.interpolation;
  var outMode=meta.outInterpolation||key.interpolation;
  try { property.setInterpolationTypeAtKey(keyIndex,interpolation(inMode),interpolation(outMode)); }
  catch(err) { warnings.push("Interpolation metadata skipped: "+String(err)); }
  try { if(typeof meta.temporalAutoBezier==="boolean") property.setTemporalAutoBezierAtKey(keyIndex,meta.temporalAutoBezier); } catch(_) {}
  try { if(typeof meta.temporalContinuous==="boolean") property.setTemporalContinuousAtKey(keyIndex,meta.temporalContinuous); } catch(_) {}
  try { if(typeof meta.spatialAutoBezier==="boolean") property.setSpatialAutoBezierAtKey(keyIndex,meta.spatialAutoBezier); } catch(_) {}
  try { if(typeof meta.spatialContinuous==="boolean") property.setSpatialContinuousAtKey(keyIndex,meta.spatialContinuous); } catch(_) {}
  // Restore explicit ease/tangent values after auto-Bezier flags.
  try {
   var incoming=easeObjects(meta.inTemporalEase),outgoing=easeObjects(meta.outTemporalEase);
   if(incoming && outgoing) property.setTemporalEaseAtKey(keyIndex,incoming,outgoing);
  } catch(err) { warnings.push("Temporal ease skipped: "+String(err)); }
  try {
   var spatialIn=meta.inSpatialTangent,spatialOut=meta.outSpatialTangent;
   if(spatialIn && spatialOut && spatialIn.length===dimensions && spatialOut.length===dimensions &&
      typeof property.setSpatialTangentsAtKey==="function")
    property.setSpatialTangentsAtKey(keyIndex,spatialIn,spatialOut);
  } catch(err) { warnings.push("Spatial tangent skipped: "+String(err)); }
  try { if(typeof meta.roving==="boolean") property.setRovingAtKey(keyIndex,meta.roving); } catch(_) {}
 }
 function applyScalarTrack(property,track) {
  if(!property || !track || !track.keyframes) return;
  for(var k=0;k<track.keyframes.length;k++) {
   var key=track.keyframes[k],time=Number(key.timeMs)/1000;
   if(!isFinite(time) || !isFinite(Number(key.value))) continue;
   try {
    property.setValueAtTime(time,Number(key.value));
    var keyIndex=property.nearestKeyIndex(time);
    applyKeyMetadata(property,keyIndex,key,1);
   } catch(err) { warnings.push("Keyframe "+track.property+" skipped: "+String(err)); }
  }
 }
 function trackByName(tracks,name) {
  for(var i=0;i<tracks.length;i++) if(tracks[i].property===name) return tracks[i];
  return null;
 }
 function sampleTrack(track,timeMs,fallback) {
  if(!track || !track.keyframes || !track.keyframes.length) return fallback;
  var keys=track.keyframes;
  if(timeMs<=Number(keys[0].timeMs)) return Number(keys[0].value);
  if(timeMs>=Number(keys[keys.length-1].timeMs)) return Number(keys[keys.length-1].value);
  for(var i=0;i<keys.length-1;i++) {
   var left=keys[i],right=keys[i+1],t0=Number(left.timeMs),t1=Number(right.timeMs);
   if(timeMs<t0 || timeMs>t1) continue;
   if(left.interpolation==="hold" || t1<=t0) return Number(left.value);
   var f=(timeMs-t0)/(t1-t0);
   return Number(left.value)+(Number(right.value)-Number(left.value))*f;
  }
  return fallback;
 }
 function applyVectorTracks(property,tracks,prefix,base,dimensions) {
  if(!property) return;
  var axes=["x","y","z"],axisTracks=[],times={};
  for(var axis=0;axis<dimensions;axis++) {
   var found=trackByName(tracks,prefix+"."+axes[axis]);
   axisTracks.push(found);
   if(found && found.keyframes) for(var k=0;k<found.keyframes.length;k++)
    times[String(found.keyframes[k].timeMs)]=Number(found.keyframes[k].timeMs);
  }
  var ordered=Object.keys(times).map(function(key){return times[key];}).sort(function(a,b){return a-b;});
  for(var t=0;t<ordered.length;t++) {
   var ms=ordered[t],value=[];
   for(var dim=0;dim<dimensions;dim++) value.push(sampleTrack(axisTracks[dim],ms,base[dim]));
   var time=ms/1000;
   try {
    property.setValueAtTime(time,value);
    var index=property.nearestKeyIndex(time),curveKey=null,mode="linear";
    for(var dim2=0;dim2<dimensions;dim2++) if(axisTracks[dim2] && axisTracks[dim2].keyframes)
     for(var q=0;q<axisTracks[dim2].keyframes.length;q++)
      if(Number(axisTracks[dim2].keyframes[q].timeMs)===ms) {
       curveKey=axisTracks[dim2].keyframes[q];
       mode=curveKey.interpolation||mode;
      }
    if(curveKey) applyKeyMetadata(property,index,curveKey,dimensions);
    else property.setInterpolationTypeAtKey(index,interpolation(mode),interpolation(mode));
   } catch(err) { warnings.push("Keyframe "+prefix+" skipped: "+String(err)); }
  }
 }
 function fx(id){var m={brightness:"ADBE Brightness & Contrast 2",contrast:"ADBE Brightness & Contrast 2",
  gaussian_blur:"ADBE Gaussian Blur 2",sharpen:"ADBE Sharpen",invert:"ADBE Invert",saturation:"ADBE Hue/Saturation"};return m[id]||null;}
 function effectProperty(group, descriptor) {
  if(!group||!descriptor) return null;
  var path=descriptor.path||[descriptor.matchName||descriptor.name];
  if(!(path instanceof Array)||!path.length) return null;
  var current=group;
  for(var pi=0;pi<path.length;pi++) {
   if(!path[pi]) continue;
   try { current=current.property(path[pi]); } catch(_) { return null; }
   if(!current) return null;
  }
  return current;
 }
 function applyNativeParameters(group, parameters) {
  if(!group||!(parameters instanceof Array)) return;
  for(var ni=0;ni<parameters.length;ni++) {
   var item=parameters[ni],property=effectProperty(group,item);
   if(!property) continue;
   if(item.parameters instanceof Array && item.parameters.length) {
    applyNativeParameters(property,item.parameters);
    continue;
   }
   if(item.keyframes instanceof Array && item.keyframes.length) {
    applyScalarTrack(property,{
     property:item.matchName||item.name||"native",
     keyframes:item.keyframes
    });
   } else if(item.value!==undefined && item.value!==null) {
    try {
     var val=item.value;
     if(typeof val==="number"||typeof val==="string"||typeof val==="boolean"||
        (val instanceof Array && val.length>0)) {
      if(!property.isTimeVarying) property.setValue(val);
     }
    } catch(err) { warnings.push("Native parameter "+String(item.name||item.matchName)+" skipped: "+String(err)); }
   }
  }
 }
 for(var i=0;i<d.layers.length;i++){
  var x=d.layers[i],l=null;
  try{if(x.sourceUri&&new File(x.sourceUri).exists)l=comp.layers.add(app.project.importFile(new ImportOptions(new File(x.sourceUri))));}
  catch(e){warnings.push(x.name+": "+String(e));}
  try{
   if(!l&&x.kind==="text")l=comp.layers.addText(x.textContent||x.name);
   else if(!l&&x.kind==="nullObject")l=comp.layers.addNull();
   else if(!l&&x.kind==="camera")l=comp.layers.addCamera(x.name,[d.width/2,d.height/2]);
   else if(!l&&x.kind==="light")l=comp.layers.addLight(x.name,[d.width/2,d.height/2]);
   else if(!l){l=comp.layers.addSolid([0.16,0.18,0.24],x.name,d.width,d.height,1,Math.max(1,x.durationMs/1000));warnings.push(x.name+": editable solid placeholder; relink media.");}
  }catch(e){warnings.push(x.name+": layer skipped: "+String(e));continue;}
  l.name=x.name;l.startTime=Number(x.startMs)/1000;l.inPoint=Number(x.startMs)/1000;
  l.outPoint=Math.min(comp.duration,(Number(x.startMs)+Number(x.durationMs))/1000);
  l.enabled=x.enabled!==false;l.solo=x.solo===true;l.locked=x.locked===true;
  var layerMeta=x.interchangeMetadata||{},is3D=(x.kind==="camera"||x.kind==="light"||layerMeta.threeDLayer===true);
   try { if(typeof layerMeta.threeDLayer==="boolean"||is3D) l.threeDLayer=is3D; } catch(_){}
   var dimensions=is3D?3:2,layerTracks=x.keyframeTracks||[],tr=x.transform||{};
   var t=l.property("ADBE Transform Group");
   if(t){
    if(tr.position)put(t,"ADBE Position",layerVector(tr.position,[d.width/2,d.height/2,0],dimensions));
    if(tr.anchor)put(t,"ADBE Anchor Point",layerVector(tr.anchor,[0,0,0],dimensions));
    if(tr.scale)put(t,"ADBE Scale",layerVector(tr.scale,[100,100,100],dimensions));
    if(tr.rotation)put(t,"ADBE Rotate Z",tr.rotation.z);
    put(t,"ADBE Opacity",tr.opacity);
    applyVectorTracks(t.property("ADBE Position"),layerTracks,"position",
      tr.position?[tr.position.x,tr.position.y,tr.position.z]:[d.width/2,d.height/2,0],dimensions);
    applyVectorTracks(t.property("ADBE Anchor Point"),layerTracks,"anchor",
      tr.anchor?[tr.anchor.x,tr.anchor.y,tr.anchor.z]:[0,0,0],dimensions);
    applyVectorTracks(t.property("ADBE Scale"),layerTracks,"scale",
      tr.scale?[tr.scale.x,tr.scale.y,tr.scale.z]:[100,100,100],dimensions);
    applyScalarTrack(t.property("ADBE Rotate Z"),trackByName(layerTracks,"rotation.z"));
    applyScalarTrack(t.property("ADBE Opacity"),trackByName(layerTracks,"opacity"));
   }
   made[x.id]=l;var parade=l.property("ADBE Effect Parade");
  if(parade&&x.effects)for(var e=0;e<x.effects.length;e++){
   var ef=x.effects[e],nativeDescriptor=ef.nativeDescriptor||{},mn=fx(ef.effectId);
   if(!mn && nativeDescriptor.matchName) mn=nativeDescriptor.matchName;
   try{if(!mn||!parade.canAddProperty(mn)){warnings.push(x.name+": unavailable effect "+String(mn||ef.name));continue;}
    var added=parade.addProperty(mn),p=ef.parameters||{};
    try { added.enabled=ef.enabled!==false; } catch(_){}
    if(ef.effectId==="gaussian_blur")put(added,"ADBE Gaussian Blur 2-0001",p.sigma);
    if(ef.effectId==="brightness")put(added,"ADBE Brightness & Contrast 2-0001",p.value*100);
    if(ef.effectId==="contrast")put(added,"ADBE Brightness & Contrast 2-0002",(p.value-1)*100);
    if(ef.effectId==="sharpen")put(added,"ADBE Sharpen-0001",p.amount);
    if(ef.effectId==="saturation")put(added,"ADBE Hue/Saturation-0004",(p.value-1)*100);
    var parameterNames={gaussian_blur:{sigma:"ADBE Gaussian Blur 2-0001"},brightness:{value:"ADBE Brightness & Contrast 2-0001"},contrast:{value:"ADBE Brightness & Contrast 2-0002"},sharpen:{amount:"ADBE Sharpen-0001"},saturation:{value:"ADBE Hue/Saturation-0004"}};
    var parameterMap=parameterNames[ef.effectId]||{};
    if(ef.keyframeTracks) for(var kt=0;kt<ef.keyframeTracks.length;kt++) {
     var track=ef.keyframeTracks[kt],propertyName=parameterMap[track.property];
     if(propertyName) applyScalarTrack(added.property(propertyName),track);
    }
    if(nativeDescriptor.parameters instanceof Array)
     applyNativeParameters(added,nativeDescriptor.parameters);
   }catch(err){warnings.push(x.name+": effect skipped "+String(err));}
  }
  // Try the exact native matchName for source effects without a DepthVibe map.
  // The target host must have the same plug-in installed; expressions are never run.
  var rawEffects=layerMeta.unsupportedEffects||[];
  for(var rawIndex=0;rawIndex<rawEffects.length;rawIndex++) {
   var rawEffect=rawEffects[rawIndex],rawMatch=rawEffect.matchName||rawEffect.name;
   try {
    var currentParade=made[x.id].property("ADBE Effect Parade");
    if(!rawMatch||!currentParade||!currentParade.canAddProperty(rawMatch)) {
     warnings.push(x.name+": unavailable native effect "+String(rawMatch||"unknown"));
     continue;
    }
    var nativeEffect=currentParade.addProperty(rawMatch);
    try { nativeEffect.enabled=rawEffect.enabled!==false; } catch(_){}
    var rawProperties=rawEffect.properties||[];
    for(var rawPropertyIndex=0;rawPropertyIndex<rawProperties.length;rawPropertyIndex++) {
     var rawProperty=rawProperties[rawPropertyIndex],targetProperty=null;
     try { if(rawProperty.matchName) targetProperty=nativeEffect.property(rawProperty.matchName); } catch(_){}
     try { if(!targetProperty&&rawProperty.name) targetProperty=nativeEffect.property(rawProperty.name); } catch(_){}
     if(!targetProperty) continue;
     if(typeof rawProperty.value==="number" ||
        (rawProperty.value instanceof Array && rawProperty.value.length>0)) {
      try { if(!targetProperty.isTimeVarying) targetProperty.setValue(rawProperty.value); } catch(_){}
     }
     if(rawProperty.keyframes && rawProperty.keyframes.length) {
      var normalizedFrames=[];
      for(var rfi=0;rfi<rawProperty.keyframes.length;rfi++) {
       var sourceKey=rawProperty.keyframes[rfi],curveMeta={};
       var curveKeys=["inInterpolation","outInterpolation","inTemporalEase","outTemporalEase",
        "inSpatialTangent","outSpatialTangent","roving","spatialAutoBezier",
        "spatialContinuous","temporalAutoBezier","temporalContinuous"];
       for(var ck=0;ck<curveKeys.length;ck++) if(sourceKey[curveKeys[ck]]!==undefined)
        curveMeta[curveKeys[ck]]=sourceKey[curveKeys[ck]];
       normalizedFrames.push({timeMs:sourceKey.timeMs,value:sourceKey.value,
        interpolation:sourceKey.interpolation,metadata:curveMeta});
      }
      applyScalarTrack(targetProperty,{property:rawProperty.name||rawProperty.matchName,keyframes:normalizedFrames});
     }
    }
   } catch(nativeError) { warnings.push(x.name+": native effect "+String(rawMatch)+" skipped: "+String(nativeError)); }
  }
 }
 function setTransitionValue(property,time,value) {
  if(!property) return;
  property.setValueAtTime(time,value);
  var index=property.nearestKeyIndex(time);
  property.setInterpolationTypeAtKey(index,KeyframeInterpolationType.BEZIER,KeyframeInterpolationType.BEZIER);
 }
 function applyImportedTransitions() {
  var transitions=d.transitions||[];
  for(var ti=0;ti<transitions.length;ti++) {
   var transition=transitions[ti],from=made[transition.fromLayerId],to=made[transition.toLayerId];
   if(!from||!to) { warnings.push("Transition "+String(transition.id)+" references a missing layer."); continue; }
   var start=Number(transition.startMs)/1000,duration=Number(transition.durationMs)/1000;
   if(!isFinite(start)||!isFinite(duration)||duration<=0) continue;
   var end=start+duration,kind=String(transition.kind||"dissolve");
   try {
    var fromOpacity=from.property("ADBE Transform Group").property("ADBE Opacity");
    var toOpacity=to.property("ADBE Transform Group").property("ADBE Opacity");
    setTransitionValue(fromOpacity,start,100);
    setTransitionValue(fromOpacity,end,0);
    setTransitionValue(toOpacity,start,0);
    setTransitionValue(toOpacity,end,100);
    if(kind==="slideLeft"||kind==="slideRight"||kind==="slideUp"||kind==="slideDown") {
     var dimension=(kind==="slideLeft"||kind==="slideRight")?Number(d.width):Number(d.height);
     var axis=(kind==="slideLeft"||kind==="slideRight")?0:1;
     var direction=(kind==="slideLeft"||kind==="slideUp")?1:-1;
     var fromTransform=from.property("ADBE Transform Group");
     var toTransform=to.property("ADBE Transform Group");
     var fromPosition=fromTransform.property("ADBE Position");
     var toPosition=toTransform.property("ADBE Position");
     var fromBase=fromPosition.valueAtTime(start,false),toBase=toPosition.valueAtTime(start,false);
     var fromEnd=fromBase.slice(0),toStart=toBase.slice(0);
     fromEnd[axis]-=direction*dimension;
     toStart[axis]+=direction*dimension;
     setTransitionValue(fromPosition,start,fromBase);
     setTransitionValue(fromPosition,end,fromEnd);
     setTransitionValue(toPosition,start,toStart);
     setTransitionValue(toPosition,end,toBase);
    } else if(kind==="zoomIn"||kind==="zoomOut") {
     var fromScale=from.property("ADBE Transform Group").property("ADBE Scale");
     var toScale=to.property("ADBE Transform Group").property("ADBE Scale");
     var fromBaseScale=fromScale.valueAtTime(start,false),toBaseScale=toScale.valueAtTime(start,false);
     var factor=kind==="zoomIn"?0.2:1.2;
     var fromEndScale=fromBaseScale.map(function(v){return v*factor;});
     var toStartScale=toBaseScale.map(function(v){return v*factor;});
     setTransitionValue(fromScale,start,fromBaseScale);
     setTransitionValue(fromScale,end,fromEndScale);
     setTransitionValue(toScale,start,toStartScale);
     setTransitionValue(toScale,end,toBaseScale);
    }
    if(transition.externalMatchName)
     warnings.push("Transition "+String(transition.externalMatchName)+" was recreated as editable motion; proprietary transition parameters are not executed.");
   } catch(err) { warnings.push("Transition "+String(transition.id)+" partially applied: "+String(err)); }
  }
 }
 applyImportedTransitions();
 for(var j=0;j<d.layers.length;j++){var x=d.layers[j];if(x.parentId&&made[x.parentId]&&made[x.id])try{made[x.id].parent=made[x.parentId];}catch(_){}}
 app.endUndoGroup();alert("Imported "+d.layers.length+" editable layers. "+(warnings.length?"Review: "+warnings.join("\\n"):""));
}());
'''.replaceAll('__DATA__',encoded);
  }
}
