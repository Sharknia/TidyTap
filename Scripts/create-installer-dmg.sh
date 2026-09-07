#!/bin/zsh
# Build a conventional, styled Finder installer image without Finder scripting.
set -euo pipefail

project_root="${0:A:h:h}"
requirements="$project_root/Scripts/dmgbuild-requirements.txt"
venv="$project_root/build/.dmgbuild-venv"

usage() {
  print -u2 -- "Usage: ${0:t} --source-directory directory --app path/to/TidyTap.app --volume-name name --output path/to/TidyTap.dmg"
}

source_directory=""
app_path=""
volume_name=""
output_path=""
while (( $# > 0 )); do
  case "$1" in
    --source-directory) source_directory="${2:-}"; shift 2 ;;
    --app) app_path="${2:-}"; shift 2 ;;
    --volume-name) volume_name="${2:-}"; shift 2 ;;
    --output) output_path="${2:-}"; shift 2 ;;
    *) usage; exit 2 ;;
  esac
done

if [[ -z "$source_directory" || -z "$app_path" || -z "$volume_name" || -z "$output_path" ]]; then
  usage
  exit 2
fi

source_directory="${source_directory:A}"
app_path="${app_path:A}"
output_path="${output_path:A}"
settings="$source_directory/Scripts/dmgbuild-settings.py"
background="$source_directory/Resources/DMGBackground.tiff"

if [[ ! -d "$source_directory" || ! -f "$settings" || ! -f "$background" ]]; then
  print -u2 -- "Installer source directory must contain Scripts/dmgbuild-settings.py and Resources/DMGBackground.tiff."
  exit 2
fi
if [[ ! -d "$app_path" || "${app_path:t}" != "TidyTap.app" ]]; then
  print -u2 -- "Installer app must be a TidyTap.app bundle."
  exit 2
fi

python_candidates=()
if [[ -x "$venv/bin/python" ]]; then
  python_candidates+=("$venv/bin/python")
fi
if [[ -n "${TIDYTAP_DMG_PYTHON:-}" ]]; then
  python_candidates+=("$TIDYTAP_DMG_PYTHON")
fi
python_candidates+=(python3.15 python3.14 python3.13 python3.12 python3.11 python3.10 python3)
python=""
incompatible_python=""
for candidate in "${python_candidates[@]}"; do
  candidate_path=$(command -v "$candidate" 2>/dev/null || true)
  [[ -n "$candidate_path" ]] || continue
  if "$candidate_path" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)'; then
    python="$candidate_path"
    break
  fi
  [[ -z "$incompatible_python" ]] && incompatible_python="$candidate_path"
done
if [[ -z "$python" ]]; then
  found_version="none"
  [[ -n "$incompatible_python" ]] && found_version=$("$incompatible_python" --version 2>&1)
  print -u2 -- "dmgbuild 1.6.7 requires Python 3.10 or newer; found $found_version. Install a compatible Python, then rerun (the script never installs packages globally)."
  exit 2
fi

if [[ -x "$venv/bin/python" ]]; then
  if ! "$venv/bin/python" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)'; then
    print -u2 -- "Existing build-only venv uses an unsupported Python. Remove build/.dmgbuild-venv and rerun with Python 3.10 or newer."
    exit 2
  fi
else
  mkdir -p "${venv:h}"
  "$python" -m venv "$venv"
fi

installed_version=$("$venv/bin/python" -c 'import importlib.metadata as m; print(m.version("dmgbuild"))' 2>/dev/null || true)
if [[ "$installed_version" != "1.6.7" ]]; then
  "$venv/bin/python" -m pip install --disable-pip-version-check --no-input --index-url https://pypi.org/simple -r "$requirements"
fi

mkdir -p "${output_path:h}"
exec "$venv/bin/dmgbuild" -s "$settings" \
  -D "app_path=$app_path" \
  -D "background_path=$background" \
  "$volume_name" "$output_path"
