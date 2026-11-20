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
        clips: await captureTrackItems(track, "video")
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
      warnings: trackWarnings,
      transferScope: "metadata-only; media files and native effects are not copied"
    }
  };
}

module.exports = { capturePremiereSequence };
