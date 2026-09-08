#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:?usage: generate-appcast.sh <version> [github-release-tag]}"
TAG="${2:-v$VERSION}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/docs}"
ZIP="$ROOT_DIR/dist/WindowManager-${VERSION}.zip"
APP="$ROOT_DIR/dist/WindowManager.app"
APPCAST="$OUTPUT_DIR/appcast.xml"

[[ -f "$ZIP" ]] || { echo "missing $ZIP — run scripts/build-release.sh first" >&2; exit 1; }
[[ -d "$APP" ]] || { echo "missing $APP — run scripts/build-release.sh first" >&2; exit 1; }
mkdir -p "$OUTPUT_DIR"

SIGN_UPDATE="$(find "$HOME/Library/Developer/Xcode/DerivedData" -type f -perm +111 -name sign_update 2>/dev/null | head -1 || true)"
[[ -x "$SIGN_UPDATE" ]] || {
  echo "sign_update not found — run xcodebuild -resolvePackageDependencies first" >&2
  exit 1
}

BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist" 2>/dev/null || printf '26.2')"
[[ "$PLIST_VERSION" == "$VERSION" ]] || { echo "version mismatch: requested $VERSION, built $PLIST_VERSION" >&2; exit 1; }

DOWNLOAD_URL="https://github.com/DdemiurgeE/WindowManager/releases/download/${TAG}/WindowManager-${VERSION}.zip"
ENCLOSURE_ATTRS="$("$SIGN_UPDATE" "$ZIP")"
PUB_DATE="$(date -u +"%a, %d %b %Y %H:%M:%S +0000")"

python3 - "$APPCAST" "$VERSION" "$BUILD" "$MIN_OS" "$DOWNLOAD_URL" "$ENCLOSURE_ATTRS" "$PUB_DATE" <<'PY'
import re
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

path, version, build, min_os, url, attrs_text, pub_date = sys.argv[1:]
ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", ns)
if path.exists():
    tree = ET.parse(path)
    root = tree.getroot()
    channel = root.find("channel")
else:
    root = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = "WindowManager Changelog"
    ET.SubElement(channel, "link").text = "https://ddemiurgee.github.io/WindowManager/appcast.xml"
    ET.SubElement(channel, "description").text = "WindowManager updates."
    tree = ET.ElementTree(root)

for item in list(channel.findall("item")):
    value = item.find(f"{{{ns}}}shortVersionString")
    if value is not None and value.text == version:
        channel.remove(item)

item = ET.Element("item")
ET.SubElement(item, "title").text = f"Version {version}"
ET.SubElement(item, "pubDate").text = pub_date
ET.SubElement(item, f"{{{ns}}}version").text = build
ET.SubElement(item, f"{{{ns}}}shortVersionString").text = version
ET.SubElement(item, f"{{{ns}}}minimumSystemVersion").text = min_os
enclosure = ET.SubElement(item, "enclosure", {"url": url, "type": "application/octet-stream"})
for key, value in re.findall(r'([\w:]+)="([^"]*)"', attrs_text):
    enclosure.set(key, value)

old = channel.findall("item")
for existing in old:
    channel.remove(existing)
channel.append(item)
for existing in old:
    channel.append(existing)
ET.indent(tree, space="    ")
tree.write(path, encoding="utf-8", xml_declaration=True)
print(f"Updated {path} with version {version} (build {build}).")
PY