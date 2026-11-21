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
function keyInterpolation(property, keyIndex, side) {
  try {
    const method = side === "in" ? property.keyInInterpolationType : property.keyOutInterpolationType;
    const value = typeof method === "function" ? method.call(property, keyIndex) : property.keyOutInterpolationType(keyIndex);
    const types = afterEffects.KeyframeInterpolationType || {};
    if (value === types.HOLD || String(value).toLowerCase().indexOf("hold") >= 0) return "hold";
    if (value === types.BEZIER || String(value).toLowerCase().indexOf("bezier") >= 0) return "cubicBezier";
    if (value === types.LINEAR || String(value).toLowerCase().indexOf("linear") >= 0) return "linear";
  } catch (_) {}
  return "linear";
}
function captureEase(property, keyIndex, side) {
  try {
    const method = side === "in" ? property.keyInTemporalEase : property.keyOutTemporalEase;
    if (typeof method !== "function") return null;
    const values = method.call(property, keyIndex);
    if (!Array.isArray(values)) return null;
    return values.map(function (ease) {
      return { speed: Number(ease.speed), influence: Number(ease.influence) };
    }).filter(function (ease) {
      return Number.isFinite(ease.speed) && Number.isFinite(ease.influence);
    });
  } catch (_) { return null; }
}
function captureKeyframeMetadata(property, keyIndex) {
  const metadata = {
    inInterpolation: keyInterpolation(property, keyIndex, "in"),
    outInterpolation: keyInterpolation(property, keyIndex, "out"),
    inTemporalEase: captureEase(property, keyIndex, "in"),
    outTemporalEase: captureEase(property, keyIndex, "out")
  };
  if (property && property.isSpatial === true) {
    try { metadata.inSpatialTangent = property.keyInSpatialTangent(keyIndex); } catch (_) {}
    try { metadata.outSpatialTangent = property.keyOutSpatialTangent(keyIndex); } catch (_) {}
    try { metadata.roving = property.keyRoving(keyIndex) === true; } catch (_) {}
    try { metadata.spatialAutoBezier = property.keySpatialAutoBezier(keyIndex) === true; } catch (_) {}
    try { metadata.spatialContinuous = property.keySpatialContinuous(keyIndex) === true; } catch (_) {}
  }
  try { metadata.temporalAutoBezier = property.keyTemporalAutoBezier(keyIndex) === true; } catch (_) {}
  try { metadata.temporalContinuous = property.keyTemporalContinuous(keyIndex) === true; } catch (_) {}
  return metadata;
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
          keyframes.push(Object.assign({
            timeMs: Math.round(time * 1000),
            value: value,
            interpolation: keyInterpolation(property, index, "out")
          }, captureKeyframeMetadata(property, index)));
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
    ["ADBE Position", "position"], ["ADBE Anchor Point", "anchor"],
    ["ADBE Scale", "scale"], ["ADBE Rotate Z", "rotation.z"], ["ADBE Opacity", "opacity"]
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
        frames.push(Object.assign({
          timeMs: Math.round(time * 1000), value: value,
          interpolation: keyInterpolation(property, index, "out")
        }, captureKeyframeMetadata(property, index)));
      } catch (_) {}
    }
    return frames;
  } catch (_) { return []; }
}
function nativeSerializableValue(value) {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" || typeof value === "boolean") return value;
  if (Array.isArray(value) && value.length <= 16 &&
      value.every(function (item) {
        return typeof item === "number" && Number.isFinite(item);
      })) return value.slice();
  return null;
}
function captureNativeProperty(property, path, depth) {
  if (!property || depth > 8) return [];
  const children = [];
  const childCount = Math.min(Number(property.numProperties) || 0, 256);
  for (let index = 1; index <= childCount; index += 1) {
    let child = null;
    try { child = property.property(index); } catch (_) {}
    if (!child) continue;
    const nextPath = path.concat([child.matchName || child.name || String(index)]);
    children.push.apply(children, captureNativeProperty(child, nextPath, depth + 1));
  }
  if (children.length) return children;

  const value = nativeSerializableValue((function () {
    try { return property.value; } catch (_) { return null; }
  }()));
  const descriptor = {
    matchName: property.matchName || "",
    name: property.name || property.matchName || "Parameter",
    displayName: property.name || property.matchName || "Parameter",
    path: path,
    propertyType: property.propertyType,
    propertyValueType: property.propertyValueType,
    unitsText: property.unitsText || "",
    value: value
  };
  try { if (property.hasMin) descriptor.minValue = property.minValue; } catch (_) {}
  try { if (property.hasMax) descriptor.maxValue = property.maxValue; } catch (_) {}
  try {
    if (property.propertyParameters && property.propertyParameters.length) {
      descriptor.options = property.propertyParameters.slice(0, 256);
      descriptor.valueText = property.valueText || "";
    }
  } catch (_) {}
  try {
    if (property.numKeys > 0) {
      descriptor.keyframes = captureScalarPropertyKeyframes(property);
    }
  } catch (_) {}
  try {
    if (typeof property.expression === "string" && property.expression.length > 0) {
      descriptor.expression = {
        source: property.expression,
        enabled: property.expressionEnabled === true
      };
    }
  } catch (_) {}
  return [descriptor];
}
function captureEffects(layer) {
  const group = layer.property("ADBE Effect Parade"), effects = [];
  if (!group) return effects;
  for (let i = 1; i <= Math.min(group.numProperties || 0, 128); i += 1) {
    const effect = group.property(i), parameters = [];
    if (!effect) continue;
    for (let p = 1; p <= Math.min(effect.numProperties || 0, 256); p += 1) {
      const property = effect.property(p);
      if (!property) continue;
      parameters.push.apply(parameters,
        captureNativeProperty(property, [property.matchName || property.name || String(p)], 0));
    }
    effects.push({
      matchName: effect.matchName || "",
      name: effect.name || effect.matchName || "Adobe Effect",
      displayName: effect.name || effect.matchName || "Adobe Effect",
      enabled: effect.enabled !== false,
      category: effect.category || "",
      properties: parameters,
      parameters: parameters
    });
  }
  return effects;
}
function captureInstalledEffects() {
  try {
    if (!Array.isArray(afterEffects.effects)) {
      return { supported: false, minimumVersion: "27.0", effects: [] };
    }
    return {
      supported: true,
      minimumVersion: "27.0",
      effects: afterEffects.effects.slice(0, 4096).map(function (effect) {
        return {
          displayName: String(effect.displayName || effect.matchName || "Effect"),
          matchName: String(effect.matchName || ""),
          category: String(effect.category || ""),
          version: String(effect.version || ""),
          hostApp: "aftereffects"
        };
      }).filter(function (effect) { return effect.matchName.length > 0; })
    };
  } catch (error) {
    return { supported: false, minimumVersion: "27.0", effects: [], error: String(error) };
  }
}
function applyNativeEffectToSelection(matchName) {
  const project = afterEffects.project;
  const composition = project && project.activeItem;
  if (!composition || !Array.isArray(composition.selectedLayers) ||
      composition.selectedLayers.length === 0) {
    throw new Error("Select one or more layers in the active composition first.");
  }
  if (!matchName || typeof matchName !== "string") {
    throw new Error("An installed effect matchName is required.");
  }
  const applied = [], warnings = [];
  afterEffects.beginUndoGroup("DepthVibe · Apply Native Effect");
  try {
    const selected = composition.selectedLayers.slice();
    for (let index = 0; index < selected.length; index += 1) {
      const layer = selected[index];
      try {
        let parade = layer.property("ADBE Effect Parade");
        if (!parade || !parade.canAddProperty(matchName)) {
          warnings.push(layer.name + ": effect is unavailable: " + matchName);
          continue;
        }
        const effect = parade.addProperty(matchName);
        applied.push({ layerId: layer.id, layerName: layer.name, matchName: effect.matchName || matchName });
      } catch (error) {
        warnings.push(layer.name + ": " + String(error));
      }
    }
  } finally {
    afterEffects.endUndoGroup();
  }
  return { applied: applied, warnings: warnings, snapshot: captureActiveComposition() };
}
function nativePropertyForDescriptor(group, descriptor) {
  if (!group || !descriptor) return null;
  const path = Array.isArray(descriptor.path) && descriptor.path.length
    ? descriptor.path
    : [descriptor.matchName || descriptor.name || ""];
  let current = group;
  for (let index = 0; index < path.length; index += 1) {
    const part = String(path[index] || "");
    if (!part) continue;
    let next = null;
    try { next = current.property(part); } catch (_) {}
    if (!next) {
      const count = Math.min(Number(current.numProperties) || 0, 512);
      for (let child = 1; child <= count; child += 1) {
        let candidate = null;
        try { candidate = current.property(child); } catch (_) {}
        if (candidate && (candidate.matchName === part || candidate.name === part)) {
          next = candidate;
          break;
        }
      }
    }
    if (!next) return null;
    current = next;
  }
  return current;
}

function nativeKeyframeInterpolation(mode) {
  const types = afterEffects.KeyframeInterpolationType || {};
  const name = String(mode || "linear").toLowerCase();
  if (name === "hold") return types.HOLD;
  if (name === "bezier" || name === "cubicbezier" || name === "easein" ||
      name === "easeout" || name === "easeinout") return types.BEZIER;
  return types.LINEAR;
}

function nativeKeyframeEase(items) {
  if (!Array.isArray(items) || !items.length || typeof KeyframeEase !== "function") return null;
  const result = [];
  for (let index = 0; index < items.length; index += 1) {
    const speed = Number(items[index] && items[index].speed);
    const influence = Number(items[index] && items[index].influence);
    if (!Number.isFinite(speed) || !Number.isFinite(influence)) return null;
    result.push(new KeyframeEase(speed, Math.max(0.1, Math.min(100, influence))));
  }
  return result;
}

function applyNativeKeyframeMetadata(property, hostKeyIndex, key, dimensions) {
  if (!property || !key || hostKeyIndex < 1) return;
  const inMode = nativeKeyframeInterpolation(key.inInterpolation || key.interpolation);
  const outMode = nativeKeyframeInterpolation(key.outInterpolation || key.interpolation);
  try {
    if (inMode !== undefined && outMode !== undefined &&
        typeof property.setInterpolationTypeAtKey === "function") {
      property.setInterpolationTypeAtKey(hostKeyIndex, inMode, outMode);
    }
  } catch (_) {}
  try {
    const incoming = nativeKeyframeEase(key.inTemporalEase);
    const outgoing = nativeKeyframeEase(key.outTemporalEase);
    if (incoming && outgoing && typeof property.setTemporalEaseAtKey === "function") {
      property.setTemporalEaseAtKey(hostKeyIndex, incoming, outgoing);
    }
  } catch (_) {}
  try {
    if (typeof key.temporalAutoBezier === "boolean" &&
        typeof property.setTemporalAutoBezierAtKey === "function") {
      property.setTemporalAutoBezierAtKey(hostKeyIndex, key.temporalAutoBezier);
    }
  } catch (_) {}
  try {
    if (typeof key.temporalContinuous === "boolean" &&
        typeof property.setTemporalContinuousAtKey === "function") {
      property.setTemporalContinuousAtKey(hostKeyIndex, key.temporalContinuous);
    }
  } catch (_) {}
  try {
    if (typeof key.spatialAutoBezier === "boolean" &&
        typeof property.setSpatialAutoBezierAtKey === "function") {
      property.setSpatialAutoBezierAtKey(hostKeyIndex, key.spatialAutoBezier);
    }
  } catch (_) {}
  try {
    if (typeof key.spatialContinuous === "boolean" &&
        typeof property.setSpatialContinuousAtKey === "function") {
      property.setSpatialContinuousAtKey(hostKeyIndex, key.spatialContinuous);
    }
  } catch (_) {}
  try {
    const incoming = key.inSpatialTangent, outgoing = key.outSpatialTangent;
    if (dimensions > 1 && Array.isArray(incoming) && Array.isArray(outgoing) &&
        incoming.length === dimensions && outgoing.length === dimensions &&
        typeof property.setSpatialTangentsAtKey === "function") {
      property.setSpatialTangentsAtKey(hostKeyIndex, incoming, outgoing);
    }
  } catch (_) {}
  try {
    if (typeof key.roving === "boolean" && typeof property.setRovingAtKey === "function") {
      property.setRovingAtKey(hostKeyIndex, key.roving);
    }
  } catch (_) {}
}

function applyNativeParameters(group, parameters, warnings, stats) {
  if (!group || !Array.isArray(parameters)) return;
  for (let index = 0; index < parameters.length; index += 1) {
    const descriptor = parameters[index];
    if (!descriptor || typeof descriptor !== "object") continue;
    const property = nativePropertyForDescriptor(group, descriptor);
    if (!property) {
      warnings.push("Native parameter unavailable: " +
        String(descriptor.displayName || descriptor.name || descriptor.matchName || index));
      continue;
    }
    if (Array.isArray(descriptor.parameters)) {
      applyNativeParameters(property, descriptor.parameters, warnings, stats);
      continue;
    }
    const keyframes = Array.isArray(descriptor.keyframes) ? descriptor.keyframes : [];
    try {
      if (keyframes.length) {
        for (let keyIndex = 0; keyIndex < Math.min(keyframes.length, 10000); keyIndex += 1) {
          const key = keyframes[keyIndex];
          const time = Number(key.timeMs) / 1000;
          const value = key.value;
          const scalar = typeof value === "number" && Number.isFinite(value);
          const vector = Array.isArray(value) && value.length > 0 &&
            value.every((part) => typeof part === "number" && Number.isFinite(part));
          if (!Number.isFinite(time) || (!scalar && !vector)) continue;
          property.setValueAtTime(time, value);
          const hostKeyIndex = property.nearestKeyIndex(time);
          applyNativeKeyframeMetadata(
            property,
            hostKeyIndex,
            key,
            Array.isArray(value) ? value.length : 1
          );
          if (stats) stats.keyframes += 1;
        }
        continue;
      }
      const value = descriptor.value;
      if (value === null || value === undefined) continue;
      if (typeof value === "number" && !Number.isFinite(value)) continue;
      if (Array.isArray(value) &&
          !value.every((part) => typeof part === "number" && Number.isFinite(part))) continue;
      property.setValue(value);
      if (stats) stats.parameters += 1;
    } catch (error) {
      warnings.push("Native parameter " +
        String(descriptor.displayName || descriptor.name || descriptor.matchName) +
        " skipped: " + String(error));
    }
  }
}

function syncNativeEffectsToSelection(documentData) {
  const project = afterEffects.project;
  const composition = project && project.activeItem;
  if (!composition || !Array.isArray(composition.selectedLayers) ||
      composition.selectedLayers.length === 0) {
    throw new Error("Select the target After Effects layer(s) first.");
  }
  const documentLayers = documentData && Array.isArray(documentData.layers)
    ? documentData.layers : [];
  if (!documentLayers.length) throw new Error("DepthVibe has no composition layers to synchronize.");
  const selected = composition.selectedLayers.slice();
  const applied = [], warnings = [];
  afterEffects.beginUndoGroup("DepthVibe · Sync Native Effect Parameters");
  try {
    for (let layerIndex = 0; layerIndex < selected.length; layerIndex += 1) {
      const hostLayer = selected[layerIndex];
      const sourceLayer = documentLayers.find((item) =>
        String(item.externalSourceId || "") === String(hostLayer.id) &&
        (item.externalHostApp === "aftereffects-beta" || item.externalHostApp === "aftereffects"));
      if (!sourceLayer) {
        warnings.push(hostLayer.name + ": no matching DepthVibe source layer ID. Capture/import this composition again first.");
        continue;
      }
      let parade = null;
      try { parade = hostLayer.property("ADBE Effect Parade"); } catch (_) {}
      if (!parade) {
        warnings.push(hostLayer.name + ": the layer has no Effect Parade.");
        continue;
      }
      const effects = Array.isArray(sourceLayer.effects) ? sourceLayer.effects : [];
      for (let effectIndex = 0; effectIndex < effects.length; effectIndex += 1) {
        const instance = effects[effectIndex];
        const descriptor = instance && instance.nativeDescriptor || {};
        if (descriptor.hostApp !== "aftereffects-beta" &&
            descriptor.hostApp !== "aftereffects") continue;
        const matchName = String(descriptor.matchName || "");
        if (!matchName) {
          warnings.push(hostLayer.name + ": a native effect has no matchName.");
          continue;
        }
        try {
          let nativeEffect = null;
          const count = Math.min(Number(parade.numProperties) || 0, 256);
          for (let existingIndex = 1; existingIndex <= count; existingIndex += 1) {
            let candidate = null;
            try { candidate = parade.property(existingIndex); } catch (_) {}
            if (candidate && candidate.matchName === matchName) {
              nativeEffect = candidate;
              break;
            }
          }
          let created = false;
          if (!nativeEffect) {
            if (!parade.canAddProperty(matchName)) {
              warnings.push(hostLayer.name + ": effect is not installed: " + matchName);
              continue;
            }
            nativeEffect = parade.addProperty(matchName);
            created = true;
          }
          try { nativeEffect.enabled = instance.enabled !== false; } catch (_) {}
          const stats = {parameters: 0, keyframes: 0};
          applyNativeParameters(nativeEffect,
            Array.isArray(descriptor.parameters) ? descriptor.parameters : [],
            warnings, stats);
          applied.push({
            layerId: hostLayer.id,
            layerName: hostLayer.name,
            matchName: matchName,
            created: created,
            parameterCount: stats.parameters,
            keyframeCount: stats.keyframes
          });
        } catch (error) {
          warnings.push(hostLayer.name + ": " + matchName + " · " + String(error));
        }
      }
    }
  } finally {
    afterEffects.endUndoGroup();
  }
  return { applied: applied, warnings: warnings, snapshot: captureActiveComposition() };
}

function applyFfxPreset(path) {
  const project = afterEffects.project;
  const composition = project && project.activeItem;
  if (!composition || !Array.isArray(composition.selectedLayers) ||
      composition.selectedLayers.length === 0) {
    throw new Error("Select one or more target layers in the active composition first.");
  }
  if (!path || typeof path !== "string") throw new Error("Choose a valid .ffx preset file.");
  const target = composition.selectedLayers[0];
  if (!target || typeof target.applyPreset !== "function") {
    throw new Error("Layer.applyPreset is unavailable. After Effects 27.0 or later is required.");
  }
  const applied = target.applyPreset(path);
  if (applied === false) {
    throw new Error("After Effects did not apply the selected .ffx preset. Check the preset file and selected layers.");
  }
  return {
    applied: true,
    targetLayerCount: composition.selectedLayers.length,
    snapshot: captureActiveComposition()
  };
}
function saveFfxPreset(path) {
  const project = afterEffects.project;
  const composition = project && project.activeItem;
  if (!composition || !Array.isArray(composition.selectedLayers) ||
      composition.selectedLayers.length === 0) {
    throw new Error("Select a layer and the properties you want to include in the preset.");
  }
  if (!path || typeof path !== "string") throw new Error("Choose an output .ffx file path.");
  const saved = composition.selectedLayers[0].savePreset(path);
  if (!saved) throw new Error("No selected properties were saved. Select effect/animation properties in the Timeline panel.");
  return { saved: true, path: path };
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
      installedEffects: captureInstalledEffects(),
      transferScope: "metadata-only; footage files, plugin binaries and rendered frames are not copied"
    }
  };
}

module.exports = {
  captureActiveComposition,
  captureInstalledEffects,
  applyNativeEffectToSelection,
  syncNativeEffectsToSelection,
  applyFfxPreset,
  saveFfxPreset
};
