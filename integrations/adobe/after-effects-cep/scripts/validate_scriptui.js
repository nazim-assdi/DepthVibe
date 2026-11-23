const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");

const scriptPath = path.join(__dirname, "DepthVibe_Motion_Tools.jsx");
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
  "Center Visible Bounds Horizontally",
  "Center Visible Bounds Vertically",
  "Distribute Visible Centers Horizontally",
  "Distribute Visible Centers Vertically",
  "Whip In Left",
  "Whip In Right",
  "Add Fractal Noise",
  "Add Lumetri Color",
  "Add CC Light Sweep",
];

for (const name of requiredFunctions) {
  assert.ok(
    source.includes("function " + name + "("),
    "Missing After Effects utility: " + name
  );
}

for (const label of requiredControls) {
  assert.ok(
    source.includes('"' + label + '"'),
    "Missing ScriptUI control: " + label
  );
}

const undoGroups = source.split("app.beginUndoGroup(").length - 1;
assert.ok(undoGroups >= 1, "Actions must be grouped into native AE undo steps");

console.log(
  "After Effects ScriptUI validation passed: " +
  requiredFunctions.length + " utilities and " +
  requiredControls.length + " required controls."
);
