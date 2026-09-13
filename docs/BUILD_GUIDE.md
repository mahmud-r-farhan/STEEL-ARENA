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

## 4. Test Play Release Packaging

To build complete release zip archives containing the `.love` bundle, launch scripts for both **Single-Player (PvE)** and **Local / Dedicated Multiplayer**, and full user documentation:

Use the automated script:
```bash
bash tools/build-release.sh
```

This creates the distribution folder `dist/` with:
- `steel-arena-v1.0.0.love`
- `steel-arena-v1.0.0-dist.zip` (containing the `.love` bundle, `start-solo.sh`, `start-server.sh`, and documentation).

---

## 5. Build Verification Checklist

Before releasing a build, ensure:
1. `love src --selftest` returns exit code `0`.
2. `love src --nettest` returns exit code `0`.
3. The `.love` package launches without missing module errors.
4. Dedicated server mode (`love src --server`) accepts local connections on port `37555`.
