// After Effects CEP host-side metadata adapter.
// Runs only inside the installed Adobe After Effects CEP host.
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
        hasAudio: layer.hasAudio
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
