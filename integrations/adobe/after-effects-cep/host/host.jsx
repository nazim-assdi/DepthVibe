// CEP host-side script entry. Adobe DOM calls belong in this host runtime.
function depthVibeGetHostInfo() {
  return {
    hostApplication: "Adobe CEP host",
    jsxEngine: "ExtendScript",
    bridge: "DepthVibe local loopback bridge"
  };
}