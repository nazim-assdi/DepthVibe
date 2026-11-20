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
  ["capture", "read", "effects", "send", "importSnapshot"].forEach(function (id) {
    document.getElementById(id).disabled = !value;
  });
}
function evalHostSnapshot() {
  return new Promise(function (resolve, reject) {
    const cep = window.__adobe_cep__;
    if (!cep || typeof cep.evalScript !== "function") {
      reject(new Error("The Adobe CEP host bridge is not available."));
      return;
    }
    cep.evalScript("depthVibeGetActiveCompSnapshot()", function (result) {
      try {
        const parsed = JSON.parse(result);
        if (parsed && parsed.error) reject(new Error(parsed.error));
        else resolve(parsed);
      } catch (error) {
        reject(new Error("Could not parse the After Effects host snapshot: " + error));
      }
    });
  });
}
document.getElementById("connect").addEventListener("click", async function () {
  try {
    const code = document.getElementById("pairing").value.trim();
    if (!/^\d{6}$/.test(code)) throw new Error("Enter a six-digit pairing code.");
    const hostInfo = await new Promise(function (resolve, reject) {
      const cep = window.__adobe_cep__;
      if (!cep || typeof cep.evalScript !== "function") {
        resolve({hostVersion: "CEP"});
        return;
      }
      cep.evalScript("JSON.stringify(depthVibeGetHostInfo())", function (value) {
        try { resolve(JSON.parse(value)); }
        catch (_) { resolve({hostVersion: "CEP"}); }
      });
    });
    const response = await api("/v1/pair", {
      method: "POST",
      body: JSON.stringify({
        code: code,
        hostApp: "aftereffects",
        hostVersion: hostInfo.hostVersion || "CEP"
      })
    });
    sessionToken = response.token;
    enabled(true);
    status("Connected to DepthVibe.");
    output(await api("/v1/session"));
  } catch (error) { status(error.message); }
});
document.getElementById("capture").addEventListener("click", async function () {
  try {
    status("Reading the active After Effects composition…");
    const snapshot = await evalHostSnapshot();
    const response = await api("/v1/adobe/metadata", {
      method: "POST",
      body: JSON.stringify({snapshot: snapshot})
    });
    output({
      project: snapshot.payload.project.file,
      composition: snapshot.payload.composition.name,
      width: snapshot.payload.composition.width,
      height: snapshot.payload.composition.height,
      frameRate: snapshot.payload.composition.frameRate,
      layers: snapshot.payload.layers.length,
      bridgeResponse: response
    });
    status("Active After Effects composition metadata sent to DepthVibe.");
  } catch (error) { status(error.message); output(error.stack || error.message); }
});

document.getElementById("importSnapshot").addEventListener("click", async function () {
  try {
    status("Importing After Effects composition into DepthVibe…");
    const result = await api("/v1/adobe/import", {method: "POST", body: "{}"});
    output(result);
    status("Imported " + result.composition.layerCount + " editable DepthVibe layers.");
  } catch (error) { status(error.message); output(error.stack || error.message); }
});
document.getElementById("read").addEventListener("click", async function () {
  try {
    const result = await api("/v1/composition");
    output(result.document || result);
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
