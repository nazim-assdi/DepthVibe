const { entrypoints, storage } = require("uxp");
const {
  capturePremiereSequence,
  captureInstalledVideoEffects,
  applyNativeVideoEffect
} = require("./premiere-host-adapter");
const { host } = require("uxp");
const DEFAULT_BRIDGE = "http://127.0.0.1:47653";
let sessionToken = null;
let latestSnapshot = null;
let installedVideoEffects = [];

function bridgeBaseUrl() {
  const field = document.getElementById("bridgeUrl");
  const raw = field && field.value.trim() ? field.value.trim() : DEFAULT_BRIDGE;
  const parsed = new URL(raw);
  if (!["http:", "https:"].includes(parsed.protocol) ||
      parsed.hostname !== "127.0.0.1" ||
      parsed.port !== "47653" ||
      parsed.username || parsed.password ||
      (parsed.pathname !== "/" && parsed.pathname !== "")) {
    throw new Error("Use only http(s)://127.0.0.1:47653 for the local bridge.");
  }
  return parsed.origin;
}

function setConnected(connected) {
  ["capture", "importSnapshot", "exportXml", "refresh", "effects", "send",
   "refreshHostEffects", "syncNativeSettings"].forEach(function (id) {
    const element = document.getElementById(id);
    if (element) element.disabled = !connected;
  });
}
function setStatus(message) {
  const status = document.getElementById("status");
  if (status) status.textContent = message;
}
function showResult(value) {
  const output = document.getElementById("result");
  if (output) output.textContent =
    typeof value === "string" ? value : JSON.stringify(value, null, 2);
}
async function request(path, options) {
  const settings = options || {};
  settings.headers = Object.assign({}, settings.headers || {});
  settings.headers["Content-Type"] = "application/json";
  if (sessionToken) settings.headers.Authorization = "Bearer " + sessionToken;
  const response = await fetch(bridgeBaseUrl() + path, settings);
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || ("Bridge HTTP " + response.status));
  return result;
}
function setConnected(enabled) {
  ["capture", "refresh", "effects", "send", "importSnapshot", "exportXml"].forEach(function (id) {
    const button = document.getElementById(id);
    if (button) button.disabled = !enabled;
  });
}
async function connect() {
  const code = document.getElementById("pairing").value.trim();
  if (!/^\d{6}$/.test(code)) throw new Error("Enter the six-digit code from DepthVibe.");
  const hostVersion = host && host.version ? host.version : "Unknown";
  const pairing = await request("/v1/pair", {
    method: "POST",
    body: JSON.stringify({
      code: code,
      hostApp: "premierepro",
      hostVersion: hostVersion
    })
  });
  sessionToken = pairing.token;
  setConnected(true);
  setConnected(true);
  setStatus("Connected to DepthVibe.");
  showResult(await request("/v1/session"));
}
async function captureSequence() {
  setStatus("Reading the active Premiere sequence…");
  const snapshot = await capturePremiereSequence();
  latestSnapshot = snapshot;
  installedVideoEffects = snapshot.payload.installedVideoEffects || [];
  refreshClipTargets();
  renderHostEffectList(document);
  const result = await request("/v1/adobe/metadata", {
    method: "POST",
    body: JSON.stringify({ snapshot: snapshot })
  });
  showResult({
    project: snapshot.payload.project.name,
    sequence: snapshot.payload.sequence.name,
    videoTracks: snapshot.payload.videoTracks.length,
    audioTracks: snapshot.payload.audioTracks.length,
    installedVideoTransitions: (snapshot.payload.installedVideoTransitions || []).length,
    installedVideoEffects: installedVideoEffects.length,
    appliedVideoTransitions: snapshot.payload.videoTracks.reduce(
      function (count, track) { return count + (track.transitions || []).length; }, 0
    ),
    capturedClips: snapshot.payload.videoTracks.reduce(
      function (count, track) { return count + track.clips.length; }, 0
    ) + snapshot.payload.audioTracks.reduce(
      function (count, track) { return count + track.clips.length; }, 0
    ),
    bridgeResponse: result
  });
  setStatus("Active Premiere sequence metadata sent to DepthVibe.");
}
function refreshClipTargets() {
  const select = document.getElementById("hostEffectTarget");
  if (!select) return;
  const previous = select.value;
  select.replaceChildren();
  const clips = [];
  if (latestSnapshot && latestSnapshot.payload) {
    const tracks = (latestSnapshot.payload.videoTracks || [])
      .concat(latestSnapshot.payload.audioTracks || []);
    tracks.forEach(function (track) {
      (track.clips || []).forEach(function (clip) {
        if (clip.id === null || clip.id === undefined) return;
        clips.push({
          id: String(clip.id),
          name: String(clip.name || "Untitled clip"),
          track: String(track.name || track.id || "Track")
        });
      });
    });
  }
  clips.forEach(function (clip) {
    const option = document.createElement("option");
    option.value = clip.id;
    option.textContent = clip.track + " · " + clip.name + " · " + clip.id;
    select.appendChild(option);
  });
  if (clips.some(function (clip) { return clip.id === previous; })) select.value = previous;
  if (!clips.length) {
    const option = document.createElement("option");
    option.value = "";
    option.textContent = "Capture a sequence with clips first";
    select.appendChild(option);
  }
}
function renderHostEffectList(root) {
  const search = root.querySelector("#hostEffectSearch");
  const container = root.querySelector("#hostEffectList");
  if (!container) return;
  const term = search ? search.value.trim().toLowerCase() : "";
  const matches = installedVideoEffects.filter(function (effect) {
    return [effect.displayName, effect.matchName, effect.category]
      .join(" ").toLowerCase().indexOf(term) >= 0;
  }).slice(0, 300);
  container.replaceChildren();
  if (!matches.length) {
    const note = document.createElement("small");
    note.textContent = installedVideoEffects.length
      ? "No matching installed video effects."
      : "Capture a sequence or refresh to load Premiere's installed effects.";
    container.appendChild(note);
    return;
  }
  matches.forEach(function (effect) {
    const button = document.createElement("button");
    button.className = "secondary host-effect";
    button.textContent = effect.displayName;
    button.title = effect.matchName;
    button.addEventListener("click", async function () {
      try {
        const clipId = root.querySelector("#hostEffectTarget").value;
        if (!clipId) throw new Error("Select a target clip first.");
        setStatus("Applying " + effect.displayName + " to Premiere clip…");
        const result = await applyNativeVideoEffect(clipId, effect.matchName, []);
        await publishPremiereSnapshot(result.snapshot);
        output({
          effect: effect,
          appliedToClipId: result.appliedToClipId,
          parametersApplied: result.parametersApplied,
          skippedParameters: result.skippedParameters,
          importedIntoDepthVibe: true
        });
        setStatus("Native effect applied in Premiere and its parameter schema imported into DepthVibe.");
      } catch (error) {
        setStatus(error.message);
        showResult(error.stack || error.message);
      }
    });
    container.appendChild(button);
  });
  const count = document.createElement("small");
  count.textContent = "Showing " + matches.length + " of " + installedVideoEffects.length + " installed video effects";
  container.appendChild(count);
}
async function publishPremiereSnapshot(snapshot) {
  latestSnapshot = snapshot;
  installedVideoEffects = snapshot.payload.installedVideoEffects || installedVideoEffects;
  refreshClipTargets();
  renderHostEffectList(document);
  await request("/v1/adobe/metadata", {
    method: "POST",
    body: JSON.stringify({snapshot: snapshot})
  });
  return await request("/v1/adobe/import", {method: "POST", body: "{}"});
}
async function refreshHostEffects() {
  const inventory = await captureInstalledVideoEffects();
  installedVideoEffects = inventory.effects || [];
  renderHostEffectList(document);
  setStatus(inventory.supported
    ? "Found " + installedVideoEffects.length + " installed Premiere video effects."
    : "Installed video effect inventory needs Premiere Pro 25.6 or later.");
  showResult({
    supported: inventory.supported,
    minimumVersion: inventory.minimumVersion,
    effectCount: installedVideoEffects.length
  });
}
async function syncDepthVibeNativeSettings() {
  const clipId = document.getElementById("hostEffectTarget").value;
  if (!clipId) throw new Error("Select the Premiere clip to receive the DepthVibe settings.");
  const response = await request("/v1/composition");
  const doc = response.document || {};
  const layer = (doc.layers || []).find(function (item) {
    return String(item.externalSourceId || "") === String(clipId);
  });
  if (!layer) throw new Error("Import the captured Premiere clip into DepthVibe first.");
  const nativeEffects = (layer.effects || []).filter(function (effect) {
    const descriptor = effect.nativeDescriptor || {};
    return descriptor.hostApp === "premierepro" && descriptor.matchName;
  });
  if (!nativeEffects.length) throw new Error("The selected DepthVibe layer has no captured Premiere-native effects.");
  const results = [];
  for (const effect of nativeEffects) {
    const descriptor = effect.nativeDescriptor;
    results.push(await applyNativeVideoEffect(
      clipId,
      descriptor.matchName,
      Array.isArray(descriptor.parameters) ? descriptor.parameters : []
    ));
  }
  const snapshot = await capturePremiereSequence();
  const imported = await publishPremiereSnapshot(snapshot);
  showResult({
    clipId: clipId,
    updatedNativeEffects: results.map(function (item) {
      return {
        matchName: item.matchName,
        parametersApplied: item.parametersApplied,
        createdNewComponent: item.createdNewComponent,
        skippedParameters: item.skippedParameters
      };
    }),
    depthVibeImport: imported
  });
  setStatus("DepthVibe native effect values sent to Premiere. Animated/keyframed values remain retained in DepthVibe metadata.");
}

async function readLatestSnapshot() {
  const result = await request("/v1/adobe/metadata");
  showResult(result.snapshot || result);
  setStatus("Latest Adobe host snapshot received from DepthVibe.");
}
async function readComposition() {
  const result = await request("/v1/composition");
  const document = result.document || {};
  const layers = Array.isArray(document.layers) ? document.layers : [];
  showResult({
    name: document.name,
    width: document.width,
    height: document.height,
    frameRate: document.frameRate,
    layerCount: layers.length,
    layerNames: layers.map(function (layer) { return layer.name; })
  });
  setStatus("Composition snapshot received from DepthVibe.");
}
async function listEffects() {
  const result = await request("/v1/effects");
  showResult(result.effects || []);
  setStatus("Effect catalog received.");
}

async function importCapturedTimeline() {
  setStatus("Importing Premiere sequence into DepthVibe…");
  const result = await request("/v1/adobe/import", { method: "POST", body: "{}" });
  showResult(result);
  setStatus("Imported " + result.composition.layerCount + " editable DepthVibe layers.");
}
async function exportPremiereXml() {
  const result = await request("/v1/adobe/export/premiere.xml");
  const file = await storage.localFileSystem.getFileForSaving(result.filename);
  if (!file) return;
  await file.write(result.content);
  showResult({ filename: result.filename, format: result.format,
    note: "Import via Premiere Pro > File > Import. This XML carries clip timing/media references and supported static Gaussian Blur filters; other effect filters are reported as unsupported." });
  setStatus("Premiere interchange XML saved.");
}

async function sendComposition() {
  const input = document.getElementById("document").value.trim();
  if (!input) throw new Error("Paste a DepthVibe composition document first.");
  const result = await request("/v1/composition", {
    method: "POST",
    body: JSON.stringify({ document: JSON.parse(input) })
  });
  showResult(result);
  setStatus("Composition sent to DepthVibe.");
}
function bindPanel(rootNode) {
  rootNode.querySelector("#refreshHostEffects").addEventListener("click", async function () {
    try { await refreshHostEffects(); } catch (error) { setStatus(error.message); showResult(error.stack || error.message); }
  });
  rootNode.querySelector("#hostEffectSearch").addEventListener("input", function () {
    renderHostEffectList(rootNode);
  });
  rootNode.querySelector("#syncNativeSettings").addEventListener("click", async function () {
    try { await syncDepthVibeNativeSettings(); } catch (error) { setStatus(error.message); showResult(error.stack || error.message); }
  });
  rootNode.querySelector("#connect").addEventListener("click", async function () {
    try { setStatus("Connecting…"); await connect(); }
    catch (error) { setStatus(error.message); showResult(error.stack || error.message); }
  });
  rootNode.querySelector("#capture").addEventListener("click", async function () {
    try { await captureSequence(); }
    catch (error) { setStatus(error.message); showResult(error.stack || error.message); }
  });
  rootNode.querySelector("#importSnapshot").addEventListener("click", async function () {
    try { await importCapturedTimeline(); } catch (error) { setStatus(error.message); showResult(error.stack || error.message); }
  });
  rootNode.querySelector("#exportXml").addEventListener("click", async function () {
    try { await exportPremiereXml(); } catch (error) { setStatus(error.message); showResult(error.stack || error.message); }
  });
  rootNode.querySelector("#refresh").addEventListener("click", async function () {
    try { await readComposition(); } catch (error) { setStatus(error.message); }
  });
  rootNode.querySelector("#effects").addEventListener("click", async function () {
    try { await listEffects(); } catch (error) { setStatus(error.message); }
  });
  rootNode.querySelector("#send").addEventListener("click", async function () {
    try { await sendComposition(); } catch (error) { setStatus(error.message); }
  });
}
entrypoints.setup({
  panels: {
    depthVibeBridgePanel: {
      create: function (rootNode) { bindPanel(rootNode); }
    }
  }
});
