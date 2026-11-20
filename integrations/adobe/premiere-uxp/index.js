const { entrypoints, storage } = require("uxp");
const { capturePremiereSequence } = require("./premiere-host-adapter");
const { host } = require("uxp");
const DEFAULT_BRIDGE = "http://127.0.0.1:47653";
let sessionToken = null;

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
  setStatus("Connected to DepthVibe.");
  showResult(await request("/v1/session"));
}
async function captureSequence() {
  setStatus("Reading the active Premiere sequence…");
  const snapshot = await capturePremiereSequence();
  const result = await request("/v1/adobe/metadata", {
    method: "POST",
    body: JSON.stringify({ snapshot: snapshot })
  });
  showResult({
    project: snapshot.payload.project.name,
    sequence: snapshot.payload.sequence.name,
    videoTracks: snapshot.payload.videoTracks.length,
    audioTracks: snapshot.payload.audioTracks.length,
    capturedClips: snapshot.payload.videoTracks.reduce(
      function (count, track) { return count + track.clips.length; }, 0
    ) + snapshot.payload.audioTracks.reduce(
      function (count, track) { return count + track.clips.length; }, 0
    ),
    bridgeResponse: result
  });
  setStatus("Active Premiere sequence metadata sent to DepthVibe.");
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
