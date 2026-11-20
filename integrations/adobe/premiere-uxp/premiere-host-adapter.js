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

async function captureEffects(trackItem) {
  const chain = await optional(() => trackItem.getComponentChain(), null);
  if (!chain) return [];
  const count = await optional(() => chain.getComponentCount(), 0);
  const effects = [];
  for (let index = 0; index < Math.min(Number(count) || 0, 128); index += 1) {
    const component = await optional(() => chain.getComponentAtIndex(index), null);
    if (!component) continue;
    const matchName = await optional(() => component.getMatchName(), "");
    const name = await optional(() => component.getDisplayName(), matchName || "Premiere Effect");
    const paramCount = await optional(() => component.getParamCount(), 0);
    const properties = [];
    for (let p = 0; p < Math.min(Number(paramCount) || 0, 128); p += 1) {
      const param = await optional(() => component.getParam(p), null);
      if (!param) continue;
      const paramName = await optional(() => param.getName(), "Parameter " + p);
      const value = await optional(() => param.getValue(), null);
      if (typeof value === "number" || typeof value === "string" || typeof value === "boolean" ||
          (Array.isArray(value) && value.every((item) => typeof item === "number"))) {
        properties.push({ name: String(paramName), value: value });
      }
    }
    effects.push({ matchName: String(matchName || ""), name: String(name || "Premiere Effect"), properties: properties });
  }
  return effects;
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
    const effects = await captureEffects(item);
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

  const transitionFactory = premiere.TransitionFactory;
  const installedVideoTransitions = await optional(
    () => transitionFactory.getVideoTransitionMatchNames(),
    []
  );
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
      warnings: trackWarnings,
      transferScope: "metadata-only; media files and native effects are not copied"
    }
  };
}

module.exports = { capturePremiereSequence };
