from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]

def update_plist(path: Path, values: dict[str, str]) -> None:
    if not path.exists():
        return
    tree = ET.parse(path)
    root = tree.getroot()
    dictionary = root.find("dict") if root.tag == "plist" else root
    if dictionary is None or dictionary.tag != "dict":
        raise ValueError(f"{path} does not contain a plist dictionary")
    children = list(dictionary)
    entries = {}
    for index in range(0, len(children), 2):
        if index + 1 < len(children) and children[index].tag == "key":
            entries[children[index].text or ""] = children[index + 1]
    for key, value in values.items():
        if key in entries:
            entries[key].text = value
        else:
            key_node = ET.Element("key")
            key_node.text = key
            value_node = ET.Element("string")
            value_node.text = value
            dictionary.extend([key_node, value_node])
    tree.write(path, encoding="utf-8", xml_declaration=True)

def replace_min_sdk(path: Path) -> None:
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 26", text)
    text = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 26", text)
    path.write_text(text, encoding="utf-8")

def add_android_gallery_permission(path: Path) -> None:
    if not path.exists():
        return
    android_ns = "http://schemas.android.com/apk/res/android"
    tools_ns = "http://schemas.android.com/tools"
    ET.register_namespace("android", android_ns)
    ET.register_namespace("tools", tools_ns)
    tree = ET.parse(path)
    root = tree.getroot()
    existing = {
        node.get(f"{{{android_ns}}}name")
        for node in root.findall("uses-permission")
    }
    permission = "android.permission.WRITE_EXTERNAL_STORAGE"
    if permission not in existing:
        ET.SubElement(root, "uses-permission", {
            f"{{{android_ns}}}name": permission,
            f"{{{android_ns}}}maxSdkVersion": "28",
            f"{{{tools_ns}}}ignore": "ScopedStorage",
        })
    tree.write(path, encoding="utf-8", xml_declaration=True)

def replace_deployment_target(path: Path, platform: str, version: str) -> None:
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    if platform == "ios":
        text = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", f"IPHONEOS_DEPLOYMENT_TARGET = {version};", text)
    else:
        text = re.sub(r"MACOSX_DEPLOYMENT_TARGET = [0-9.]+;", f"MACOSX_DEPLOYMENT_TARGET = {version};", text)
    path.write_text(text, encoding="utf-8")

def add_camera_compile_dependency(path: Path) -> None:
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    if "androidx.concurrent:concurrent-futures:1.2.0" in text:
        return
    if path.name.endswith(".kts"):
        block = """
subprojects {
    if (name == "camera_android_camerax") {
        dependencies {
            add("implementation", "androidx.concurrent:concurrent-futures:1.2.0")
        }
    }
}
"""
    else:
        block = """
subprojects {
    if (name == 'camera_android_camerax') {
        dependencies {
            implementation 'androidx.concurrent:concurrent-futures:1.2.0'
        }
    }
}
"""
    path.write_text(text.rstrip() + "\n" + block, encoding="utf-8")

def add_camera_entitlements(path: Path) -> None:
    if not path.exists():
        return
    tree = ET.parse(path)
    root = tree.getroot()
    keys = {node.text for node in root.findall("key")}
    for key in ("com.apple.security.device.camera", "com.apple.security.device.audio-input"):
        if key not in keys:
            key_node = ET.Element("key")
            key_node.text = key
            value_node = ET.Element("true")
            root.extend([key_node, value_node])
    tree.write(path, encoding="utf-8", xml_declaration=True)

replace_min_sdk(ROOT / "android/app/build.gradle.kts")
add_camera_compile_dependency(ROOT / "android/build.gradle.kts")
add_camera_compile_dependency(ROOT / "android/build.gradle")
replace_min_sdk(ROOT / "android/app/build.gradle")
add_android_gallery_permission(ROOT / "android/app/src/main/AndroidManifest.xml")
update_plist(ROOT / "ios/Runner/Info.plist", {
    "NSCameraUsageDescription": "DepthVibe uses your camera to record video for editing.",
    "NSMicrophoneUsageDescription": "DepthVibe uses your microphone to record audio with video.",
    "NSPhotoLibraryUsageDescription": "DepthVibe needs access to import videos from your library.",
    "NSPhotoLibraryAddUsageDescription": "DepthVibe saves exported videos to your Photos library.",
})
update_plist(ROOT / "macos/Runner/Info.plist", {
    "NSCameraUsageDescription": "DepthVibe uses your camera to record video for editing.",
    "NSMicrophoneUsageDescription": "DepthVibe uses your microphone to record audio with video.",
})
for name in ("DebugProfile.entitlements", "DebugProfile.entitlements", "Release.entitlements"):
    add_camera_entitlements(ROOT / "macos/Runner/" / name)
replace_deployment_target(ROOT / "ios/Runner.xcodeproj/project.pbxproj", "ios", "14.0")
replace_deployment_target(ROOT / "macos/Runner.xcodeproj/project.pbxproj", "macos", "13.0")
