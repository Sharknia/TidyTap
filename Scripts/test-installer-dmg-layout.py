#!/usr/bin/env python3
"""Exercise the data that dmgbuild writes into Finder's .DS_Store metadata."""

from pathlib import Path
import runpy
import sys
import tempfile


project_root = Path(__file__).resolve().parent.parent
settings = project_root / "Scripts" / "dmgbuild-settings.py"
with tempfile.TemporaryDirectory(prefix="tidytap-dmg-layout-") as directory:
    root = Path(directory)
    app = root / "TidyTap.app"
    app.mkdir()
    background = root / "DMGBackground.tiff"
    background.write_bytes(b"fixture")
    layout = runpy.run_path(
        str(settings),
        init_globals={"defines": {"app_path": str(app), "background_path": str(background)}},
    )

assert layout["files"] == [(str(app.resolve()), "TidyTap.app")]
assert layout["symlinks"] == {"Applications": "/Applications"}
assert "hide" not in layout
assert layout["hide_extensions"] == ["TidyTap.app"]
assert layout["format"] == "UDZO"
assert layout["filesystem"] == "HFS+"
assert layout["background"] == str(background.resolve())
assert layout["window_rect"][1] == (640, 400)
assert layout["default_view"] == "icon-view"
assert layout["icon_size"] == 112
assert layout["icon_locations"] == {"TidyTap.app": (170, 200), "Applications": (470, 200)}
for key in ("show_status_bar", "show_toolbar", "show_sidebar", "show_pathbar", "show_tab_view"):
    assert layout[key] is False

print("Installer DMG Finder metadata settings checks passed.")
