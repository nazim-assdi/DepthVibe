const { entrypoints } = require("uxp");
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
  ["refresh", "effects", "send"].forEach(function (id) {
    const button = document.getElementById(id);
    if (button) button.disabled = !enabled;
  });
}
async function connect() {
  const code = document.getElementById("pairing").value.trim();
  if (!/^\d{6}$/.test(code)) throw new Error("Enter the six-digit code from DepthVibe.");
  const pairing = await request("/v1/pair", {
    method: "POST",
    body: JSON.stringify({
      code: code,
      hostApp: "premierepro",
      hostVersion: "25.6+"
    })
  });
  sessionToken = pairing.token;
  setConnected(true);
  setStatus("Connected to DepthVibe.");
  showResult(await request("/v1/session"));
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