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
- Native Gaussian Blur, Glow, Drop Shadow, Tint, Sharpen and Posterize Time effects
- Editable keyframe presets: Fade In/Out, Fade + Pop, Slide Up/Left, Spin In, Bounce In and Scale Punch
- Layer staggering and Easy Ease for selected transform keys

Effects are added using After Effects' native effect registry. If an effect match name is not available in the installed After Effects version, the script reports the layer/effect error instead of pretending it was added.

## Compatibility and safety

This script targets the ExtendScript host available in After Effects desktop versions. It does not silently execute imported JSX/JSXBIN files, bypass licensing, modify system directories or run third-party presets. Test it on a duplicate project before applying it to production work.

The separate CEP bridge is a metadata-oriented compatibility bridge, not a lossless AEP converter or a full Premiere Pro extension.
