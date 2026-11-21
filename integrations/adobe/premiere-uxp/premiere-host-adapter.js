const premiere = require("premierepro");
const { host } = require("uxp");

function secondsOf(value) {
  if (value && typeof value.seconds === "number") return value.seconds;
  return null;
}

async function optional(call, fallback) {
  try {
    return await call();
  } catch (_) {
    return fallback === undefined ? null : fallback;
  }
}

function safeRead(call, fallback) {
  try {
    const value = call();
    return value === undefined || value === null ? fallback : value;
  } catch (_) {
    return fallback;
  }
}
function isMogrtText(value) {
  const Constructor = premiere.MogrtText;
  if (typeof Constructor === "function") {
    try { if (value instanceof Constructor) return true; } catch (_) {}
  }
  return !!value && typeof value.getText === "function" &&
    typeof value.isUniformStyling === "function";
}
function isMogrtComment(value) {
  const Constructor = premiere.MogrtComment;
  if (typeof Constructor === "function") {
    try { if (value instanceof Constructor) return true; } catch (_) {}
  }
  return !!value && typeof value.getText === "function" &&
    typeof value.isUniformStyling !== "function";
}
function mogrtTextDescriptor(value) {
  const result = {
    kind: "mogrtText",
    text: safeRead(() => value.getText(), ""),
    uniformStyling: safeRead(() => value.isUniformStyling(), false),
    fontNameEditable: safeRead(() => value.isFontNameEditable(), false),
    fontSizeEditable: safeRead(() => value.isFontSizeEditable(), false),
    fauxStylesEditable: safeRead(() => value.isFauxStylesEditable(), false)
  };
  if (result.uniformStyling) {
    const optionalFields = [
      ["fontName", "getFontName"], ["fontSize", "getFontSize"],
      ["allCaps", "getAllCaps"], ["fauxBold", "getFauxBold"],
      ["fauxItalic", "getFauxItalic"], ["smallCaps", "getSmallCaps"]
    ];
    for (const entry of optionalFields) {
      const fieldValue = safeRead(() => value[entry[1]](), undefined);
      if (fieldValue !== undefined) result[entry[0]] = fieldValue;
    }
  }
  return result;
}
function nativeParameterValue(value) {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" || typeof value === "boolean") return value;
  if (Array.isArray(value) && value.length <= 16 &&
      value.every((item) => typeof item === "number" && Number.isFinite(item))) return value.slice();
  if (isMogrtText(value)) return mogrtTextDescriptor(value);
  if (isMogrtComment(value)) {
    return {kind: "mogrtComment", text: safeRead(() => value.getText(), ""), readOnly: true};
  }
  if (value && typeof value === "object") {
    if (typeof value.x === "number" && typeof value.y === "number") {
      return {kind: "point", x: value.x, y: value.y};
    }
    if (typeof value.red === "number" && typeof value.green === "number" &&
        typeof value.blue === "number") {
      return {kind: "color", red: value.red, green: value.green, blue: value.blue,
        alpha: typeof value.alpha === "number" ? value.alpha : 1};
    }
    if (typeof value.text === "string") return value.text;
  }
  return null;
}
function unwrapPremiereValue(value) {
  let current = value;
  for (let depth = 0; depth < 3; depth += 1) {
    if (!current || typeof current !== "object" ||
        !Object.prototype.hasOwnProperty.call(current, "value")) break;
    current = current.value;
  }
  return current;
}
function tickTime(seconds) {
  const factory = premiere.TickTime;
  if (!factory || typeof factory.createWithSeconds !== "function") return null;
  return factory.createWithSeconds(Number.isFinite(seconds) ? seconds : 0);
}
function interpolationDescriptor(mode) {
  const modes = premiere.Constants && premiere.Constants.InterpolationMode
    ? premiere.Constants.InterpolationMode : {};
  for (const name of Object.keys(modes)) {
    if (modes[name] === mode) return {name: name.toLowerCase(), value: mode};
  }
  return {name: "unknown", value: typeof mode === "number" ? mode : null};
}
function valueTypeOf(value) {
  if (value && typeof value === "object" && typeof value.kind === "string") return value.kind;
  if (Array.isArray(value)) return "vector";
  if (value === null || value === undefined) return "unknown";
  return typeof value;
}
async function readParameterValue(param, timeSeconds, startValue) {
  const time = tickTime(timeSeconds);
  if (time) {
    const sampled = await optional(() => param.getValueAtTime(time), null);
    if (sampled && Object.prototype.hasOwnProperty.call(sampled, "value")) {
      const normalized = nativeParameterValue(unwrapPremiereValue(sampled.value));
      if (normalized !== null) return normalized;
    }
    const key = await optional(() => param.getKeyframePtr(time), null);
    if (key) {
      const normalized = nativeParameterValue(unwrapPremiereValue(key.value));
      if (normalized !== null) return normalized;
    }
  }
  const initial = startValue === undefined
    ? await optional(() => param.getStartValue(), null) : startValue;
  return nativeParameterValue(unwrapPremiereValue(initial));
}
async function componentIsTimeVarying(param) {
  if (typeof param.isTimeVarying === "function") {
    return await optional(() => param.isTimeVarying(), false);
  }
  return await optional(async () => param.isTimeVarying, false);
}
async function captureComponentParameters(component, timeSeconds, componentMatchName) {
  const paramCount = await optional(() => component.getParamCount(), 0);
  const parameters = [];
  for (let index = 0; index < Math.min(Number(paramCount) || 0, 256); index += 1) {
    const param = await optional(() => component.getParam(index), null);
    if (!param) continue;
    const displayName = await optional(async () => param.displayName, "Parameter " + (index + 1));
    const [startValue, supportsKeyframes, isTimeVarying] = await Promise.all([
      optional(() => param.getStartValue(), null),
      optional(() => param.areKeyframesSupported(), false),
      componentIsTimeVarying(param)
    ]);
    const value = await readParameterValue(param, timeSeconds, startValue);
    const keyframes = [];
    if (supportsKeyframes) {
      const times = await optional(() => param.getKeyframeListAsTickTimes(), []);
      for (const time of (Array.isArray(times) ? times : []).slice(0, 2048)) {
        if (!time || typeof time.seconds !== "number") continue;
        const keyValue = await readParameterValue(param, time.seconds, startValue);
        if (keyValue !== null) {
          const key = await optional(() => param.getKeyframePtr(time), null);
          const rawMode = key ? await optional(() => key.getTemporalInterpolationMode(), null) : null;
          const interpolation = interpolationDescriptor(rawMode);
          keyframes.push({
            timeSeconds: time.seconds,
            value: keyValue,
            interpolationMode: interpolation.value,
            interpolation: interpolation.name
          });
        }
      }
    }
    if (value !== null || keyframes.length) {
      const parameterName = String(displayName || ("Parameter " + (index + 1)));
      parameters.push({
        index: index,
        matchName: String(index),
        parameterId: String(componentMatchName || "component") + "#" + index + ":" + parameterName,
        componentMatchName: String(componentMatchName || ""),
        path: [String(componentMatchName || ""), String(index)],
        name: parameterName,
        displayName: parameterName,
        value: value,
        valueType: valueTypeOf(value),
        isMogrtText: isMogrtText(startValue),
        isMogrtComment: isMogrtComment(startValue),
        keyframesSupported: supportsKeyframes === true,
        isTimeVarying: isTimeVarying === true,
        keyframes: keyframes
      });
    }
  }
  return parameters;
}
async function captureEffects(async function captureEffects(trackItem, startSeconds, mediaType) {
  const chain = await optional(() => trackItem.getComponentChain(), null);
  if (!chain) return [];
  const count = await optional(() => chain.getComponentCount(), 0);
  const effects = [];
  for (let index = 0; index < Math.min(Number(count) || 0, 128); index += 1) {
    const component = await optional(() => chain.getComponentAtIndex(index), null);
    if (!component) continue;
    const matchName = await optional(() => component.getMatchName(), "");
    const name = await optional(() => component.getDisplayName(), matchName || "Premiere Effect");
    const isMotionGraphicsTemplate = String(matchName) === "AE.ADBE Capsule";
    const parameters = await captureComponentParameters(
      component, Number.isFinite(startSeconds) ? startSeconds : 0, matchName
    );
    effects.push({
      matchName: String(matchName || ""),
      name: String(name || "Premiere Effect"),
      displayName: String(name || "Premiere Effect"),
      enabled: true,
      hostApp: "premierepro",
      mediaType: mediaType || "video",
      isMotionGraphicsTemplate: isMotionGraphicsTemplate,
      parameterSchemaVersion: 2,
      parameterTree: parameters,
      properties: parameters,
      parameters: parameters
    });
  }
  return effects;
}
async function captureInstalledVideoEffects() {
  const factory = premiere.VideoFilterFactory;
  if (!factory ||
      typeof factory.getMatchNames !== "function" ||
      typeof factory.getDisplayNames !== "function") {
    return { supported: false, minimumVersion: "25.6", effects: [] };
  }
  const [matchNames, displayNames] = await Promise.all([
    optional(() => factory.getMatchNames(), []),
    optional(() => factory.getDisplayNames(), [])
  ]);
  const effects = [];
  const matches = Array.isArray(matchNames) ? matchNames : [];
  const labels = Array.isArray(displayNames) ? displayNames : [];
  for (let index = 0; index < Math.min(matches.length, 8192); index += 1) {
    if (typeof matches[index] !== "string" || !matches[index]) continue;
    effects.push({
      matchName: matches[index],
      displayName: typeof labels[index] === "string" ? labels[index] : matches[index],
      category: "",
      version: "",
      hostApp: "premierepro"
    });
  }
  return { supported: true, minimumVersion: "25.6", effects: effects };
}
async function captureInstalledAudioEffects() {
  const factory = premiere.AudioFilterFactory;
  if (!factory || typeof factory.getDisplayNames !== "function") {
    return { supported: false, minimumVersion: "25.6", effects: [] };
  }
  const labels = await optional(() => factory.getDisplayNames(), []);
  const effects = (Array.isArray(labels) ? labels : [])
    .filter((name) => typeof name === "string" && name.trim())
    .slice(0, 4096)
    .map((displayName) => ({
      matchName: displayName,
      displayName: displayName,
      category: "Audio",
      version: "",
      mediaType: "audio",
      hostApp: "premierepro"
    }));
  return { supported: true, minimumVersion: "25.6", effects: effects };
}
async function findTrackItem(sequence, clipId, mediaType) {
  for (const type of (mediaType === "audio" ? ["audio"] : mediaType === "video" ? ["video"] : ["video", "audio"])) {
    const count = type === "video"
      ? await sequence.getVideoTrackCount()
      : await sequence.getAudioTrackCount();
    for (let index = 0; index < count; index += 1) {
      const track = type === "video"
        ? await sequence.getVideoTrack(index)
        : await sequence.getAudioTrack(index);
      const items = await optional(
        () => track.getTrackItems(premiere.Constants.TrackItemType.CLIP, false), []
      );
      for (const item of items || []) {
        const id = typeof item.getId === "function"
          ? await optional(() => item.getId(), null) : null;
        if (String(id) === String(clipId)) return item;
      }
    }
  }
  return null;
}
function materializeNativeParameterValue(rawValue) {
  if (rawValue === null || rawValue === undefined) return null;
  if (typeof rawValue !== "object") return nativeParameterValue(rawValue);
  if (rawValue.kind === "mogrtComment" || rawValue.readOnly === true) {
    throw new Error("MOGRT comment parameters are informational/read-only in Premiere UXP.");
  }
  if (rawValue.kind === "mogrtText") {
    if (typeof premiere.MogrtText !== "function") {
      throw new Error("Editable MogrtText requires Premiere Pro 27.0 or later.");
    }
    const text = new premiere.MogrtText();
    if (typeof text.setText === "function" && typeof rawValue.text === "string") text.setText(rawValue.text);
    if (rawValue.fauxStylesEditable === true) {
      const setters = [["allCaps","setAllCaps"],["fauxBold","setFauxBold"],
        ["fauxItalic","setFauxItalic"],["smallCaps","setSmallCaps"]];
      for (const entry of setters) {
        if (typeof rawValue[entry[0]] === "boolean" && typeof text[entry[1]] === "function") {
          text[entry[1]](rawValue[entry[0]]);
        }
      }
    }
    if (rawValue.fontNameEditable === true && typeof rawValue.fontName === "string" &&
        typeof text.setFontName === "function") text.setFontName(rawValue.fontName);
    if (rawValue.fontSizeEditable === true && Number.isFinite(Number(rawValue.fontSize)) &&
        typeof text.setFontSize === "function") text.setFontSize(Number(rawValue.fontSize));
    return text;
  }
  if (rawValue.kind === "color" ||
      (typeof rawValue.red === "number" && typeof rawValue.green === "number" &&
       typeof rawValue.blue === "number")) {
    if (typeof premiere.Color !== "function") throw new Error("Premiere Color constructor is unavailable.");
    return new premiere.Color(Number(rawValue.red), Number(rawValue.green), Number(rawValue.blue),
      Number.isFinite(Number(rawValue.alpha)) ? Number(rawValue.alpha) : 1);
  }
  if (rawValue.kind === "point" ||
      (typeof rawValue.x === "number" && typeof rawValue.y === "number")) {
    if (typeof premiere.PointF !== "function") throw new Error("Premiere PointF constructor is unavailable.");
    return new premiere.PointF(Number(rawValue.x), Number(rawValue.y));
  }
  return nativeParameterValue(rawValue);
}
async function resolveComponentParameterIndex(component, descriptor, paramCount, skipped) {
  const rawIndex = Number(descriptor.index !== undefined ? descriptor.index : descriptor.matchName);
  const expectedName = String(descriptor.displayName || descriptor.name || "");
  if (Number.isInteger(rawIndex) && rawIndex >= 0 && rawIndex < Number(paramCount)) {
    const candidate = await optional(() => component.getParam(rawIndex), null);
    const candidateName = candidate ? String(await optional(async () => candidate.displayName, "")) : "";
    if (!expectedName || candidateName === expectedName) return rawIndex;
  }
  if (expectedName) {
    const matches = [];
    for (let index = 0; index < Math.min(Number(paramCount) || 0, 256); index += 1) {
      const candidate = await optional(() => component.getParam(index), null);
      const candidateName = candidate ? String(await optional(async () => candidate.displayName, "")) : "";
      if (candidateName === expectedName) matches.push(index);
    }
    if (matches.length === 1) return matches[0];
    if (matches.length > 1) {
      skipped.push(expectedName + ": duplicate display names in the current effect schema; parameter was not guessed.");
      return null;
    }
  }
  skipped.push(expectedName || "Parameter " + rawIndex + ": parameter schema no longer matches the installed effect.");
  return null;
}
function interpolationModeForFrame(frame) {
  if (frame && typeof frame.interpolationMode === "number") return frame.interpolationMode;
  const modes = premiere.Constants && premiere.Constants.InterpolationMode
    ? premiere.Constants.InterpolationMode : {};
  const name = String(frame && frame.interpolation || "").toUpperCase();
  return name && typeof modes[name] === "number" ? modes[name] : null;
}
async function appendNativeParameterActions(param, descriptor, actions, skipped) {
  const label = String(descriptor.displayName || descriptor.name || "Parameter");
  const frames = Array.isArray(descriptor.keyframes) ? descriptor.keyframes : [];
  let keyframesApplied = 0;
  let parametersApplied = 0;
  if (frames.length) {
    const supports = await optional(() => param.areKeyframesSupported(), false);
    if (!supports || typeof param.createSetTimeVaryingAction !== "function" ||
        typeof param.createAddKeyframeAction !== "function") {
      skipped.push(label + ": host parameter cannot be animated");
      return {keyframesApplied: 0, parametersApplied: 0};
    }
    try {
      const enableAction = param.createSetTimeVaryingAction(true);
      if (enableAction) actions.push(enableAction);
    } catch (error) {
      skipped.push(label + ": could not enable keyframes: " + String(error));
      return {keyframesApplied: 0, parametersApplied: 0};
    }
    for (const frame of frames.slice(0, 2048)) {
      const time = tickTime(Number(frame.timeSeconds));
      let value = null;
      try { value = materializeNativeParameterValue(frame.value); }
      catch (error) {
        skipped.push(label + " at " + frame.timeSeconds + "s: " + String(error));
        continue;
      }
      if (!time || value === null) {
        skipped.push(label + ": invalid keyframe time/value");
        continue;
      }
      try {
        if (typeof param.createRemoveKeyframeAction === "function") {
          const removeAction = param.createRemoveKeyframeAction(time, true);
          if (removeAction) actions.push(removeAction);
        }
        const keyframe = param.createKeyframe(value);
        keyframe.position = time;
        const addAction = param.createAddKeyframeAction(keyframe);
        if (addAction) {
          actions.push(addAction);
          keyframesApplied += 1;
        }
        const mode = interpolationModeForFrame(frame);
        if (mode !== null && typeof param.createSetInterpolationAtKeyframeAction === "function") {
          const interpolationAction = param.createSetInterpolationAtKeyframeAction(time, mode, true);
          if (interpolationAction) actions.push(interpolationAction);
        }
      } catch (error) {
        skipped.push(label + " at " + frame.timeSeconds + "s: " + String(error));
      }
    }
    return {keyframesApplied: keyframesApplied, parametersApplied: 0};
  }
  const isAnimated = await componentIsTimeVarying(param);
  if (isAnimated) {
    skipped.push(label + ": parameter is animated in Premiere but no keyframes were returned");
    return {keyframesApplied: 0, parametersApplied: 0};
  }
  let value = null;
  try { value = materializeNativeParameterValue(descriptor.value); }
  catch (error) {
    skipped.push(label + ": " + String(error));
    return {keyframesApplied: 0, parametersApplied: 0};
  }
  if (value === null) return {keyframesApplied: 0, parametersApplied: 0};
  try {
    const keyframe = param.createKeyframe(value);
    const action = param.createSetValueAction(keyframe, true);
    if (action) {
      actions.push(action);
      parametersApplied = 1;
    }
  } catch (error) {
    skipped.push(label + ": " + String(error));
  }
  return {keyframesApplied: 0, parametersApplied: parametersApplied};
}

async function applyNativeVideoEffect(clipId, matchName, parameters) {
  const project = await premiere.Project.getActiveProject();
  const sequence = project && await project.getActiveSequence();
  if (!project || !sequence) throw new Error("Open an active Premiere project and sequence.");
  if (!matchName) throw new Error("A video effect matchName is required.");
  const item = await findTrackItem(sequence, clipId);
  if (!item) throw new Error("The captured Premiere clip no longer exists. Capture the sequence again.");
  const factory = premiere.VideoFilterFactory;
  const chain = await item.getComponentChain();
  const initialCount = await optional(() => chain.getComponentCount(), 0);
  let component = null;
  for (let index = 0; index < Math.min(Number(initialCount) || 0, 256); index += 1) {
    const existing = await optional(() => chain.getComponentAtIndex(index), null);
    if (!existing) continue;
    const existingName = await optional(() => existing.getMatchName(), "");
    if (existingName === matchName) {
      component = existing;
      break;
    }
  }
  const isNewComponent = component === null;
  if (isNewComponent) component = await factory.createComponent(matchName);
  if (!component) throw new Error("Premiere could not create effect: " + matchName);

  const skippedParameters = [];
  const actions = [];
  let animationKeyframesApplied = 0;
  let parametersApplied = 0;
  const paramCount = await optional(() => component.getParamCount(), 0);
  for (const descriptor of (Array.isArray(parameters) ? parameters : [])) {
    const index = await resolveComponentParameterIndex(component, descriptor, paramCount, skippedParameters);
    if (index === null) continue;
    const param = await optional(() => component.getParam(index), null);
    if (!param) continue;
    const appliedCounts = await appendNativeParameterActions(param, descriptor, actions, skippedParameters);
    animationKeyframesApplied += appliedCounts.keyframesApplied;
    parametersApplied += appliedCounts.parametersApplied;
  }

  let success = false;
  project.lockedAccess(() => {
    success = project.executeTransaction((compoundAction) => {
      if (isNewComponent) {
        compoundAction.addAction(chain.createAppendComponentAction(component));
      }
      for (const action of actions) compoundAction.addAction(action);
    }, isNewComponent
      ? "DepthVibe · Add Native Video Effect"
      : "DepthVibe · Update Native Video Effect");
  });
  if (!success) throw new Error("Premiere did not accept the native effect transaction.");
  const snapshot = await capturePremiereSequence();
  const importedClip = snapshot.payload.videoTracks
    .concat(snapshot.payload.audioTracks)
    .flatMap((track) => track.clips || [])
    .find((clip) => String(clip.id) === String(clipId));
  return {
    matchName: matchName,
    appliedToClipId: String(clipId),
    parametersApplied: parametersApplied,
    animationKeyframesApplied: animationKeyframesApplied,
    actionCount: actions.length,
    createdNewComponent: isNewComponent,
    skippedParameters: skippedParameters,
    capturedEffect: importedClip && importedClip.effects
      ? importedClip.effects.find((effect) => effect.matchName === matchName) || null
      : null,
    snapshot: snapshot
  };
}

async function applyNativeAudioEffect(clipId, displayName, parameters) {
  const project = await premiere.Project.getActiveProject();
  const sequence = project && await project.getActiveSequence();
  if (!project || !sequence) throw new Error("Open an active Premiere project and sequence.");
  if (!displayName) throw new Error("An audio effect displayName is required.");
  const item = await findTrackItem(sequence, clipId, "audio");
  if (!item) throw new Error("The captured audio clip no longer exists. Capture the sequence again.");
  const factory = premiere.AudioFilterFactory;
  if (!factory || typeof factory.createComponentByDisplayName !== "function") {
    throw new Error("Premiere AudioFilterFactory requires Premiere Pro 25.6 or later.");
  }
  const chain = await item.getComponentChain();
  const initialCount = await optional(() => chain.getComponentCount(), 0);
  let component = null;
  for (let index = 0; index < Math.min(Number(initialCount) || 0, 256); index += 1) {
    const existing = await optional(() => chain.getComponentAtIndex(index), null);
    if (!existing) continue;
    const name = await optional(() => existing.getDisplayName(), "");
    if (name === displayName) {
      component = existing;
      break;
    }
  }
  const isNewComponent = component === null;
  if (isNewComponent) {
    component = await factory.createComponentByDisplayName(displayName, item);
  }
  if (!component) throw new Error("Premiere could not create audio effect: " + displayName);

  const skippedParameters = [];
  const actions = [];
  let animationKeyframesApplied = 0;
  let parametersApplied = 0;
  const paramCount = await optional(() => component.getParamCount(), 0);
  for (const descriptor of (Array.isArray(parameters) ? parameters : [])) {
    const index = await resolveComponentParameterIndex(component, descriptor, paramCount, skippedParameters);
    if (index === null) continue;
    const param = await optional(() => component.getParam(index), null);
    if (!param) continue;
    const appliedCounts = await appendNativeParameterActions(param, descriptor, actions, skippedParameters);
    animationKeyframesApplied += appliedCounts.keyframesApplied;
    parametersApplied += appliedCounts.parametersApplied;
  }

  let success = false;
  project.lockedAccess(() => {
    success = project.executeTransaction((compoundAction) => {
      if (isNewComponent) {
        compoundAction.addAction(chain.createAppendComponentAction(component));
      }
      for (const action of actions) compoundAction.addAction(action);
    }, isNewComponent
      ? "DepthVibe · Add Native Audio Effect"
      : "DepthVibe · Update Native Audio Effect");
  });
  if (!success) throw new Error("Premiere did not accept the native audio effect transaction.");
  const snapshot = await capturePremiereSequence();
  return {
    displayName: displayName,
    appliedToClipId: String(clipId),
    parametersApplied: parametersApplied,
    animationKeyframesApplied: animationKeyframesApplied,
    actionCount: actions.length,
    createdNewComponent: isNewComponent,
    skippedParameters: skippedParameters,
    snapshot: snapshot
  };
}

async function insertMotionBroMogrt(path) {
  const project = await premiere.Project.getActiveProject();
  const sequence = project && await project.getActiveSequence();
  if (!project || !sequence) {
    throw new Error("Open a Premiere project and active sequence first.");
  }
  if (!path || typeof path !== "string") {
    throw new Error("Select an imported Motion Bro .MOGRT asset.");
  }
  const sequenceEditor = premiere.SequenceEditor.getEditor(sequence);
  if (!sequenceEditor || typeof sequenceEditor.insertMogrtFromPath !== "function") {
    throw new Error("MOGRT insertion requires Premiere Pro 25.6 or later.");
  }
  const [position, videoCount, audioCount] = await Promise.all([
    sequence.getPlayerPosition(),
    sequence.getVideoTrackCount(),
    sequence.getAudioTrackCount()
  ]);
  const videoTrackIndex = Math.max(0, Number(videoCount) - 1);
  const audioTrackIndex = Math.max(0, Number(audioCount) - 1);
  const result = await sequenceEditor.insertMogrtFromPath(
    path, position, videoTrackIndex, audioTrackIndex
  );
  const insertedItems = Array.isArray(result) ? result : (result ? [result] : []);
  const insertedIds = [];
  for (const item of insertedItems) {
    if (item && typeof item.getId === "function") {
      const itemId = await optional(() => item.getId(), null);
      if (itemId !== null && itemId !== undefined) insertedIds.push(String(itemId));
    }
  }
  const snapshot = await capturePremiereSequence();
  const insertedClips = [];
  for (const track of (snapshot.payload.videoTracks || [])) {
    for (const clip of (track.clips || [])) {
      const idMatch = insertedIds.indexOf(String(clip.id)) >= 0;
      const timeMatch = typeof clip.startSeconds === "number" &&
        Math.abs(clip.startSeconds - Number(position.seconds || 0)) < 0.05;
      const mogrtMatch = (clip.effects || []).some((effect) =>
        effect.matchName === "AE.ADBE Capsule" || effect.isMotionGraphicsTemplate === true);
      if (idMatch || (timeMatch && mogrtMatch)) {
        clip.mogrtTemplate = {
          assetPath: path,
          fileName: String(path).split(/[\\/]/).pop(),
          insertedAtSeconds: Number(position.seconds || 0),
          isEditableTemplate: mogrtMatch
        };
        insertedClips.push({
          id: clip.id,
          name: clip.name,
          trackName: track.name,
          editableControlCount: (clip.effects || []).reduce((total, effect) =>
            total + (Array.isArray(effect.parameters) ? effect.parameters.length : 0), 0),
          textControlCount: (clip.effects || []).reduce((total, effect) =>
            total + (effect.parameters || []).filter((parameter) =>
              parameter.value && parameter.value.kind === "mogrtText").length, 0)
        });
      }
    }
  }
  snapshot.payload.insertedMotionGraphicsTemplates = [{
    assetPath: path,
    fileName: String(path).split(/[\\/]/).pop(),
    insertedAtSeconds: Number(position.seconds || 0),
    insertedTrackItemIds: insertedIds,
    matchedClips: insertedClips
  }];
  return {
    inserted: insertedItems.length > 0,
    insertionResult: result,
    insertedTrackItemIds: insertedIds,
    insertedClips: insertedClips,
    videoTrackIndex: videoTrackIndex,
    audioTrackIndex: audioTrackIndex,
    snapshot: snapshot
  };
}

async function captureTrackTransitions(track) {
  const transitionType = premiere.Constants && premiere.Constants.TrackItemType
    ? premiere.Constants.TrackItemType.TRANSITION : undefined;
  if (transitionType === undefined) return [];
  const items = await optional(
    async () => track.getTrackItems(transitionType, false),
    []
  );
  const transitions = [];
  for (let index = 0; index < Math.min(items.length || 0, 256); index += 1) {
    const item = items[index];
    const values = await Promise.all([
      optional(() => item.getName(), item.name || "Premiere Transition"),
      optional(() => item.getMatchName(), ""),
      optional(() => item.getStartTime()),
      optional(() => item.getDuration()),
      optional(() => item.getEndTime())
    ]);
    transitions.push({
      id: typeof item.getId === "function" ? await optional(() => item.getId()) : null,
      name: String(values[0] || "Premiere Transition"),
      matchName: String(values[1] || values[0] || ""),
      startSeconds: secondsOf(values[2]),
      durationSeconds: secondsOf(values[3]),
      endSeconds: secondsOf(values[4])
    });
  }
  return transitions;
}

async function captureTrackItems(track, trackType) {
  const trackItems = await optional(
    async () => track.getTrackItems(premiere.Constants.TrackItemType.CLIP, false),
    []
  );
  const clips = [];

  for (let index = 0; index < trackItems.length; index += 1) {
    const item = trackItems[index];
    const values = await Promise.all([
      optional(() => item.getName(), item.name || "Untitled clip"),
      optional(() => item.getStartTime()),
      optional(() => item.getEndTime()),
      optional(() => item.getDuration()),
      optional(() => item.getInPoint()),
      optional(() => item.getOutPoint()),
      optional(() => item.getSpeed(), 1),
      optional(() => item.getProjectItem())
    ]);
    const projectItem = values[7];
    const sourcePath = projectItem
      ? await optional(() => projectItem.getMediaFilePath(), null)
      : null;
    const startSeconds = secondsOf(values[1]);
    const effects = await captureEffects(item, startSeconds, trackType);
    clips.push({
      id: typeof item.getId === "function" ? await optional(() => item.getId()) : null,
      name: values[0],
      startSeconds: secondsOf(values[1]),
      endSeconds: secondsOf(values[2]),
      durationSeconds: secondsOf(values[3]),
      sourceInSeconds: secondsOf(values[4]),
      sourceOutSeconds: secondsOf(values[5]),
      speed: values[6],
      sourceName: projectItem && projectItem.name ? projectItem.name : null,
      sourcePath: typeof sourcePath === "string" ? sourcePath : null,
      effects: effects,
      sourceId: projectItem && typeof projectItem.getId === "function"
        ? await optional(() => projectItem.getId())
        : null,
      mediaType: trackType
    });
  }

  return clips;
}

async function capturePremiereSequence() {
  const project = await premiere.Project.getActiveProject();
  if (!project) {
    throw new Error("Open a Premiere Pro project before capturing its sequence.");
  }
  const sequence = await project.getActiveSequence();
  if (!sequence) {
    throw new Error("Select an active Premiere Pro sequence first.");
  }

  const [frameSize, timebase, endTime, videoCount, audioCount, sequenceItem] =
    await Promise.all([
      sequence.getFrameSize(),
      sequence.getTimebase(),
      sequence.getEndTime(),
      sequence.getVideoTrackCount(),
      sequence.getAudioTrackCount(),
      optional(() => sequence.getProjectItem())
    ]);

  const videoTracks = [];
  const audioTracks = [];
  const trackWarnings = [];

  for (let index = 0; index < videoCount; index += 1) {
    try {
      const track = await sequence.getVideoTrack(index);
      videoTracks.push({
        index: index,
        id: track.id,
        name: track.name,
        muted: false,
        clips: await captureTrackItems(track, "video"),
        transitions: await captureTrackTransitions(track)
      });
    } catch (error) {
      trackWarnings.push("Video track " + index + ": " + String(error));
    }
  }

  for (let index = 0; index < audioCount; index += 1) {
    try {
      const track = await sequence.getAudioTrack(index);
      const muted = await optional(() => track.isMuted(), false);
      audioTracks.push({
        index: index,
        id: track.id,
        name: track.name,
        muted: muted,
        clips: await captureTrackItems(track, "audio")
      });
    } catch (error) {
      trackWarnings.push("Audio track " + index + ": " + String(error));
    }
  }

  const [installedTransitionResult, installedEffectResult, installedAudioEffectResult] =
    await Promise.all([
      optional(async () => premiere.TransitionFactory.getVideoTransitionMatchNames(), []),
      captureInstalledVideoEffects(),
      captureInstalledAudioEffects()
    ]);
  const installedVideoTransitions = installedTransitionResult;
  const installedTransitionNames = Array.isArray(installedVideoTransitions)
    ? installedVideoTransitions.map((item) => typeof item === "string"
        ? item : (item && (item.matchName || item.name))
          ? String(item.matchName || item.name) : "").filter(Boolean)
    : [];
  const hostVersion = host && host.version ? host.version : "Unknown";
  return {
    schemaVersion: 1,
    hostApp: "premierepro",
    hostVersion: hostVersion,
    capturedAt: new Date().toISOString(),
    payload: {
      sourceType: "premiere-sequence-snapshot",
      project: {
        name: project.name || "",
        guid: project.guid && project.guid.toString
          ? project.guid.toString()
          : String(project.guid || "")
      },
      sequence: {
        name: sequence.name || "",
        guid: sequence.guid && sequence.guid.toString
          ? sequence.guid.toString()
          : String(sequence.guid || ""),
        projectItemName: sequenceItem && sequenceItem.name
          ? sequenceItem.name
          : null,
        width: frameSize && typeof frameSize.width === "number"
          ? frameSize.width
          : null,
        height: frameSize && typeof frameSize.height === "number"
          ? frameSize.height
          : null,
        timebase: timebase,
        durationSeconds: secondsOf(endTime),
        videoTrackCount: videoCount,
        audioTrackCount: audioCount
      },
      videoTracks: videoTracks,
      audioTracks: audioTracks,
      installedVideoTransitions: installedTransitionNames,
      installedVideoEffects: installedEffectResult.effects,
      installedVideoEffectsSupported: installedEffectResult.supported,
      installedVideoEffectsMinimumVersion: installedEffectResult.minimumVersion,
      installedAudioEffects: installedAudioEffectResult.effects,
      installedAudioEffectsSupported: installedAudioEffectResult.supported,
      installedAudioEffectsMinimumVersion: installedAudioEffectResult.minimumVersion,
      warnings: trackWarnings,
      transferScope: "metadata-only; media files and native effects are not copied"
    }
  };
}

module.exports = {
  capturePremiereSequence,
  captureInstalledVideoEffects,
  captureInstalledAudioEffects,
  applyNativeVideoEffect,
  applyNativeAudioEffect,
  insertMotionBroMogrt
};
