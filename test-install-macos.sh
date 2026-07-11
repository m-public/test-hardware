#!/usr/bin/env sh
# DEPZ hardware test — macOS bootstrap runner.
#
# Hosted as a GitHub release asset with a fixed link. Curl-downloadable:
#   curl -fsSL <repo-url>/releases/latest/download/test-install-macos.sh | sh
#
# Creates an isolated temp dir, downloads + extracts this package archive,
# downloads + runs the REAL DEPZ autoinstaller (the system under test — it
# detects hardware and installs the right SDK extras into a venv), installs
# this package into that venv, runs the probe + pipeline smoke test against
# sample.mkv, prints the transcript JSON to stdout, and cleans up.
# Nothing touches ~. No source/repo assumed on the host.
#
#   Options:
#     --keep          Retain the temp dir + transcript for debugging.
#     --no-pipeline   Probe only; skip the pipeline smoke run.
set -u

# ── fixed URLs (GitHub release assets) ───────────────────────────────────
PACKAGE_URL="https://raw.githubusercontent.com/m-public/test-hardware/main/depz-hardware-test.zip"
AUTOINSTALLER_URL="https://github.com/depz-ai/depz-cython-releases/releases/latest/download/Install-CameraViewer-macOS.sh"

# ── parse args ───────────────────────────────────────────────────────────
KEEP=0
NO_PIPELINE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --keep) KEEP=1 ;;
    --no-pipeline) NO_PIPELINE=1 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

# ── temp dir (cleaned on exit unless --keep) ───────────────────────────
RUN_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t depz-ht)"
export HOME="$RUN_DIR"          # redirects autoinstaller's APP_DIR + uv caches
PKG_DIR="$RUN_DIR/pkg"
TRANSCRIPT="$RUN_DIR/transcript.json"
LOG="$RUN_DIR/install-test.log"
: > "$LOG"

cleanup() {
  if [ "$KEEP" = "1" ]; then
    echo "[runner] keeping temp dir: $RUN_DIR" >&2
    echo "[runner] transcript:      $TRANSCRIPT" >&2
    echo "[runner] log:             $LOG" >&2
  else
    rm -rf "$RUN_DIR"
  fi
}
trap cleanup EXIT INT TERM

echo "[runner] run dir: $RUN_DIR" >&2
echo "[runner] host: $(uname -s)/$(uname -m)" >&2

# ── step 1: download + extract the package archive ─────────────────────
echo "[runner] downloading package archive…" >&2
mkdir -p "$PKG_DIR"
ARCHIVE="$RUN_DIR/depz-hardware-test.zip"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$PACKAGE_URL" -o "$ARCHIVE" || { echo "[runner] download failed" >&2; exit 3; }
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$ARCHIVE" "$PACKAGE_URL" || { echo "[runner] download failed" >&2; exit 3; }
else
  echo "[runner] need curl or wget" >&2; exit 3
fi

echo "[runner] extracting package…" >&2
if command -v unzip >/dev/null 2>&1; then
  unzip -q "$ARCHIVE" -d "$PKG_DIR" || { echo "[runner] unzip failed" >&2; exit 3; }
else
  python3 -c "import zipfile; zipfile.ZipFile('$ARCHIVE').extractall('$PKG_DIR')" || \
    { echo "[runner] extract failed (need unzip or python3)" >&2; exit 3; }
fi
# The archive may contain a top-level dir; find the one with pyproject.toml.
PKG_ROOT="$(find "$PKG_DIR" -name pyproject.toml -maxdepth 2 -print -quit)"
PKG_ROOT="$(dirname "$PKG_ROOT")"
SAMPLE_MKV="$PKG_ROOT/sample.mkv"

# ── step 2: download + run the REAL autoinstaller ──────────────────────
AUTOINSTALLER_SCRIPT="$RUN_DIR/autoinstaller.sh"
echo "[runner] downloading autoinstaller: $AUTOINSTALLER_URL" >&2
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$AUTOINSTALLER_URL" -o "$AUTOINSTALLER_SCRIPT" || { echo "[runner] download failed" >&2; exit 3; }
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$AUTOINSTALLER_SCRIPT" "$AUTOINSTALLER_URL" || { echo "[runner] download failed" >&2; exit 3; }
fi

# macOS autoinstaller puts the venv at $HOME/Library/Application Support/DepzCameraViewer/venv/
VENV_PY="$RUN_DIR/Library/Application Support/DepzCameraViewer/venv/bin/python"
echo "[runner] running autoinstaller (hardware=auto)…" >&2
sh "$AUTOINSTALLER_SCRIPT" --hardware auto >>"$LOG" 2>&1
if [ ! -x "$VENV_PY" ]; then
  echo "[runner] autoinstaller did not produce venv python at $VENV_PY" >&2
  echo "[runner] see $LOG" >&2
  exit 4
fi

# ── step 3: install this package from the extracted archive ───────────
echo "[runner] pip install depz-hardware-test (from archive)…" >&2
# The autoinstaller's venv (uv venv) has no pip module — use uv pip install
# when available, else ensure pip is bootstrapped.
if command -v uv >/dev/null 2>&1; then
  uv pip install --python "$VENV_PY" --quiet "$PKG_ROOT" >>"$LOG" 2>&1 || {
    echo "[runner] package install failed; see $LOG" >&2
    exit 5
  }
else
  "$VENV_PY" -m ensurepip --quiet >>"$LOG" 2>&1 || true
  "$VENV_PY" -m pip install --quiet "$PKG_ROOT" >>"$LOG" 2>&1 || {
    echo "[runner] package install failed; see $LOG" >&2
    exit 5
  }
fi

# ── step 4: run the probe + pipeline smoke test ────────────────────────
EXTRA_FLAGS="--mkv $SAMPLE_MKV"
[ "$NO_PIPELINE" = "1" ] && EXTRA_FLAGS="--no-pipeline"
echo "[runner] running python -m depz_hardware_test…" >&2
"$VENV_PY" -m depz_hardware_test $EXTRA_FLAGS --out "$TRANSCRIPT" --summary >>"$LOG" 2>&1
RC=$?

# ── step 5: (deferred) submit transcript ───────────────────────────────
echo "[runner] transcript: $TRANSCRIPT" >&2
echo "[runner] (transcript submission is deferred — not yet implemented)" >&2

# ── step 6: print transcript JSON to stdout ────────────────────────────
if [ -f "$TRANSCRIPT" ]; then
  cat "$TRANSCRIPT"
else
  echo "[runner] no transcript produced — see $LOG" >&2
  exit 6
fi

exit $RC
