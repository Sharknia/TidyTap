"""Shared, declarative Finder layout for TidyTap installer disk images."""

from pathlib import Path


def required_path(name: str) -> str:
    value = defines.get(name)  # Provided by dmgbuild's -D key=value option.
    if not value:
        raise RuntimeError(f"Missing dmgbuild define: {name}")
    path = Path(value).resolve()
    if not path.exists():
        raise RuntimeError(f"dmgbuild define does not exist: {name}={path}")
    return str(path)


app_path = required_path("app_path")
background_path = required_path("background_path")

# Only these two entries are visible in Finder. dmgbuild carries the TIFF as a
# dotfile, which Finder already hides; adding a synthetic .background path would
# make dmgbuild try to hide a file that does not exist.
files = [(app_path, "TidyTap.app")]
symlinks = {"Applications": "/Applications"}
hide_extensions = ["TidyTap.app"]

format = "UDZO"
filesystem = "HFS+"
background = background_path
window_rect = ((100, 100), (640, 400))
default_view = "icon-view"
show_status_bar = False
show_toolbar = False
show_sidebar = False
show_pathbar = False
show_tab_view = False
include_icon_view_settings = True
icon_size = 112
icon_locations = {
    "TidyTap.app": (170, 200),
    "Applications": (470, 200),
}
