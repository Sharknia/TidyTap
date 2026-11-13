#!/bin/bash
set -euo pipefail
umask 077

if [[ $# -gt 1 || "${1:-local}" != "local" ]]; then
  echo 'probe-error: invalid-arguments (local only)' >&2
  exit 64
fi

probe_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
python3 - "$probe_repo_root" <<'PY'
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import tempfile

os.umask(0o077)
repo = Path(sys.argv[1])
output = repo / 'build/clipboard-cloudkit-probe'
if (repo / 'build').is_symlink() or output.is_symlink():
    raise SystemExit('probe-error: unsafe-output')
output.mkdir(parents=True, exist_ok=True, mode=0o700)
os.chmod(output, 0o700)
probe = repo / 'Spikes/ClipboardCloudKitProbe'
if plistlib.loads((probe / 'Probe.entitlements').read_bytes()) != {}:
    raise SystemExit('probe-error: restricted-entitlements')
run_root = Path(tempfile.mkdtemp(prefix='run.', dir=output))
summary = {'scope': 'local-only', 'cloudkit': 'not_run', 'run': str(run_root), 'status': 'failed'}

def validate_output_boundary(root, candidate):
    if candidate.is_symlink() or not candidate.resolve().is_relative_to(root.resolve()):
        raise RuntimeError('unsafe-derived-data')

def execute(command, log, seconds):
    with log.open('wb') as stream:
        process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT,
                                   cwd=repo, start_new_session=True)
        try:
            return process.wait(timeout=seconds)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            return 124

try:
    derived = output / 'DerivedData'
    validate_output_boundary(output, derived)
    build_log = run_root / 'build.log'
    status = execute(['xcodebuild', '-quiet', '-project',
        str(probe / 'ClipboardCloudKitProbe.xcodeproj'), '-scheme', 'ClipboardCloudKitProbe',
        '-configuration', 'Debug', '-destination', 'platform=macOS,arch=arm64', '-derivedDataPath', str(derived), 'build'],
        build_log, 180)
    summary['build_exit'] = status
    if status:
        raise RuntimeError('build-failed')
    executable = output / 'DerivedData/Build/Products/Debug/ClipboardCloudKitProbe.app/Contents/MacOS/ClipboardCloudKitProbe'
    # 실행 root는 self-test 시작 전에 비어 있어야 한다.
    evidence = run_root / 'local'
    evidence.mkdir(mode=0o700)
    status = execute([str(executable), 'self-test', str(evidence)], run_root / 'probe.log', 90)
    summary['probe_exit'] = status
    if status:
        raise RuntimeError('probe-failed')
    report = json.loads((evidence / 'results.json').read_text())
    expected = [f'L{i:02d}' for i in range(1, 10)]
    if [r['id'] for r in report['results']] != expected or any(r['status'] != 'passed' for r in report['results']):
        raise RuntimeError('incomplete-results')
    for path in [run_root, *run_root.rglob('*')]:
        info = path.lstat()
        if path.is_symlink() or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise RuntimeError('unsafe-artifact-permissions')
    summary['status'] = 'passed'
    summary['passed'] = expected
except Exception as error:
    summary['error'] = str(error) if isinstance(error, RuntimeError) else type(error).__name__
finally:
    (run_root / 'launcher-summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')

print(json.dumps(summary, ensure_ascii=False, indent=2))
sys.exit(0 if summary['status'] == 'passed' else 1)
PY
