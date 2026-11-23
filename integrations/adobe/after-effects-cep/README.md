# DepthVibe Motion Tools for After Effects

This is an original ExtendScript / ScriptUI palette for After Effects. It is not a repackaged Motion Bro or Mister Horse extension and does not include commercial scripts, plug-in binaries, .ffx files or .mogrt templates.

## Install and run

1. Open After Effects and a project with an active composition.
2. Choose File > Scripts > Run Script File.
3. Select DepthVibe_Motion_Tools.jsx.
4. Use the palette buttons. Every action is explicit and grouped into an After Effects undo step.

## Included tools

- 3D Null creation and parenting selected layers to a Null controller
- Adjustment Layer, Camera Rig, editable Shape, editable 3D Text and Lower Third creation
- Native AE effect actions in separate EFFECTS and VFX tabs: Gaussian/Box/Directional Blur, Glow, Drop Shadow, Tint, Sharpen, Posterize Time, Hue/Saturation, Curves, Levels, Lumetri, Vibrance, Exposure, Fractal Noise, Turbulent Displace, Wave Warp, Displacement Map, Optics Compensation, Echo, Pixel Motion Blur, Linear/Radial Wipe, Block Dissolve, 4-Color Gradient and CC Light Sweep
- Editable keyframe presets: Fade In/Out, Fade + Pop, Slide Up/Down/Left/Right, Spin In, Bounce In, Scale Punch, Zoom In, Elastic Pop, Text Rise, Pulse and Whip In
- Timeline tools: sequence selected layers at the playhead with configurable gap, trim in/out to playhead, split selected layers at playhead, add composition/layer markers
- 2D layout tools: centre the visible bounds and distribute visible centres horizontally/vertically for unparented 2D layers
- Layer staggering and Easy Ease for selected transform keys

Effects are added using After Effects' native effect registry. If an effect match name is not available in the installed After Effects version, the script reports the layer/effect error instead of pretending it was added.

## Compatibility and safety

This script targets the ExtendScript host available in After Effects desktop versions. It does not silently execute imported JSX/JSXBIN files, bypass licensing, modify system directories or run third-party presets. Test it on a duplicate project before applying it to production work.

The separate CEP bridge is a metadata-oriented compatibility bridge, not a lossless AEP converter or a full Premiere Pro extension.
