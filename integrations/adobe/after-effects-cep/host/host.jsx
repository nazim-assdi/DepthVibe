// After Effects CEP host-side metadata adapter.
// Runs only inside the installed Adobe After Effects CEP host.

function depthVibeSafeValue(group, matchName) {
  try {
    var property = group && group.property(matchName);
    if (!property) return null;
    var value = property.value;
    if (typeof value === "number" || typeof value === "string" || typeof value === "boolean") return value;
    if (value instanceof Array) return value.slice(0, 4);
    return null;
  } catch (_) { return null; }
}
function depthVibeTransform(layer) {
  var group = layer.property("ADBE Transform Group");
  return {
    position: depthVibeSafeValue(group, "ADBE Position"),
    anchorPoint: depthVibeSafeValue(group, "ADBE Anchor Point"),
    scale: depthVibeSafeValue(group, "ADBE Scale"),
    rotation: depthVibeSafeValue(group, "ADBE Rotate Z"),
    opacity: depthVibeSafeValue(group, "ADBE Opacity")
  };
}
function depthVibeKeyInterpolation(property, keyIndex) {
  try {
    var value = property.keyOutInterpolationType(keyIndex);
    if (value === KeyframeInterpolationType.HOLD) return "hold";
    if (value === KeyframeInterpolationType.BEZIER) return "cubicBezier";
    if (value === KeyframeInterpolationType.LINEAR) return "linear";
  } catch (_) {}
  return "linear";
}
function depthVibePropertyKeyframes(property, propertyPath) {
  try {
    if (!property || typeof property.numKeys !== "number" ||
        typeof property.keyTime !== "function" || typeof property.keyValue !== "function") return [];
    var count=Math.min(property.numKeys,10000);
    if(count<1)return [];
    var first=property.keyValue(1),vector=first instanceof Array && first.length>0;
    if(vector) for(var v=0;v<first.length;v++) if(typeof first[v]!=="number") vector=false;
    var axisNames=["x","y","z","w"],paths=vector?axisNames.slice(0,Math.min(first.length,4)):[""];
    var result=[];
    for(var axis=0;axis<paths.length;axis++) {
      var frames=[];
      for(var index=1;index<=count;index++) {
        try {
          var raw=property.keyValue(index),time=property.keyTime(index),value=vector?raw[axis]:raw;
          if(typeof value!=="number"||!isFinite(value)||typeof time!=="number"||!isFinite(time))continue;
          frames.push({timeMs:Math.round(time*1000),value:value,interpolation:depthVibeKeyInterpolation(property,index)});
        } catch (_) {}
      }
      if(frames.length)result.push({property:propertyPath+(vector?"."+paths[axis]:""),keyframes:frames});
    }
    return result;
  } catch (_) { return []; }
}
function depthVibeLayerAnimation(layer) {
  var group=layer.property("ADBE Transform Group");
  var properties=[["ADBE Position","position"],["ADBE Anchor Point","anchor"],["ADBE Scale","scale"],["ADBE Rotate Z","rotation.z"],["ADBE Opacity","opacity"]];
  var tracks=[],expressions=[];
  for(var i=0;i<properties.length;i++) {
    var property=group?group.property(properties[i][0]):null;
    if(!property)continue;
    var found=depthVibePropertyKeyframes(property,properties[i][1]);
    for(var j=0;j<found.length;j++)tracks.push(found[j]);
    try {
      if(typeof property.expression==="string"&&property.expression.length)
        expressions.push({property:properties[i][1],source:property.expression,enabled:property.expressionEnabled===true});
    } catch (_) {}
  }
  return {keyframeTracks:tracks,expressions:expressions};
}

function depthVibeScalarKeyframes(property) {
  try {
    if (!property || typeof property.numKeys !== "number" ||
        typeof property.keyTime !== "function" || typeof property.keyValue !== "function") return [];
    var count=Math.min(property.numKeys,10000),frames=[];
    for(var i=1;i<=count;i++) {
      try {
        var value=property.keyValue(i),time=property.keyTime(i);
        if(typeof value!=="number"||!isFinite(value)||typeof time!=="number"||!isFinite(time))continue;
        frames.push({timeMs:Math.round(time*1000),value:value,interpolation:depthVibeKeyInterpolation(property,i)});
      } catch (_) {}
    }
    return frames;
  } catch (_) { return []; }
}
function depthVibeEffects(layer) {
  var group = layer.property("ADBE Effect Parade"), effects = [];
  if (!group) return effects;
  for (var i=1; i<=Math.min(group.numProperties || 0,128); i++) {
    var effect=group.property(i), properties=[];
    if (!effect) continue;
    for (var p=1; p<=Math.min(effect.numProperties || 0,128); p++) {
      var prop=effect.property(p), value=prop?depthVibeSafeValue(effect,prop.matchName):null;
      if (prop && value!==null) properties.push({
        matchName:prop.matchName,name:prop.name,value:value,
        keyframes:depthVibeScalarKeyframes(prop),
        expression:(typeof prop.expression==="string"&&prop.expression.length)
          ? {source:prop.expression,enabled:prop.expressionEnabled===true} : null
      });
    }
    effects.push({matchName:effect.matchName,name:effect.name,enabled:effect.enabled!==false,properties:properties});
  }
  return effects;
}

function depthVibeGetActiveCompSnapshot() {
  try {
    var project = app.project;
    if (!project) {
      throw new Error("No After Effects project is open.");
    }
    var comp = project.activeItem;
    if (!(comp instanceof CompItem)) {
      throw new Error("Select an active composition before capturing metadata.");
    }

    var layers = [];
    for (var index = 1; index <= comp.numLayers; index += 1) {
      var layer = comp.layer(index);
      var parent = layer.parent;
      var animation = depthVibeLayerAnimation(layer);
      var source = layer.source;
      var footageFile = source && source.file ? source.file : null;
      var textContent = null;
      try { var textDoc=layer.property('ADBE Text Properties').property('ADBE Text Document').value; textContent=textDoc?textDoc.text:null; } catch (_) {}
      layers.push({
        id: layer.id,
        index: layer.index,
        name: layer.name,
        matchName: layer.matchName,
        startTimeSeconds: layer.startTime,
        inPointSeconds: layer.inPoint,
        outPointSeconds: layer.outPoint,
        enabled: layer.enabled,
        solo: layer.solo,
        locked: layer.locked,
        shy: layer.shy,
        threeDLayer: layer.threeDLayer,
        adjustmentLayer: layer.adjustmentLayer,
        nullLayer: layer.nullLayer,
        stretchPercent: layer.stretch,
        parentLayerId: parent ? parent.id : null,
        parentLayerName: parent ? parent.name : null,
        hasVideo: layer.hasVideo,
        hasAudio: layer.hasAudio,
        sourcePath: footageFile && footageFile.fsName ? footageFile.fsName : null,
        source: source ? {name:source.name||null,width:source.width||null,height:source.height||null,path:footageFile&&footageFile.fsName?footageFile.fsName:null} : null,
        textContent: textContent,
        transform: depthVibeTransform(layer),
        keyframeTracks: animation.keyframeTracks,
        expressions: animation.expressions,
        effects: depthVibeEffects(layer),
        blendMode: layer.blendingMode !== undefined ? String(layer.blendingMode) : null
      });
    }

    return JSON.stringify({
      schemaVersion: 1,
      hostApp: "aftereffects",
      hostVersion: String(app.version || "CEP"),
      capturedAt: new Date().toISOString(),
      payload: {
        sourceType: "after-effects-cep-composition-snapshot",
        project: {
          fileName: project.file ? project.file.name : "",
          numItems: project.numItems
        },
        composition: {
          id: comp.id,
          name: comp.name,
          width: comp.width,
          height: comp.height,
          durationSeconds: comp.duration,
          frameRate: comp.frameRate,
          frameDurationSeconds: comp.frameDuration,
          displayStartTimeSeconds: comp.displayStartTime,
          displayStartFrame: comp.displayStartFrame,
          dropFrame: comp.dropFrame,
          workAreaStartSeconds: comp.workAreaStart,
          workAreaDurationSeconds: comp.workAreaDuration,
          numLayers: comp.numLayers,
          backgroundColor: comp.bgColor
        },
        layers: layers,
        transferScope: "metadata-only; footage files, plugin binaries and rendered frames are not copied"
      }
    });
  } catch (error) {
    return JSON.stringify({error: String(error)});
  }
}

function depthVibeGetHostInfo() {
  return {
    hostApplication: "Adobe After Effects",
    hostVersion: String(app.version || "Unknown"),
    jsxEngine: "ExtendScript",
    bridge: "DepthVibe authenticated localhost bridge"
  };
}
