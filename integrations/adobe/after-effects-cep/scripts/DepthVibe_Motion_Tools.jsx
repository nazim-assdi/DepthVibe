/*
 * DepthVibe Motion Tools — original ExtendScript / ScriptUI palette.
 * Run with After Effects: File > Scripts > Run Script File…
 *
 * All edits are explicit, grouped into native AE undo steps, and target only
 * unlocked selected layers. No third-party script or paid preset is included.
 */
(function depthVibeMotionTools(thisObj) {
  function activeComp() {
    var comp = app.project && app.project.activeItem;
    if (!(comp instanceof CompItem)) {
      alert("Open a project and select an active composition first.");
      return null;
    }
    return comp;
  }

  function undoGroup(label, action) {
    app.beginUndoGroup("DepthVibe - " + label);
    try {
      action();
    } catch (error) {
      alert("DepthVibe: " + error.toString());
    } finally {
      app.endUndoGroup();
    }
  }

  function selectedLayers(comp) {
    var selection = comp.selectedLayers || [];
    var layers = [];
    for (var i = 0; i < selection.length; i++) {
      if (selection[i] && !selection[i].locked) layers.push(selection[i]);
    }
    layers.sort(function (a, b) { return a.index - b.index; });
    return layers;
  }

  function cloneValue(value) {
    if (value instanceof Array) return value.slice(0);
    return value;
  }

  function scaledValue(value, factor) {
    var result = cloneValue(value);
    if (result instanceof Array) {
      for (var i = 0; i < result.length; i++) result[i] *= factor;
      return result;
    }
    return result * factor;
  }

  function offsetPosition(value, dx, dy) {
    var result = cloneValue(value);
    if (!(result instanceof Array)) return result;
    result[0] += dx;
    if (result.length > 1) result[1] += dy;
    return result;
  }

  function transformProperty(layer, matchName) {
    var transform = layer.property("ADBE Transform Group");
    return transform ? transform.property(matchName) : null;
  }

  function currentValue(property, time) {
    return property.valueAtTime(time, false);
  }

  function setKey(property, time, value) {
    if (!property || !property.canVaryOverTime) return;
    property.setValueAtTime(time, value);
  }

  function easeKeysInRange(property, startTime, endTime) {
    if (!property || !property.numKeys ||
        typeof property.keyTime !== "function") return;
    for (var index = 1; index <= property.numKeys; index++) {
      var time = property.keyTime(index);
      if (time < startTime || time > endTime) continue;
      try {
        var value = property.keyValue(index);
        var dimensions = (value instanceof Array) ? value.length : 1;
        var easeIn = [];
        var easeOut = [];
        for (var d = 0; d < dimensions; d++) {
          easeIn.push(new KeyframeEase(0, 72));
          easeOut.push(new KeyframeEase(0, 72));
        }
        property.setTemporalEaseAtKey(index, easeIn, easeOut);
        property.setTemporalAutoBezierAtKey(index, true);
        property.setTemporalContinuousAtKey(index, true);
      } catch (_) {}
    }
  }

  function animateLayer(layer, comp, preset) {
    var start = Math.max(comp.time, layer.inPoint, comp.displayStartTime);
    var duration = Math.min(preset.duration || 0.75, layer.outPoint - start);
    if (duration <= 0.02) return false;
    var end = start + duration;
    var opacity = transformProperty(layer, "ADBE Opacity");
    var position = transformProperty(layer, "ADBE Position");
    var scale = transformProperty(layer, "ADBE Scale");
    var rotation = transformProperty(layer, "ADBE Rotate Z");
    var baseOpacity = currentValue(opacity, start);
    var basePosition = currentValue(position, start);
    var baseScale = currentValue(scale, start);
    var baseRotation = currentValue(rotation, start);
    var created = [];

    if (preset === "fade-in") {
      setKey(opacity, start, 0);
      setKey(opacity, end, baseOpacity);
      created.push([opacity, start, end]);
    } else if (preset === "fade-out") {
      setKey(opacity, start, baseOpacity);
      setKey(opacity, end, 0);
      created.push([opacity, start, end]);
    } else if (preset === "fade-pop") {
      setKey(opacity, start, 0);
      setKey(opacity, end, baseOpacity);
      setKey(scale, start, scaledValue(baseScale, 0.72));
      setKey(scale, end, baseScale);
      created.push([opacity, start, end], [scale, start, end]);
    } else if (preset === "slide-up") {
      setKey(position, start, offsetPosition(basePosition, 0, comp.height * 0.14));
      setKey(position, end, basePosition);
      setKey(opacity, start, 0);
      setKey(opacity, end, baseOpacity);
      created.push([position, start, end], [opacity, start, end]);
    } else if (preset === "slide-left") {
      setKey(position, start, offsetPosition(basePosition, comp.width * 0.14, 0));
      setKey(position, end, basePosition);
      setKey(opacity, start, 0);
      setKey(opacity, end, baseOpacity);
      created.push([position, start, end], [opacity, start, end]);
    } else if (preset === "spin-in") {
      setKey(rotation, start, baseRotation - 180);
      setKey(rotation, end, baseRotation);
      setKey(opacity, start, 0);
      setKey(opacity, end, baseOpacity);
      created.push([rotation, start, end], [opacity, start, end]);
    } else if (preset === "bounce-in") {
      setKey(scale, start, scaledValue(baseScale, 0.48));
      setKey(scale, start + duration * 0.72, scaledValue(baseScale, 1.12));
      setKey(scale, end, baseScale);
      setKey(opacity, start, 0);
      setKey(opacity, end, baseOpacity);
      created.push([scale, start, end], [opacity, start, end]);
    } else if (preset === "scale-punch") {
      setKey(scale, start, baseScale);
      setKey(scale, start + duration * 0.45, scaledValue(baseScale, 1.14));
      setKey(scale, end, baseScale);
      created.push([scale, start, end]);
    } else if (preset === "slide-right") {
      setKey(position, start, offsetPosition(basePosition, -comp.width * 0.14, 0));
      setKey(position, end, basePosition);
      setKey(opacity, start, 0);
      setKey(opacity, end, baseOpacity);
      created.push([position, start, end], [opacity, start, end]);
    } else if (preset === "slide-down") {
      setKey(position, start, offsetPosition(basePosition, 0, -comp.height * 0.14));
      setKey(position, end, basePosition);
      setKey(opacity, start, 0);
      setKey(opacity, end, baseOpacity);
      created.push([position, start, end], [opacity, start, end]);
    } else if (preset === "zoom-in") {
      setKey(scale, start, scaledValue(baseScale, 0.62));
      setKey(scale, end, baseScale);
      setKey(opacity, start, 0);
      setKey(opacity, end, baseOpacity);
      created.push([scale, start, end], [opacity, start, end]);
    } else if (preset === "elastic-pop") {
      setKey(scale, start, scaledValue(baseScale, 0.42));
      setKey(scale, start + duration * 0.56, scaledValue(baseScale, 1.18));
      setKey(scale, start + duration * 0.76, scaledValue(baseScale, 0.92));
      setKey(scale, start + duration * 0.9, scaledValue(baseScale, 1.035));
      setKey(scale, end, baseScale);
      setKey(opacity, start, 0);
      setKey(opacity, start + duration * 0.18, baseOpacity);
      created.push([scale, start, end], [opacity, start, end]);
    } else if (preset === "text-rise") {
      setKey(position, start, offsetPosition(basePosition, 0, comp.height * 0.08));
      setKey(position, end, basePosition);
      setKey(opacity, start, 0);
      setKey(opacity, end, baseOpacity);
      created.push([position, start, end], [opacity, start, end]);
    } else if (preset === "pulse") {
      setKey(scale, start, baseScale);
      setKey(scale, start + duration * 0.5, scaledValue(baseScale, 1.08));
      setKey(scale, end, baseScale);
      created.push([scale, start, end]);
    } else if (preset === "whip-left") {
      setKey(position, start, offsetPosition(basePosition, comp.width * 0.65, 0));
      setKey(position, end, basePosition);
      setKey(rotation, start, baseRotation + 14);
      setKey(rotation, end, baseRotation);
      setKey(opacity, start, 0);
      setKey(opacity, end, baseOpacity);
      created.push([position, start, end], [rotation, start, end], [opacity, start, end]);
    } else if (preset === "whip-right") {
      setKey(position, start, offsetPosition(basePosition, -comp.width * 0.65, 0));
      setKey(position, end, basePosition);
      setKey(rotation, start, baseRotation - 14);
      setKey(rotation, end, baseRotation);
      setKey(opacity, start, 0);
      setKey(opacity, end, baseOpacity);
      created.push([position, start, end], [rotation, start, end], [opacity, start, end]);
    }

    for (var i = 0; i < created.length; i++) {
      easeKeysInRange(created[i][0], created[i][1], created[i][2]);
    }
    return true;
  }

  function animateSelected(preset, label) {
    var comp = activeComp();
    if (!comp) return;
    var layers = selectedLayers(comp);
    if (!layers.length) {
      alert("Select one or more unlocked layers first.");
      return;
    }
    undoGroup(label, function () {
      var applied = 0;
      for (var i = 0; i < layers.length; i++) {
        if (animateLayer(layers[i], comp, preset)) applied++;
      }
      if (!applied) alert("The playhead is outside the selected layers' visible duration.");
    });
  }

  function createNullController() {
    var comp = activeComp();
    if (!comp) return;
    undoGroup("Create 3D Null Controller", function () {
      var controller = comp.layers.addNull();
      controller.name = "DepthVibe Null Controller";
      controller.threeDLayer = true;
      controller.label = 9;
      controller.property("ADBE Transform Group")
        .property("ADBE Position")
        .setValue([comp.width / 2, comp.height / 2, 0]);
      controller.moveToBeginning();
    });
  }

  function parentSelectedToNull() {
    var comp = activeComp();
    if (!comp) return;
    var layers = selectedLayers(comp);
    if (!layers.length) {
      alert("Select the layers you want to parent first.");
      return;
    }
    undoGroup("Create Parent Null", function () {
      var use3D = false;
      for (var i = 0; i < layers.length; i++) {
        if (layers[i].threeDLayer) use3D = true;
      }
      var controller = comp.layers.addNull();
      controller.name = "DepthVibe Parent Controller";
      controller.threeDLayer = use3D;
      controller.label = 9;
      var controllerPosition = [comp.width / 2, comp.height / 2];
      if (use3D) controllerPosition.push(0);
      controller.property("ADBE Transform Group")
        .property("ADBE Position")
        .setValue(controllerPosition);
      controller.moveToBeginning();
      var attached = 0;
      for (var j = 0; j < layers.length; j++) {
        try {
          if (typeof layers[j].setParentWithJump === "function") {
            layers[j].setParentWithJump(controller);
          } else {
            layers[j].parent = controller;
          }
          attached++;
        } catch (_) {}
      }
      if (!attached) alert("No selected layers could be parented.");
    });
  }

  function createAdjustmentLayer() {
    var comp = activeComp();
    if (!comp) return;
    undoGroup("Create Adjustment Layer", function () {
      var layer = comp.layers.addSolid(
        [1, 1, 1], "DepthVibe Adjustment Layer",
        comp.width, comp.height, comp.pixelAspect, comp.duration
      );
      layer.adjustmentLayer = true;
      layer.label = 14;
      layer.moveToBeginning();
    });
  }

  function createCameraRig() {
    var comp = activeComp();
    if (!comp) return;
    undoGroup("Create Camera Rig", function () {
      var controller = comp.layers.addNull();
      controller.name = "DepthVibe Camera Controller";
      controller.threeDLayer = true;
      controller.property("ADBE Transform Group")
        .property("ADBE Position")
        .setValue([comp.width / 2, comp.height / 2, 0]);
      var camera = comp.layers.addCamera(
        "DepthVibe Camera", [comp.width / 2, comp.height / 2]
      );
      camera.parent = controller;
      camera.moveBefore(controller);
      controller.moveToBeginning();
    });
  }

  function createShapeAccent() {
    var comp = activeComp();
    if (!comp) return;
    undoGroup("Create Editable Shape Accent", function () {
      var layer = comp.layers.addShape();
      layer.name = "DepthVibe Rounded Rectangle";
      layer.property("ADBE Transform Group")
        .property("ADBE Position")
        .setValue([comp.width / 2, comp.height / 2]);
      var root = layer.property("ADBE Root Vectors Group");
      var group = root.addProperty("ADBE Vector Group");
      var contents = group.property("ADBE Vectors Group");
      var rectangle = contents.addProperty("ADBE Vector Shape - Rect");
      rectangle.property("ADBE Vector Rect Size")
        .setValue([comp.width * 0.55, comp.height * 0.18]);
      rectangle.property("ADBE Vector Rect Roundness").setValue(28);
      var fill = contents.addProperty("ADBE Vector Graphic - Fill");
      fill.property("ADBE Vector Fill Color").setValue([0.31, 0.36, 0.92]);
      layer.moveToBeginning();
    });
  }

  function createTextLayer(text, make3D, lowerThird) {
    var comp = activeComp();
    if (!comp) return;
    undoGroup(lowerThird ? "Create Editable Lower Third" : "Create Editable Text", function () {
      var layer = comp.layers.addText(text || "DEPTHVIBE TITLE");
      layer.name = lowerThird ? "DepthVibe Lower Third" : "DepthVibe Editable Title";
      if (make3D) layer.threeDLayer = true;
      var group = layer.property("ADBE Text Properties");
      var source = group && group.property("ADBE Text Document");
      if (source) {
        var document = source.value;
        document.fontSize = lowerThird ? 54 : 112;
        document.applyFill = true;
        document.fillColor = [1, 1, 1];
        document.applyStroke = false;
        document.justification = lowerThird
          ? ParagraphJustification.LEFT_JUSTIFY
          : ParagraphJustification.CENTER_JUSTIFY;
        source.setValue(document);
      }
      var textPosition = lowerThird
        ? [comp.width * 0.12, comp.height * 0.82]
        : [comp.width / 2, comp.height / 2];
      if (make3D) textPosition.push(0);
      layer.property("ADBE Transform Group")
        .property("ADBE Position")
        .setValue(textPosition);
      layer.moveToBeginning();
    });
  }

  function addNativeEffect(matchName, title) {
    var comp = activeComp();
    if (!comp) return;
    var layers = selectedLayers(comp);
    if (!layers.length) {
      alert("Select one or more unlocked visual layers first.");
      return;
    }
    undoGroup("Add " + title, function () {
      var added = 0;
      var failures = [];
      for (var i = 0; i < layers.length; i++) {
        try {
          var parade = layers[i].property("ADBE Effect Parade");
          if (!parade) throw new Error("This layer does not support effects.");
          parade.addProperty(matchName);
          added++;
        } catch (error) {
          failures.push(layers[i].name + ": " + error.toString());
        }
      }
      if (failures.length) {
        alert(title + " added to " + added + " layer(s).\n" + failures.join("\n"));
      } else {
        alert(title + " added to " + added + " layer(s).");
      }
    });
  }

  function staggerSelectedLayers() {
    var comp = activeComp();
    if (!comp) return;
    var layers = selectedLayers(comp);
    if (layers.length < 2) {
      alert("Select at least two unlocked layers to stagger.");
      return;
    }
    undoGroup("Stagger Selected Layers", function () {
      var origin = Math.max(comp.time, layers[0].startTime);
      for (var i = 0; i < layers.length; i++) {
        var offset = origin + i * 0.12;
        if (offset < comp.duration) layers[i].startTime = offset;
      }
    });
  }

  function easyEaseSelectedKeys() {
    var comp = activeComp();
    if (!comp) return;
    undoGroup("Easy Ease Selected Keys", function () {
      var layers = selectedLayers(comp);
      var eased = 0;
      for (var i = 0; i < layers.length; i++) {
        var transform = layers[i].property("ADBE Transform Group");
        if (!transform) continue;
        for (var p = 1; p <= transform.numProperties; p++) {
          var property = transform.property(p);
          if (!property || !property.numKeys ||
              typeof property.keySelected !== "function") continue;
          for (var keyIndex = 1; keyIndex <= property.numKeys; keyIndex++) {
            if (!property.keySelected(keyIndex)) continue;
            try {
              var value = property.keyValue(keyIndex);
              var count = value instanceof Array ? value.length : 1;
              var easeIn = [];
              var easeOut = [];
              for (var axis = 0; axis < count; axis++) {
                easeIn.push(new KeyframeEase(0, 70));
                easeOut.push(new KeyframeEase(0, 70));
              }
              property.setTemporalEaseAtKey(keyIndex, easeIn, easeOut);
              property.setTemporalAutoBezierAtKey(keyIndex, true);
              property.setTemporalContinuousAtKey(keyIndex, true);
              eased++;
            } catch (_) {}
          }
        }
      }
      if (!eased) alert("Select one or more transform keyframes first.");
    });
  }

  function panelFor(target) {
    var panel = target instanceof Panel
      ? target
      : new Window("palette", "DepthVibe Motion Tools", undefined, {resizeable:true});
    panel.orientation = "column";
    panel.alignChildren = ["fill", "fill"];
    panel.spacing = 8;
    panel.margins = 12;

    var heading = panel.add("statictext", undefined, "DEPTHVIBE / AFTER EFFECTS TOOLKIT");
    heading.graphics.font = ScriptUI.newFont("Arial", "BOLD", 13);

    var tabs = panel.add("tabbedpanel");
    tabs.alignChildren = ["fill", "top"];
    tabs.preferredSize = [390, 640];

    function makeTab(label) {
      var item = tabs.add("tab", undefined, label);
      item.orientation = "column";
      item.alignChildren = ["fill", "top"];
      item.spacing = 7;
      item.margins = 10;
      return item;
    }

    function addButton(parent, label, action) {
      parent.add("button", undefined, label).onClick = action;
    }

    var layersTab = makeTab("LAYERS");
    addButton(layersTab, "Create 3D Null Controller", createNullController);
    addButton(layersTab, "Parent Selected Layers to Null", parentSelectedToNull);
    addButton(layersTab, "Create Adjustment Layer", createAdjustmentLayer);
    addButton(layersTab, "Create Camera Rig", createCameraRig);
    addButton(layersTab, "Create Editable Shape", createShapeAccent);
    addButton(layersTab, "Create Editable 3D Text", function () {
      createTextLayer("DEPTHVIBE TITLE", true, false);
    });
    addButton(layersTab, "Create Lower Third", function () {
      createTextLayer("HOST NAME\nROLE / TITLE", false, true);
    });

    var effectsTab = makeTab("EFFECTS");
    addButton(effectsTab, "Add Gaussian Blur", function () {
      addNativeEffect("ADBE Gaussian Blur 2", "Gaussian Blur");
    });
    addButton(effectsTab, "Add Glow", function () {
      addNativeEffect("ADBE Glo2", "Glow");
    });
    addButton(effectsTab, "Add Drop Shadow", function () {
      addNativeEffect("ADBE Drop Shadow", "Drop Shadow");
    });
    addButton(effectsTab, "Add Tint", function () {
      addNativeEffect("ADBE Tint", "Tint");
    });
    addButton(effectsTab, "Add Sharpen", function () {
      addNativeEffect("ADBE Sharpen", "Sharpen");
    });
    addButton(effectsTab, "Add Posterize Time", function () {
      addNativeEffect("ADBE Posterize Time", "Posterize Time");
    });
    addButton(effectsTab, "Add Fast Box Blur", function () {
      addNativeEffect("ADBE Box Blur2", "Fast Box Blur");
    });
    addButton(effectsTab, "Add Directional Blur", function () {
      addNativeEffect("ADBE Motion Blur", "Directional Blur");
    });
    addButton(effectsTab, "Add Hue/Saturation", function () {
      addNativeEffect("ADBE HUE SATURATION", "Hue/Saturation");
    });
    addButton(effectsTab, "Add Curves", function () {
      addNativeEffect("ADBE CurvesCustom", "Curves");
    });
    addButton(effectsTab, "Add Levels", function () {
      addNativeEffect("ADBE Easy Levels2", "Levels");
    });
    addButton(effectsTab, "Add Lumetri Color", function () {
      addNativeEffect("ADBE Lumetri", "Lumetri Color");
    });
    addButton(effectsTab, "Add Vibrance", function () {
      addNativeEffect("ADBE Vibrance", "Vibrance");
    });
    addButton(effectsTab, "Add Exposure", function () {
      addNativeEffect("ADBE Exposure2", "Exposure");
    });

    var vfxTab = makeTab("VFX");
    addButton(vfxTab, "Add Fractal Noise", function () {
      addNativeEffect("ADBE Fractal Noise", "Fractal Noise");
    });
    addButton(vfxTab, "Add Turbulent Displace", function () {
      addNativeEffect("ADBE Turbulent Displace", "Turbulent Displace");
    });
    addButton(vfxTab, "Add Wave Warp", function () {
      addNativeEffect("ADBE Wave Warp", "Wave Warp");
    });
    addButton(vfxTab, "Add Displacement Map", function () {
      addNativeEffect("ADBE Displacement Map", "Displacement Map");
    });
    addButton(vfxTab, "Add Optics Compensation", function () {
      addNativeEffect("ADBE Optics Compensation", "Optics Compensation");
    });
    addButton(vfxTab, "Add Echo", function () {
      addNativeEffect("ADBE Echo", "Echo");
    });
    addButton(vfxTab, "Add Pixel Motion Blur", function () {
      addNativeEffect("ADBE OFMotionBlur", "Pixel Motion Blur");
    });
    addButton(vfxTab, "Add Linear Wipe", function () {
      addNativeEffect("ADBE Linear Wipe", "Linear Wipe");
    });
    addButton(vfxTab, "Add Radial Wipe", function () {
      addNativeEffect("ADBE Radial Wipe", "Radial Wipe");
    });
    addButton(vfxTab, "Add Block Dissolve", function () {
      addNativeEffect("ADBE Block Dissolve", "Block Dissolve");
    });
    addButton(vfxTab, "Add 4-Color Gradient", function () {
      addNativeEffect("ADBE 4ColorGradient", "4-Color Gradient");
    });
    addButton(vfxTab, "Add CC Light Sweep", function () {
      addNativeEffect("CC Light Sweep", "CC Light Sweep");
    });

    var motionTab = makeTab("MOTION");
    addButton(motionTab, "Fade In", function () {
      animateSelected("fade-in", "Fade In");
    });
    addButton(motionTab, "Fade Out", function () {
      animateSelected("fade-out", "Fade Out");
    });
    addButton(motionTab, "Fade + Pop", function () {
      animateSelected("fade-pop", "Fade and Pop");
    });
    addButton(motionTab, "Slide Up", function () {
      animateSelected("slide-up", "Slide Up");
    });
    addButton(motionTab, "Slide Left", function () {
      animateSelected("slide-left", "Slide Left");
    });
    addButton(motionTab, "Spin In", function () {
      animateSelected("spin-in", "Spin In");
    });
    addButton(motionTab, "Bounce In", function () {
      animateSelected("bounce-in", "Bounce In");
    });
    addButton(motionTab, "Scale Punch", function () {
      animateSelected("scale-punch", "Scale Punch");
    });
    addButton(motionTab, "Slide Right", function () {
      animateSelected("slide-right", "Slide Right");
    });
    addButton(motionTab, "Slide Down", function () {
      animateSelected("slide-down", "Slide Down");
    });
    addButton(motionTab, "Zoom In", function () {
      animateSelected("zoom-in", "Zoom In");
    });
    addButton(motionTab, "Elastic Pop", function () {
      animateSelected("elastic-pop", "Elastic Pop");
    });
    addButton(motionTab, "Text Rise", function () {
      animateSelected("text-rise", "Text Rise");
    });
    addButton(motionTab, "Pulse", function () {
      animateSelected("pulse", "Pulse");
    });
    addButton(motionTab, "Whip In Left", function () {
      animateSelected("whip-left", "Whip In Left");
    });
    addButton(motionTab, "Whip In Right", function () {
      animateSelected("whip-right", "Whip In Right");
    });
    addButton(motionTab, "Stagger Selected Layers", staggerSelectedLayers);
    addButton(motionTab, "Easy Ease Selected Keys", easyEaseSelectedKeys);

    panel.add("statictext", undefined, "Actions target unlocked layers and support Ctrl/Cmd+Z.");
    panel.preferredSize = [410, 730];
    panel.onResizing = panel.onResize = function () { this.layout.resize(); };
    panel.layout.layout(true);
    return panel;
  }
  var ui = panelFor(thisObj);
  if (ui instanceof Window) {
    ui.center();
    ui.show();
  }
})(this);
