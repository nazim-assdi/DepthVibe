/*
 * DepthVibe Motion Tools — original After Effects ExtendScript / ScriptUI.
 * Run explicitly via File > Scripts > Run Script File.
 */
(function(thisObj){
  function comp(){var c=app.project&&app.project.activeItem;if(!(c instanceof CompItem)){alert("Select an After Effects composition first.");return null;}return c;}
  function undo(name,fn){app.beginUndoGroup("DepthVibe - "+name);try{fn();}catch(e){alert("DepthVibe: "+e.toString());}finally{app.endUndoGroup();}}
  function selected(c){var a=c.selectedLayers||[],r=[];for(var i=0;i<a.length;i++)if(a[i]&&!a[i].locked)r.push(a[i]);r.sort(function(x,y){return x.index-y.index;});return r;}
  function addNull(){var c=comp();if(!c)return;undo("Create 3D Null",function(){var l=c.layers.addNull();l.name="DepthVibe Null Controller";l.threeDLayer=true;l.label=9;l.moveToBeginning();});}
  function addAdjustment(){var c=comp();if(!c)return;undo("Create Adjustment Layer",function(){var l=c.layers.addSolid([1,1,1],"DepthVibe Adjustment Layer",c.width,c.height,c.pixelAspect,c.duration);l.adjustmentLayer=true;l.label=14;l.moveToBeginning();});}
  function addCameraRig(){var c=comp();if(!c)return;undo("Create Camera Rig",function(){var n=c.layers.addNull();n.name="DepthVibe Camera Controller";n.threeDLayer=true;n.property("ADBE Transform Group").property("ADBE Position").setValue([c.width/2,c.height/2,0]);var cam=c.layers.addCamera("DepthVibe Camera",[c.width/2,c.height/2]);cam.parent=n;cam.moveBefore(n);n.moveToBeginning();});}
  function addText(){var c=comp();if(!c)return;undo("Create Text Layer",function(){var l=c.layers.addText("YOUR TITLE");l.name="DepthVibe Editable Title";l.moveToBeginning();});}
  function easeKeys(p){if(!p||!p.numKeys||typeof p.keySelected!=="function")return;for(var k=1;k<=p.numKeys;k++)if(p.keySelected(k)){try{var v=p.keyValue(k),n=(v instanceof Array)?v.length:1,ins=[],outs=[];for(var d=0;d<n;d++){ins.push(new KeyframeEase(0,70));outs.push(new KeyframeEase(0,70));}p.setTemporalEaseAtKey(k,ins,outs);p.setTemporalAutoBezierAtKey(k,true);p.setTemporalContinuousAtKey(k,true);}catch(_){}}}
  function easyEase(){var c=comp();if(!c)return;undo("Easy Ease Keys",function(){var a=selected(c);for(var i=0;i<a.length;i++){var t=a[i].property("ADBE Transform Group");if(t)for(var p=1;p<=t.numProperties;p++)easeKeys(t.property(p));var es=a[i].property("ADBE Effect Parade");if(es)for(var e=1;e<=es.numProperties;e++){var fx=es.property(e);for(var q=1;q<=fx.numProperties;q++)easeKeys(fx.property(q));}}});}
  function fadePop(){var c=comp();if(!c)return;var a=selected(c);if(!a.length){alert("Select unlocked layers first.");return;}undo("Fade and Pop",function(){for(var i=0;i<a.length;i++){var l=a[i],s=Math.max(c.displayStartTime,l.inPoint),e=Math.min(l.outPoint,s+0.45);if(e<=s)continue;var t=l.property("ADBE Transform Group"),o=t.property("ADBE Opacity"),z=t.property("ADBE Scale"),base=z.value,small=[];for(var d=0;d<base.length;d++)small.push(base[d]*0.72);o.setValueAtTime(s,0);o.setValueAtTime(e,100);z.setValueAtTime(s,small);z.setValueAtTime(e,base);}});}
  function stagger(){var c=comp();if(!c)return;var a=selected(c);if(a.length<2){alert("Select at least two unlocked layers.");return;}undo("Stagger Layers",function(){var s=a[0].startTime;for(var i=0;i<a.length;i++)a[i].startTime=s+i*0.12;});}
  var w=(thisObj instanceof Panel)?thisObj:new Window("palette","DepthVibe Motion Tools",undefined,{resizeable:true});
  w.orientation="column";w.alignChildren=["fill","top"];w.spacing=8;w.margins=12;
  w.add("statictext",undefined,"DEPTHVIBE / AFTER EFFECTS TOOLS");
  w.add("button",undefined,"Create 3D Null Controller").onClick=addNull;
  w.add("button",undefined,"Create Adjustment Layer").onClick=addAdjustment;
  w.add("button",undefined,"Create Camera Rig").onClick=addCameraRig;
  w.add("button",undefined,"Create Editable Text Layer").onClick=addText;
  w.add("button",undefined,"Fade + Pop Selected Layers").onClick=fadePop;
  w.add("button",undefined,"Stagger Selected Layers").onClick=stagger;
  w.add("button",undefined,"Easy Ease Selected Keys").onClick=easyEase;
  w.add("statictext",undefined,"Every operation is click-triggered and undoable.");
  w.onResizing=w.onResize=function(){this.layout.resize();};w.layout.layout(true);if(w instanceof Window){w.center();w.show();}
})(this);
