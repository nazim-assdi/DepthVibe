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
function keyInterpolation(property, keyIndex) {
  try {
    const value = property.keyOutInterpolationType(keyIndex);
    const types = afterEffects.KeyframeInterpolationType || {};
    if (value === types.HOLD || String(value).toLowerCase().indexOf("hold") >= 0) return "hold";
    if (value === types.BEZIER || String(value).toLowerCase().indexOf("bezier") >= 0) return "cubicBezier";
    if (value === types.LINEAR || String(value).toLowerCase().indexOf("linear") >= 0) return "linear";
  } catch (_) {}
  return "linear";
}
function capturePropertyKeyframes(property, propertyPath) {
  try {
    if (!property || typeof property.numKeys !== "number" ||
        typeof property.keyTime !== "function" || typeof property.keyValue !== "function") return [];
    const count = Math.min(property.numKeys, 10000);
    if (count < 1) return [];
    const first = property.keyValue(1);
    const isVector = Array.isArray(first) && first.length > 0 &&
      first.every(function (item) { return typeof item === "number" && Number.isFinite(item); });
    const axes = ["x", "y", "z", "w"];
    const paths = isVector
      ? axes.slice(0, Math.min(first.length, 4)).map(function (axis) { return propertyPath + "." + axis; })
      : [propertyPath];
    const tracks = paths.map(function (path, axis) {
      const keyframes = [];
      for (let index = 1; index <= count; index += 1) {
        try {
          const raw = property.keyValue(index), time = property.keyTime(index);
          const value = isVector ? raw[axis] : raw;
          if (typeof value !== "number" || !Number.isFinite(value) ||
              typeof time !== "number" || !Number.isFinite(time)) continue;
          keyframes.push({
            timeMs: Math.round(time * 1000),
            value: value,
            interpolation: keyInterpolation(property, index)
          });
        } catch (_) {}
      }
      return { property: path, keyframes: keyframes };
    }).filter(function (track) { return track.keyframes.length > 0; });
    return tracks;
  } catch (_) { return []; }
}
function captureLayerAnimation(layer) {
  const group = layer.property("ADBE Transform Group");
  const properties = [
    ["ADBE Position", "position"],
    ["ADBE Anchor Point", "anchor"],
    ["ADBE Scale", "scale"],
    ["ADBE Rotate Z", "rotation.z"],
    ["ADBE Opacity", "opacity"]
  ];
  const keyframeTracks = [], expressions = [];
  for (let i = 0; i < properties.length; i += 1) {
    const property = group && group.property(properties[i][0]);
    if (!property) continue;
    keyframeTracks.push.apply(keyframeTracks, capturePropertyKeyframes(property, properties[i][1]));
    try {
      if (typeof property.expression === "string" && property.expression.length > 0) {
        expressions.push({ property: properties[i][1], source: property.expression, enabled: property.expressionEnabled === true });
      }
    } catch (_) {}
  }
  return { keyframeTracks: keyframeTracks, expressions: expressions };
}

function captureScalarPropertyKeyframes(property) {
  try {
    if (!property || typeof property.numKeys !== "number" ||
        typeof property.keyTime !== "function" || typeof property.keyValue !== "function") return [];
    const count = Math.min(property.numKeys, 10000), frames = [];
    for (let index = 1; index <= count; index += 1) {
      try {
        const value = property.keyValue(index), time = property.keyTime(index);
        if (typeof value !== "number" || !Number.isFinite(value) ||
            typeof time !== "number" || !Number.isFinite(time)) continue;
        frames.push({ timeMs: Math.round(time * 1000), value: value,
          interpolation: keyInterpolation(property, index) });
      } catch (_) {}
    }
    return frames;
  } catch (_) { return []; }
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
      if (value !== null) properties.push({
        matchName: property.matchName,
        name: property.name,
        value: value,
        keyframes: captureScalarPropertyKeyframes(property),
        expression: typeof property.expression === "string" && property.expression.length
          ? { source: property.expression, enabled: property.expressionEnabled === true }
          : null
      });
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
    const animation = captureLayerAnimation(layer);
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
      keyframeTracks: animation.keyframeTracks,
      expressions: animation.expressions,
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
