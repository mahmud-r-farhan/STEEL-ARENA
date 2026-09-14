# STEEL ARENA — Build & Packaging Guide

This guide covers building `.love` bundles, packaging standalone executables for Windows and Linux, and building test play release packages for both local multiplayer and single-player modes.

---

## 1. Prerequisites

- **LÖVE 11.5**: Downloaded from [love2d.org](https://love2d.org) or retrieved via `tools/fetch-love.sh`.
- **Zip Utility**: `zip` / `unzip` on Linux/macOS or standard archiving tools on Windows.
- **Bash Shell**: For executing build automation scripts in `tools/`.

---

## 2. Quick Packaging (.love file)

A `.love` file is a ZIP archive containing the contents of the `src/` directory.

### Linux / macOS
```bash
cd src
zip -9 -r ../steel-arena.love . -x ".*"
```

### Windows (PowerShell)
```powershell
Compress-Archive -Path src\* -DestinationPath steel-arena.love -Force
```

### Verification
Run the `.love` bundle directly with LÖVE:
```bash
love steel-arena.love
```

---

## 3. Creating Standalone Executables

### Windows Standalone Executable (.exe)

1. Obtain the official LÖVE 11.5 64-bit release zip (`love-11.5-win64.zip`).
2. Build `steel-arena.love` (as detailed above).
3. Combine `love.exe` and `steel-arena.love` using binary append:
   - **Windows Command Prompt**:
     ```cmd
     copy /b love.exe+steel-arena.love steel-arena.exe
     ```
   - **Linux / Bash**:
     ```bash
     cat love/love.exe steel-arena.love > steel-arena.exe
     ```
4. Package `steel-arena.exe` with the essential LÖVE DLLs (`love.dll`, `lua51.dll`, `mpg123.dll`, `msvcp140.dll`, `vcruntime140.dll`, `OpenAL32.dll`, etc.):
   ```bash
   zip -9 -r steel-arena-win64.zip steel-arena.exe *.dll license.txt
   ```

### Linux Standalone Executable / AppImage

1. Combine the `love` binary with `steel-arena.love`:
   ```bash
   cat /usr/bin/love steel-arena.love > steel-arena-linux
   chmod +x steel-arena-linux
   ```
2. Test execution:
   ```bash
   ./steel-arena-linux
   ```

---

## 4. Multiplatform Release Packaging

To build complete release packages for all supported platforms (**Windows x64**, **Android APK**, **Web HTML5/WASM**, **Linux**, and universal **.love**):

Use the automated script:
```bash
bash tools/build-release.sh 1.0.0
```

This creates the distribution folder `dist/` with:
- `steel-arena-v1.0.0.love` — Universal bundle for macOS, Steam Deck, Linux, or Android
- `steel-arena-v1.0.0-windows-x64.zip` — Standalone Windows 64-bit portable package (`steel-arena.exe`, DLLs, `start-game.bat`, `start-server.bat`)
- `steel-arena-v1.0.0-android.apk` — Standalone signed Android APK
- `steel-arena-v1.0.0-web.zip` — Static HTML5 / WebAssembly web player build
- `steel-arena-v1.0.0-linux.tar.gz` — Linux distribution archive with launcher scripts

---

## 5. GitHub Actions Auto-Release CI/CD

Steel Arena includes an automated CI/CD release pipeline in `.github/workflows/ci.yml`.

### Automated Release on Git Tag
Push any version tag to trigger an automatic release build:
```bash
git tag v1.0.1
git push origin v1.0.1
```
The workflow will:
1. Run syntax verification across all Lua sources.
2. Execute headless verification tests (`--selftest` and `--nettest`).
3. Build all 5 platform release packages.
4. Publish a GitHub Release with auto-generated release notes and attached release binaries.

### Manual Trigger
You can also trigger release builds manually via the GitHub Actions tab (`workflow_dispatch`) with custom version numbers and optional release publishing.

---

## 6. Build Verification Checklist

Before publishing or releasing a build, ensure:
1. `love src --selftest` returns exit code `0`.
2. `love src --nettest` returns exit code `0`.
3. The `.love` package launches without missing module errors.
4. The Windows standalone `steel-arena.exe` boots directly without external dependencies.
5. Dedicated server mode (`love src --server`) accepts local connections on port `37555`.
