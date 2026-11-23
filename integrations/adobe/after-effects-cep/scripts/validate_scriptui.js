const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");

const scriptPath = path.join(
  __dirname,
  "DepthVibe_Motion_Tools.jsx"
);
const source = fs.readFileSync(scriptPath, "utf8");

const requiredFunctions = [
  "sequenceSelectedLayersAtPlayhead",
  "trimSelectedLayersToPlayhead",
  "splitSelectedLayersAtPlayhead",
  "addCompositionMarker",
  "addSelectedLayerMarkers",
  "alignSelectedLayers",
  "distributeSelectedLayers",
  "addNativeEffect",
  "animateSelected",
];

const requiredControls = [
  "Sequence Selected Layers",
  "Trim Layer Starts to Playhead",
  "Trim Layer Ends to Playhead",
  "Split Selected Layers at Playhead",
  "Add Composition Marker",
  "Add Markers to Selected Layers",
  "Center Horizontally",
  "Center Vertically",
  "Distribute Horizontally",
  "Distribute Vertically",
  "Whip In Left",
  "Whip In Right",
  "Add Fractal Noise",
  "Add Lumetri Color",
  "Add CC Light Sweep",
];

for (const name of requiredFunctions) {
  assert.match(
    source,
    new RegExp("function\\s+" + name + "\\s*\\("),
    "Missing After Effects utility: " + name
  );
}

for (const label of requiredControls) {
  assert.ok(
    source.includes('"' + label + '"'),
    "Missing ScriptUI control: " + label
  );
}

const undoGroups = (source.match(/app\\.beginUndoGroup\\(/g) || []).length;
assert.ok(undoGroups >= 1, "Actions must be grouped into native AE undo steps");

console.log(
  "After Effects ScriptUI validation passed: " +
  requiredFunctions.length + " utilities and " +
  requiredControls.length + " required controls."
);
