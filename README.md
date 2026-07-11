# test-hardware

Public download endpoint (bucket) for the DEPZ hardware-test harness.
No source code lives here — only the release assets below.

## Fixed download links

| File | URL |
|---|---|
| Linux runner | `https://raw.githubusercontent.com/m-public/test-hardware/main/test-install-linux.sh` |
| macOS runner | `https://raw.githubusercontent.com/m-public/test-hardware/main/test-install-macos.sh` |
| Windows runner | `https://raw.githubusercontent.com/m-public/test-hardware/main/test-install-windows.ps1` |
| Package archive | `https://raw.githubusercontent.com/m-public/test-hardware/main/depz-hardware-test.zip` |

## Usage

**Linux:**
```sh
curl -fsSL https://raw.githubusercontent.com/m-public/test-hardware/main/test-install-linux.sh | sh
```

**macOS:**
```sh
curl -fsSL https://raw.githubusercontent.com/m-public/test-hardware/main/test-install-macos.sh | sh
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/m-public/test-hardware/main/test-install-windows.ps1 | iex
```

Each runner downloads the package archive + the real DEPZ autoinstaller,
builds an isolated temp venv, runs the hardware probe + pipeline smoke test,
and prints a structured JSON transcript to stdout.

### Where the transcript lands

The transcript JSON is written to the **launch directory** (where you ran
`curl | sh`) unless overridden with `--out-dir DIR` (Linux/macOS) /
`-OutDir DIR` (Windows). The runner resolves this to an absolute path *before*
isolating `$HOME`, so it never ends up in the scratch temp dir. The resolved
path is printed as `[runner] transcript -> <abs path>`.

```sh
# write the transcript to a specific dir
curl -fsSL <linux-url> | sh -s -- --out-dir ~/depz-results
```

### Runner provenance

The transcript carries a `runner` block recording exactly which scripts ran:

```json
"runner": {
  "autoinstaller_url": "https://github.com/depz-ai/depz-cython-releases/...",
  "package_url":       "https://raw.githubusercontent.com/m-public/test-hardware/main/depz-hardware-test.zip",
  "runner_url":        "https://raw.githubusercontent.com/m-public/test-hardware/main/test-install-linux.sh"
}
```
