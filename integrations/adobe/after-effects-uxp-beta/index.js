const { entrypoints } = require("uxp");
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
function bind(root) {
  root.querySelector("#connect").addEventListener("click", async function () {
    try {
      const code = root.querySelector("#pairing").value.trim();
      if (!/^\d{6}$/.test(code)) throw new Error("Enter a six-digit pairing code.");
      const pairing = await api("/v1/pair", {
        method: "POST",
        body: JSON.stringify({
          code: code,
          hostApp: "aftereffects-beta",
          hostVersion: "27.1+"
        })
      });
      token = pairing.token;
      ["read", "effects", "send"].forEach(function (id) {
        root.querySelector("#" + id).disabled = false;
      });
      status("Connected to DepthVibe.");
      output(await api("/v1/session"));
    } catch (error) { status(error.message); }
  });
  root.querySelector("#read").addEventListener("click", async function () {
    try { output(await api("/v1/composition")); status("Composition received."); }
    catch (error) { status(error.message); }
  });
  root.querySelector("#effects").addEventListener("click", async function () {
    try { output(await api("/v1/effects")); status("Effect catalog received."); }
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