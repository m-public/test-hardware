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
