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
function depthVibeEffects(layer) {
  var group = layer.property("ADBE Effect Parade"), effects = [];
  if (!group) return effects;
  for (var i=1; i<=Math.min(group.numProperties || 0,128); i++) {
    var effect=group.property(i), properties=[];
    if (!effect) continue;
    for (var p=1; p<=Math.min(effect.numProperties || 0,128); p++) {
      var prop=effect.property(p), value=prop?depthVibeSafeValue(effect,prop.matchName):null;
      if (prop && value!==null) properties.push({matchName:prop.matchName,name:prop.name,value:value});
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
