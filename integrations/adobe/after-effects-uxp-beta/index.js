const { entrypoints, host, storage } = require("uxp");
const {
  captureActiveComposition,
  captureInstalledEffects,
  applyNativeEffectToSelection,
  syncNativeEffectsToSelection,
  applyFfxPreset,
  saveFfxPreset
} = require("./after-effects-host-adapter");
const DEFAULT_BRIDGE = "http://127.0.0.1:47653";
let token = null;
let installedEffects = [];
let motionBroAssets = [];

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
  ["capture", "read", "effects", "send", "importSnapshot", "exportScript",
   "refreshHostEffects", "syncNativeEffects", "ffxImport", "ffxExport", "refreshMotionBroAssets"].forEach(function (id) {
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
async function publishHostSnapshot(snapshot) {
  await api("/v1/adobe/metadata", {
    method: "POST",
    body: JSON.stringify({snapshot: snapshot})
  });
  const imported = await api("/v1/adobe/import", {
    method: "POST",
    body: "{}"
  });
  return imported;
}
async function captureComposition() {
  status("Reading the active After Effects composition…");
  const snapshot = captureActiveComposition();
  const result = await api("/v1/adobe/metadata", {
    method: "POST",
    body: JSON.stringify({snapshot: snapshot})
  });
  installedEffects = snapshot.payload.installedEffects || [];
  if (installedEffects.length) renderHostEffectList(document);
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
async function refreshHostEffects() {
  const inventory = captureInstalledEffects();
  installedEffects = inventory.effects || [];
  renderHostEffectList(document);
  if (!inventory.supported) {
    status("Installed effect inventory requires After Effects 27.0 or later.");
    output(inventory);
    return;
  }
  status("Found " + installedEffects.length + " installed After Effects effects.");
  output({installedEffectCount: installedEffects.length, minimumVersion: inventory.minimumVersion});
}
function renderHostEffectList(root) {
  const search = root.querySelector("#hostEffectSearch");
  const container = root.querySelector("#hostEffectList");
  if (!container) return;
  const term = search ? search.value.trim().toLowerCase() : "";
  const matches = installedEffects.filter(function (effect) {
    return [effect.displayName, effect.matchName, effect.category, effect.version]
      .join(" ").toLowerCase().indexOf(term) >= 0;
  }).slice(0, 250);
  container.replaceChildren();
  if (!matches.length) {
    const note = document.createElement("small");
    note.textContent = installedEffects.length
      ? "No matching installed effects."
      : "Refresh installed effects to read the Adobe effect catalog.";
    container.appendChild(note);
    return;
  }
  matches.forEach(function (effect) {
    const button = document.createElement("button");
    button.className = "secondary host-effect";
    button.textContent = effect.displayName + " · " + effect.category;
    button.title = effect.matchName + " · " + (effect.version || "");
    button.addEventListener("click", async function () {
      try {
        status("Applying " + effect.displayName + " to selected layer(s)…");
        const result = applyNativeEffectToSelection(effect.matchName);
        const imported = await publishHostSnapshot(result.snapshot);
        output({
          effect: effect,
          applied: result.applied,
          warnings: result.warnings,
          depthVibeImport: imported
        });
        status("Applied native effect and synchronized its parameters/keyframes to DepthVibe.");
      } catch (error) {
        status(error.message);
        output(error.stack || error.message);
      }
    });
    container.appendChild(button);
  });
  const count = document.createElement("small");
  count.textContent = "Showing " + matches.length + " of " + installedEffects.length + " installed effects";
  container.appendChild(count);
}
async function refreshMotionBroAssets() {
  const catalog = await api("/v1/motionbro/assets");
  motionBroAssets = (catalog.assets || []).filter(function (asset) {
    return asset.extension === "ffx" &&
      (!Array.isArray(asset.apps) || !asset.apps.length || asset.apps.indexOf("AE") >= 0);
  });
  renderMotionBroAssets(document);
  status("Found " + motionBroAssets.length + " Motion Bro/pack .ffx presets.");
  output({
    importedPackCount: (catalog.packs || []).length,
    afterEffectsPresetCount: motionBroAssets.length,
    scriptExecution: catalog.scriptExecution
  });
}
function renderMotionBroAssets(root) {
  const container = root.querySelector("#motionBroPresetList");
  const search = root.querySelector("#motionBroSearch");
  if (!container) return;
  const term = search ? search.value.trim().toLowerCase() : "";
  const matches = motionBroAssets.filter(function (asset) {
    return [asset.packName, asset.category, asset.fileName, asset.relativePath]
      .join(" ").toLowerCase().indexOf(term) >= 0;
  }).slice(0, 250);
  container.replaceChildren();
  if (!matches.length) {
    const note = document.createElement("small");
    note.textContent = motionBroAssets.length
      ? "No matching .ffx presets."
      : "Import an MBR pack in DepthVibe and refresh this list.";
    container.appendChild(note);
    return;
  }
  matches.forEach(function (asset) {
    const button = document.createElement("button");
    button.className = "secondary host-effect";
    button.textContent = asset.packName + " · " + asset.category + " · " + asset.fileName;
    button.title = asset.path;
    button.addEventListener("click", async function () {
      try {
        status("Applying Motion Bro preset " + asset.fileName + "…");
        const result = applyFfxPreset(asset.path);
        const imported = await publishHostSnapshot(result.snapshot);
        output({
          pack: asset.packName,
          preset: asset.relativePath,
          applied: result.applied,
          depthVibeImport: imported
        });
        status("Motion Bro .ffx preset applied in After Effects and captured in DepthVibe.");
      } catch (error) {
        status(error.message);
        output(error.stack || error.message);
      }
    });
    container.appendChild(button);
  });
  const count = document.createElement("small");
  count.textContent = "Showing " + matches.length + " of " + motionBroAssets.length + " After Effects presets";
  container.appendChild(count);
}

async function syncDepthVibeNativeEffects() {
  status("Reading the current DepthVibe composition…");
  const response = await api("/v1/composition");
  const result = syncNativeEffectsToSelection(response.document || {});
  const imported = await publishHostSnapshot(result.snapshot);
  output({applied: result.applied, warnings: result.warnings, importedIntoDepthVibe: imported});
  status("DepthVibe native effect values/keyframes synchronized to selected After Effects layers.");
}
async function importFfxPreset() {
  const file = await storage.localFileSystem.getFileForOpening({types: ["ffx"]});
  if (!file) return;
  const path = storage.localFileSystem.getNativePath(file);
  status("Applying After Effects animation preset…");
  const result = applyFfxPreset(path);
  const imported = await publishHostSnapshot(result.snapshot);
  installedEffects = result.snapshot.payload.installedEffects || installedEffects;
  renderHostEffectList(document);
  output({preset: file.name, applied: result.applied, depthVibeImport: imported});
  status("Applied .ffx preset in After Effects and imported its editable snapshot into DepthVibe.");
}
async function exportFfxPreset() {
  const file = await storage.localFileSystem.getFileForSaving("DepthVibe_Animation.ffx");
  if (!file) return;
  const path = storage.localFileSystem.getNativePath(file);
  const result = saveFfxPreset(path);
  output({file: file.name, saved: result.saved});
  status("Selected After Effects properties exported as an .ffx animation preset.");
}

async function readLatestSnapshot() {
  const result = await api("/v1/adobe/metadata");
  output(result.snapshot || result);
  status("Latest Adobe host snapshot received from DepthVibe.");
}

async function importCapturedComposition() {
  status("Importing After Effects composition into DepthVibe…");
  const result = await api("/v1/adobe/import", { method: "POST", body: "{}" });
  output(result);
  status("Imported " + result.composition.layerCount + " editable DepthVibe layers.");
}
async function exportAfterEffectsScript() {
  const result = await api("/v1/adobe/export/after-effects.jsx");
  const file = await storage.localFileSystem.getFileForSaving(result.filename);
  if (!file) return;
  await file.write(result.content);
  output({ filename: result.filename, format: result.format,
    instruction: "In After Effects use File > Scripts > Run Script File to create the editable composition." });
  status("After Effects import script saved.");
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
  root.querySelector("#importSnapshot").addEventListener("click", async function () {
    try { await importCapturedComposition(); } catch (error) { status(error.message); output(error.stack || error.message); }
  });
  root.querySelector("#exportScript").addEventListener("click", async function () {
    try { await exportAfterEffectsScript(); } catch (error) { status(error.message); output(error.stack || error.message); }
  });
  root.querySelector("#read").addEventListener("click", async function () {
    try { output(await api("/v1/composition")); status("DepthVibe composition received."); }
    catch (error) { status(error.message); }
  });
  root.querySelector("#effects").addEventListener("click", async function () {
    try { output(await api("/v1/effects")); status("DepthVibe effect catalog received."); }
    catch (error) { status(error.message); }
  });
  root.querySelector("#refreshHostEffects").addEventListener("click", async function () {
    try { await refreshHostEffects(); } catch (error) { status(error.message); output(error.stack || error.message); }
  });
  root.querySelector("#hostEffectSearch").addEventListener("input", function () {
    renderHostEffectList(root);
  });
  root.querySelector("#syncNativeEffects").addEventListener("click", async function () {
    try { await syncDepthVibeNativeEffects(); } catch (error) { status(error.message); output(error.stack || error.message); }
  });
  root.querySelector("#ffxImport").addEventListener("click", async function () {
    try { await importFfxPreset(); } catch (error) { status(error.message); output(error.stack || error.message); }
  });
  root.querySelector("#ffxExport").addEventListener("click", async function () {
    try { await exportFfxPreset(); } catch (error) { status(error.message); output(error.stack || error.message); }
  });
  root.querySelector("#refreshMotionBroAssets").addEventListener("click", async function () {
    try { await refreshMotionBroAssets(); } catch (error) { status(error.message); output(error.stack || error.message); }
  });
  root.querySelector("#motionBroSearch").addEventListener("input", function () {
    renderMotionBroAssets(root);
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
