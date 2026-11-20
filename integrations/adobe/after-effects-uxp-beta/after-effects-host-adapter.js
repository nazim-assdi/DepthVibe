const afterEffects = require("aftereffects");
const { host } = require("uxp");


function safePropertyValue(group, matchName) {
  try {
    const property = group && group.property(matchName);
    if (!property) return null;
    const value = property.value;
    if (typeof value === "number" || typeof value === "string" || typeof value === "boolean") return value;
    if (Array.isArray(value)) return value.slice(0, 4).map(Number);
    return null;
  } catch (_) { return null; }
}
function captureTransform(layer) {
  const group = layer.property("ADBE Transform Group");
  return {
    position: safePropertyValue(group, "ADBE Position"),
    anchorPoint: safePropertyValue(group, "ADBE Anchor Point"),
    scale: safePropertyValue(group, "ADBE Scale"),
    rotation: safePropertyValue(group, "ADBE Rotate Z"),
    opacity: safePropertyValue(group, "ADBE Opacity")
  };
}
function captureEffects(layer) {
  const group = layer.property("ADBE Effect Parade"), effects = [];
  if (!group) return effects;
  for (let i = 1; i <= Math.min(group.numProperties || 0, 128); i += 1) {
    const effect = group.property(i), properties = [];
    if (!effect) continue;
    for (let p = 1; p <= Math.min(effect.numProperties || 0, 128); p += 1) {
      const property = effect.property(p);
      if (!property) continue;
      const value = safePropertyValue(effect, property.matchName);
      if (value !== null) properties.push({ matchName: property.matchName, name: property.name, value: value });
    }
    effects.push({ matchName: effect.matchName, name: effect.name, enabled: effect.enabled !== false, properties: properties });
  }
  return effects;
}

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
    const source = layer.source;
    const sourcePath = source && typeof source.file === "string" ? source.file : null;
    let textContent = null;
    try {
      const textDocument = layer.property("ADBE Text Properties").property("ADBE Text Document").value;
      textContent = textDocument && typeof textDocument.text === "string" ? textDocument.text : null;
    } catch (_) {}
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
      sourcePath: sourcePath,
      source: source ? { name: source.name || null, width: source.width || null, height: source.height || null, path: sourcePath } : null,
      textContent: textContent,
      transform: captureTransform(layer),
      effects: captureEffects(layer),
      blendMode: layer.blendingMode !== undefined ? String(layer.blendingMode) : null
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
