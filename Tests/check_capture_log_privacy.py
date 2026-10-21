"""Static guard against leaking window titles in capture-path console messages."""

from pathlib import Path
import re

source = (Path(__file__).resolve().parents[1] / "WindowManager/Services/WindowService.swift").read_text()
capture = source.split("private func getWindowInfo(", 1)[1].split("private func getScreenIndex(", 1)[0]
assert 'print("Skipping window - outside screen bounds' in capture
assert 'print("Captured window on screen' in capture
for call in re.findall(r"\bprint\(.*?\)\s*(?:\n|$)", capture, flags=re.DOTALL):
    assert not re.search(r"\\\(\s*title\s*\)|\\\(\s*appName\s*\)", call), "capture log interpolates a private name"
print("Capture log privacy: static guard passed")
