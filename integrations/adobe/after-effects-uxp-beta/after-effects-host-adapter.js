const afterEffects = require("aftereffects");
const { host } = require("uxp");

function captureActiveComposition() {
  const project = afterEffects.project;
  if (!project) {
    throw new Error("Open an After Effects project first.");
  }
  const composition = project.activeItem;
  if (!composition ||
      typeof composition.layer !== "function" ||
      typeof composition.numLayers !== "number") {
    throw new Error("Select an active After Effects composition in the Project or Composition panel.");
  }

  const layers = [];
  for (let index = 1; index <= composition.numLayers; index += 1) {
    const layer = composition.layer(index);
    const parent = layer.parent;
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

  const hostVersion = host && host.version ? host.version : "Unknown";
  return {
    schemaVersion: 1,
    hostApp: "aftereffects-beta",
    hostVersion: hostVersion,
    capturedAt: new Date().toISOString(),
    payload: {
      sourceType: "after-effects-composition-snapshot",
      project: {
        fileName: project.file
          ? String(project.file).split(/[\\/]/).pop()
          : "",
        isDirty: project.dirty === true,
        revision: typeof project.revision === "number" ? project.revision : null,
        bitsPerChannel: project.bitsPerChannel
      },
      composition: {
        id: composition.id,
        name: composition.name,
        width: composition.width,
        height: composition.height,
        durationSeconds: composition.duration,
        frameRate: composition.frameRate,
        frameDurationSeconds: composition.frameDuration,
        displayStartTimeSeconds: composition.displayStartTime,
        displayStartFrame: composition.displayStartFrame,
        dropFrame: composition.dropFrame,
        workAreaStartSeconds: composition.workAreaStart,
        workAreaDurationSeconds: composition.workAreaDuration,
        numLayers: composition.numLayers,
        backgroundColor: composition.bgColor
      },
      layers: layers,
      transferScope: "metadata-only; footage files, plugin binaries and rendered frames are not copied"
    }
  };
}

module.exports = { captureActiveComposition };
