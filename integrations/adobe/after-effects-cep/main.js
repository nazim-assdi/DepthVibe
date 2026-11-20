const DEFAULT_BRIDGE = "http://127.0.0.1:47653";
let sessionToken = null;
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
function status(message) { document.getElementById("status").textContent = message; }
function output(data) {
  document.getElementById("result").textContent =
    typeof data === "string" ? data : JSON.stringify(data, null, 2);
}
async function api(path, options) {
  const settings = options || {};
  settings.headers = Object.assign({}, settings.headers || {});
  settings.headers["Content-Type"] = "application/json";
  if (sessionToken) settings.headers.Authorization = "Bearer " + sessionToken;
  const response = await fetch(bridgeBaseUrl() + path, settings);
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || ("HTTP " + response.status));
  return data;
}
function enabled(value) {
  ["read", "effects", "send"].forEach(function (id) {
    document.getElementById(id).disabled = !value;
  });
}
document.getElementById("connect").addEventListener("click", async function () {
  try {
    const code = document.getElementById("pairing").value.trim();
    const response = await api("/v1/pair", {
      method: "POST",
      body: JSON.stringify({code: code, hostApp: "aftereffects", hostVersion: "CEP 11"})
    });
    sessionToken = response.token;
    enabled(true);
    status("Connected to DepthVibe.");
    output(await api("/v1/session"));
  } catch (error) { status(error.message); }
});
document.getElementById("read").addEventListener("click", async function () {
  try {
    const result = await api("/v1/composition");
    const doc = result.document || {};
    const layers = Array.isArray(doc.layers) ? doc.layers : [];
    output({
      name: doc.name,
      width: doc.width,
      height: doc.height,
      frameRate: doc.frameRate,
      layerCount: layers.length
    });
    status("DepthVibe composition received.");
  } catch (error) { status(error.message); }
});
document.getElementById("effects").addEventListener("click", async function () {
  try { output(await api("/v1/effects")); status("DepthVibe effect catalog received."); }
  catch (error) { status(error.message); }
});
document.getElementById("send").addEventListener("click", async function () {
  try {
    const documentData = JSON.parse(document.getElementById("document").value);
    output(await api("/v1/composition", {
      method: "POST",
      body: JSON.stringify({document: documentData})
    }));
    status("Composition sent to DepthVibe.");
  } catch (error) { status(error.message); }
});