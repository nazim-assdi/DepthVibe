const { entrypoints, host } = require("uxp");
const { captureActiveComposition } = require("./after-effects-host-adapter");
const DEFAULT_BRIDGE = "http://127.0.0.1:47653";
let token = null;

function bridgeBaseUrl() {
  const field = document.getElementById("bridgeUrl");
  const raw = field && field.value.trim() ? field.value.trim() : DEFAULT_BRIDGE;
  const parsed = new URL(raw);
  if (!["http:", "https:"].includes(parsed.protocol) ||
      parsed.hostname !== "127.0.0.1" || parsed.port !== "47653" ||
      parsed.username || parsed.password ||
      (parsed.pathname !== "/" && parsed.pathname !== "")) {
    throw new Error("Use only http(s)://127.0.0.1:47653 for the local bridge.");
  }
  return parsed.origin;
}

async function api(path, options) {
  const settings = options || {};
  settings.headers = Object.assign({}, settings.headers || {});
  settings.headers["Content-Type"] = "application/json";
  if (token) settings.headers.Authorization = "Bearer " + token;
  const response = await fetch(bridgeBaseUrl() + path, settings);
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || ("HTTP " + response.status));
  return data;
}
function status(message) {
  document.getElementById("status").textContent = message;
}
function output(value) {
  document.getElementById("result").textContent =
    typeof value === "string" ? value : JSON.stringify(value, null, 2);
}
function setConnected(connected) {
  ["capture", "read", "effects", "send"].forEach(function (id) {
    document.getElementById(id).disabled = !connected;
  });
}
async function connect() {
  const code = document.getElementById("pairing").value.trim();
  if (!/^\d{6}$/.test(code)) throw new Error("Enter a six-digit pairing code.");
  const hostVersion = host && host.version ? host.version : "Unknown";
  const pairing = await api("/v1/pair", {
    method: "POST",
    body: JSON.stringify({
      code: code,
      hostApp: "aftereffects-beta",
      hostVersion: hostVersion
    })
  });
  token = pairing.token;
  setConnected(true);
  status("Connected to DepthVibe.");
  output(await api("/v1/session"));
}
async function captureComposition() {
  status("Reading the active After Effects composition…");
  const snapshot = captureActiveComposition();
  const result = await api("/v1/adobe/metadata", {
    method: "POST",
    body: JSON.stringify({snapshot: snapshot})
  });
  const payload = snapshot.payload;
  output({
    project: payload.project.file,
    composition: payload.composition.name,
    width: payload.composition.width,
    height: payload.composition.height,
    frameRate: payload.composition.frameRate,
    layers: payload.layers.length,
    bridgeResponse: result
  });
  status("Active After Effects composition metadata sent to DepthVibe.");
}
async function readLatestSnapshot() {
  const result = await api("/v1/adobe/metadata");
  output(result.snapshot || result);
  status("Latest Adobe host snapshot received from DepthVibe.");
}
function bind(root) {
  root.querySelector("#connect").addEventListener("click", async function () {
    try { status("Connecting…"); await connect(); }
    catch (error) { status(error.message); output(error.stack || error.message); }
  });
  root.querySelector("#capture").addEventListener("click", async function () {
    try { await captureComposition(); }
    catch (error) { status(error.message); output(error.stack || error.message); }
  });
  root.querySelector("#read").addEventListener("click", async function () {
    try { output(await api("/v1/composition")); status("DepthVibe composition received."); }
    catch (error) { status(error.message); }
  });
  root.querySelector("#effects").addEventListener("click", async function () {
    try { output(await api("/v1/effects")); status("DepthVibe effect catalog received."); }
    catch (error) { status(error.message); }
  });
  root.querySelector("#send").addEventListener("click", async function () {
    try {
      const documentData = JSON.parse(root.querySelector("#document").value);
      output(await api("/v1/composition", {
        method: "POST",
        body: JSON.stringify({document: documentData})
      }));
      status("Composition sent to DepthVibe.");
    } catch (error) { status(error.message); }
  });
}
entrypoints.setup({
  panels: {
    depthVibeAfterEffectsPanel: {
      create: function (root) { bind(root); }
    }
  }
});
