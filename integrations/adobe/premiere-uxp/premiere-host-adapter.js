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

function nativeParameterValue(value) {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" || typeof value === "boolean") return value;
  if (Array.isArray(value) && value.length <= 16 &&
      value.every((item) => typeof item === "number" && Number.isFinite(item))) return value.slice();
  if (value && typeof value === "object") {
    if (typeof value.x === "number" && typeof value.y === "number") return [value.x, value.y];
    if (typeof value.red === "number" && typeof value.green === "number" &&
        typeof value.blue === "number") {
      return {
        red: value.red, green: value.green, blue: value.blue,
        alpha: typeof value.alpha === "number" ? value.alpha : 1
      };
    }
    if (typeof value.text === "string") return value.text;
  }
  return null;
}
function tickTime(seconds) {
  const factory = premiere.TickTime;
  if (!factory || typeof factory.createWithSeconds !== "function") return null;
  return factory.createWithSeconds(Number.isFinite(seconds) ? seconds : 0);
}
async function readParameterValue(param, timeSeconds) {
  const time = tickTime(timeSeconds);
  if (time) {
    const sampled = await optional(() => param.getValueAtTime(time), null);
    if (sampled && Object.prototype.hasOwnProperty.call(sampled, "value")) {
      return nativeParameterValue(sampled.value);
    }
  }
  const initial = await optional(() => param.getStartValue(), null);
  if (initial && Object.prototype.hasOwnProperty.call(initial, "value")) {
    return nativeParameterValue(initial.value);
  }
  return null;
}
async function captureComponentParameters(component, timeSeconds) {
  const paramCount = await optional(() => component.getParamCount(), 0);
  const parameters = [];
  for (let index = 0; index < Math.min(Number(paramCount) || 0, 256); index += 1) {
    const param = await optional(() => component.getParam(index), null);
    if (!param) continue;
    const displayName = await optional(
      async () => param.displayName,
      "Parameter " + (index + 1)
    );
    const [value, supportsKeyframes, isTimeVarying] = await Promise.all([
      readParameterValue(param, timeSeconds),
      optional(() => param.areKeyframesSupported(), false),
      optional(async () => param.isTimeVarying, false)
    ]);
    const keyframes = [];
    if (supportsKeyframes) {
      const times = await optional(() => param.getKeyframeListAsTickTimes(), []);
      for (const time of (Array.isArray(times) ? times : []).slice(0, 2048)) {
        if (!time || typeof time.seconds !== "number") continue;
        const keyValue = await readParameterValue(param, time.seconds);
        if (keyValue !== null) {
          keyframes.push({ timeSeconds: time.seconds, value: keyValue });
        }
      }
    }
    if (value !== null || keyframes.length) {
      parameters.push({
        index: index,
        matchName: String(index),
        name: String(displayName || ("Parameter " + (index + 1))),
        displayName: String(displayName || ("Parameter " + (index + 1))),
        value: value,
        valueType: value === null ? "unknown" : Array.isArray(value) ? "vector" : typeof value,
        keyframesSupported: supportsKeyframes === true,
        isTimeVarying: isTimeVarying === true,
        keyframes: keyframes
      });
    }
  }
  return parameters;
}
async function captureEffects(trackItem, startSeconds) {
  const chain = await optional(() => trackItem.getComponentChain(), null);
  if (!chain) return [];
  const count = await optional(() => chain.getComponentCount(), 0);
  const effects = [];
  for (let index = 0; index < Math.min(Number(count) || 0, 128); index += 1) {
    const component = await optional(() => chain.getComponentAtIndex(index), null);
    if (!component) continue;
    const matchName = await optional(() => component.getMatchName(), "");
    const name = await optional(() => component.getDisplayName(), matchName || "Premiere Effect");
    const parameters = await captureComponentParameters(
      component, Number.isFinite(startSeconds) ? startSeconds : 0
    );
    effects.push({
      matchName: String(matchName || ""),
      name: String(name || "Premiere Effect"),
      displayName: String(name || "Premiere Effect"),
      enabled: true,
      hostApp: "premierepro",
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
async function findTrackItem(sequence, clipId) {
  for (const type of ["video", "audio"]) {
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
async function applyNativeVideoEffect(clipId, matchName, parameters) {
  const project = await premiere.Project.getActiveProject();
  const sequence = project && await project.getActiveSequence();
  if (!project || !sequence) throw new Error("Open an active Premiere project and sequence.");
  if (!matchName) throw new Error("A video effect matchName is required.");
  const item = await findTrackItem(sequence, clipId);
  if (!item) throw new Error("The captured Premiere clip no longer exists. Capture the sequence again.");
  const factory = premiere.VideoFilterFactory;
  const component = await factory.createComponent(matchName);
  if (!component) throw new Error("Premiere could not create effect: " + matchName);

  const skippedParameters = [];
  const actions = [];
  const paramCount = await optional(() => component.getParamCount(), 0);
  for (const descriptor of (Array.isArray(parameters) ? parameters : [])) {
    const index = Number(descriptor.index !== undefined ? descriptor.index : descriptor.matchName);
    if (!Number.isInteger(index) || index < 0 || index >= Number(paramCount)) continue;
    const value = nativeParameterValue(descriptor.value);
    if (value === null) continue;
    const param = await optional(() => component.getParam(index), null);
    if (!param) continue;
    const timeVarying = await optional(async () => param.isTimeVarying, false);
    if (timeVarying) {
      skippedParameters.push(String(descriptor.displayName || descriptor.name) + ": animated parameter kept at its host default");
      continue;
    }
    try {
      const keyframe = param.createKeyframe(value);
      const action = param.createSetValueAction(keyframe, true);
      if (action) actions.push(action);
    } catch (error) {
      skippedParameters.push(String(descriptor.displayName || descriptor.name) + ": " + String(error));
    }
  }

  const chain = await item.getComponentChain();
  let success = false;
  project.lockedAccess(() => {
    success = project.executeTransaction((compoundAction) => {
      compoundAction.addAction(chain.createAppendComponentAction(component));
      for (const action of actions) compoundAction.addAction(action);
    }, "DepthVibe · Add Native Video Effect");
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
    parametersApplied: actions.length,
    skippedParameters: skippedParameters,
    capturedEffect: importedClip && importedClip.effects
      ? importedClip.effects.find((effect) => effect.matchName === matchName) || null
      : null,
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
    const effects = await captureEffects(item, startSeconds);
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

  const [installedTransitionResult, installedEffectResult] = await Promise.all([
    optional(async () => premiere.TransitionFactory.getVideoTransitionMatchNames(), []),
    captureInstalledVideoEffects()
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
      warnings: trackWarnings,
      transferScope: "metadata-only; media files and native effects are not copied"
    }
  };
}

module.exports = { capturePremiereSequence, captureInstalledVideoEffects, applyNativeVideoEffect };
