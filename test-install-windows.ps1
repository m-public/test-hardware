# DEPZ hardware test — Windows bootstrap runner.
#
# Hosted as a GitHub release asset with a fixed link. Curl-downloadable:
#   irm <repo-url>/releases/latest/download/test-install-windows.ps1 | iex
#
# Creates an isolated temp dir, downloads + extracts this package archive,
# downloads + runs the REAL DEPZ autoinstaller (the system under test — it
# detects hardware and installs the right SDK extras into a venv), installs
# this package into that venv, runs the probe + pipeline smoke test against
# sample.mkv, prints the transcript JSON to stdout, and cleans up.
# Nothing touches the user profile. No source/repo assumed on the host.
#
#   Options:
#     -OutDir DIR    Write transcript JSON to DIR (default: launch dir).
#     -Keep          Retain the temp dir + transcript for debugging.
#     -NoPipeline    Probe only; skip the pipeline smoke run.
[CmdletBinding()]
param(
  [switch]$Keep,
  [switch]$NoPipeline,
  [string]$OutDir
)

$ErrorActionPreference = "Stop"

# ── fixed URLs (GitHub release assets) ───────────────────────────────────
$PackageUrl = "https://raw.githubusercontent.com/m-public/test-hardware/main/depz-hardware-test.zip"
$AutoinstallerUrl = "https://github.com/depz-ai/depz-cython-releases/releases/latest/download/Install-CameraViewer-Windows.ps1"
$RunnerUrl = "https://raw.githubusercontent.com/m-public/test-hardware/main/test-install-windows.ps1"

# Capture the launch dir *now* — before we redirect LOCALAPPDATA/USERPROFILE —
# so the transcript lands where the user actually ran us, not in a scratch dir.
$LaunchDir = (Get-Location).Path
if (-not $OutDir) { $OutDir = $LaunchDir }
if (-not (Test-Path $OutDir -PathType Container)) {
  Write-Error "[runner] -OutDir does not exist: $OutDir"; exit 2
}
$Transcript = Join-Path $OutDir "depz-hardware-transcript.json"
Write-Host "[runner] launch dir:    $LaunchDir"
Write-Host "[runner] transcript ->  $Transcript"
Write-Host "[runner] runner URL:    $RunnerUrl"
Write-Host "[runner] package URL:   $PackageUrl"

# ── temp dir (cleaned on exit unless -Keep) ───────────────────────────
$RunDir = Join-Path ([System.IO.Path]::GetTempPath()) ("depz-ht-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
# Redirect everything into the temp dir — nothing touches the user profile.
$env:LOCALAPPDATA = $RunDir
$env:USERPROFILE = $RunDir
$PkgDir = Join-Path $RunDir "pkg"
$Log = Join-Path $RunDir "install-test.log"
"" | Out-File -FilePath $Log

try {
  Write-Host "[runner] run dir: $RunDir"
  Write-Host "[runner] host: Windows/$env:PROCESSOR_ARCHITECTURE"

  # ── step 1: download + extract the package archive ────────────────────
  Write-Host "[runner] downloading package archive..."
  New-Item -ItemType Directory -Path $PkgDir -Force | Out-Null
  $Archive = Join-Path $RunDir "depz-hardware-test.zip"
  Invoke-WebRequest -Uri $PackageUrl -OutFile $Archive -UseBasicParsing

  Write-Host "[runner] extracting package..."
  Expand-Archive -Path $Archive -DestinationPath $PkgDir -Force
  # The archive may contain a top-level dir; find the one with pyproject.toml.
  $Pyproject = Get-ChildItem -Path $PkgDir -Filter "pyproject.toml" -Recurse | Select-Object -First 1
  $PkgRoot = Split-Path -Parent $Pyproject.FullName
  $SampleMkv = Join-Path $PkgRoot "sample.mkv"

  # ── step 2: download + run the REAL autoinstaller ─────────────────────
  $AutoinstallerScript = Join-Path $RunDir "autoinstaller.ps1"
  Write-Host "[runner] downloading autoinstaller: $AutoinstallerUrl"
  Invoke-WebRequest -Uri $AutoinstallerUrl -OutFile $AutoinstallerScript -UseBasicParsing

  $VenvPy = Join-Path $RunDir "DepzCameraViewer\venv\Scripts\python.exe"
  Write-Host "[runner] autoinstaller URL: $AutoinstallerUrl"
  Write-Host "[runner] running autoinstaller (hardware=auto) — forwarding output:"
  Write-Host "──────────────────────────────────────────────────────────"
  & powershell -ExecutionPolicy Bypass -File $AutoinstallerScript --hardware auto *>&1 |
    Tee-Object -FilePath $Log -Append
  $AutoinstallerRc = $LASTEXITCODE
  Write-Host "──────────────────────────────────────────────────────────"
  Write-Host "[runner] autoinstaller exited with code $AutoinstallerRc"
  if (-not (Test-Path $VenvPy)) {
    Write-Error "[runner] autoinstaller did not produce venv python at $VenvPy"
    Write-Error "[runner] see $Log"
    exit 4
  }

  # ── step 3: install this package from the extracted archive ─────────
  Write-Host "[runner] pip install depz-hardware-test (from archive)…"
  # The autoinstaller's venv (uv venv) has no pip module — use uv pip install
  # when available, else ensure pip is bootstrapped.
  if (Get-Command uv -ErrorAction SilentlyContinue) {
    & uv pip install --python $VenvPy --quiet $PkgRoot *>&1 | Tee-Object -FilePath $Log -Append
    if ($LASTEXITCODE -ne 0) {
      Write-Error "[runner] package install failed; see $Log"
      exit 5
    }
  } else {
    & $VenvPy -m ensurepip --quiet *>&1 | Tee-Object -FilePath $Log -Append
    & $VenvPy -m pip install --quiet $PkgRoot *>&1 | Tee-Object -FilePath $Log -Append
    if ($LASTEXITCODE -ne 0) {
      Write-Error "[runner] package install failed; see $Log"
      exit 5
    }
  }

  # ── step 4: run the probe + pipeline smoke test ──────────────────────
  $extraArgs = @("--out", $Transcript, "--summary")
  if (-not $NoPipeline -and (Test-Path $SampleMkv)) {
    $extraArgs += @("--mkv", $SampleMkv)
  } elseif ($NoPipeline) {
    $extraArgs += "--no-pipeline"
  }

  Write-Host "[runner] running python -m depz_hardware_test..."
  & $VenvPy -m depz_hardware_test @extraArgs *>&1 | Tee-Object -FilePath $Log -Append
  $rc = $LASTEXITCODE

  # ── step 5: stamp runner provenance into the transcript JSON ───────────
  # The python module doesn't know which autoinstaller/runner ran it, so we
  # inject a `runner` block here. The transcript already lives at $Transcript
  # (the user's -OutDir), so this both records the URLs and is the final copy.
  if (Test-Path $Transcript) {
    $ProvenancePy = Join-Path $RunDir "stamp_provenance.py"
    @'
import json, sys
p, ai, pkg, run = sys.argv[1:5]
d = json.load(open(p, encoding='utf-8'))
d['runner'] = {'autoinstaller_url': ai, 'package_url': pkg, 'runner_url': run}
open(p, 'w', encoding='utf-8').write(json.dumps(d, indent=2, default=str))
'@ | Out-File -FilePath $ProvenancePy -Encoding utf8
    & $VenvPy $ProvenancePy $Transcript $AutoinstallerUrl $PackageUrl $RunnerUrl *>&1 |
      Tee-Object -FilePath $Log -Append
    if ($LASTEXITCODE -ne 0) {
      Write-Host "[runner] warning: could not stamp provenance into transcript"
    }
    Write-Host "[runner] transcript saved to: $Transcript"
    Write-Host "[runner] autoinstaller URL: $AutoinstallerUrl"
    Write-Host "[runner] (transcript submission deferred - JSON saved locally instead)"
  } else {
    Write-Error "[runner] no transcript produced - see $Log"
    exit 6
  }

  # ── step 6: print transcript JSON to stdout ──────────────────────────
  Get-Content $Transcript
  exit $rc
}
finally {
  if ($Keep) {
    Write-Host "[runner] keeping temp dir: $RunDir"
    Write-Host "[runner] transcript:      $Transcript"
    Write-Host "[runner] log:             $Log"
  } else {
    Remove-Item -Recurse -Force $RunDir -ErrorAction SilentlyContinue
  }
}
