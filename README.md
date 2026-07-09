# Compressor (Native SDK)

Full **native** desktop image compressor — no WebView, no React, no browser UI.

- UI: `src/app.native` (Native markup)
- Logic: `src/main.zig` (`Model` / `Msg` / `update_fx`)
- Encode: **Bun** `Bun.file(…).image().webp({ quality })` via `fx.spawn`

## Features

- Browse (platform file dialog) or drop an image
- Convert any common image → **WebP**
- Quality slider in settings (**default 80%**)
- Presets: Light 90 · Medium 80 · Heavy 50
- Shortcuts: **Ctrl+,** settings · **Ctrl+O** browse · **Ctrl+Enter** compress

## Requirements (Windows native)

Run these on **Windows** (PowerShell / cmd), not WSL.

- [Zig 0.16](https://ziglang.org/download/) (`zig` on `PATH`)
- [Bun](https://bun.sh) 1.4+ on `PATH` (used for compression)
- [@native-sdk/cli](https://www.npmjs.com/package/@native-sdk/cli) (`npm install -g @native-sdk/cli`)
- Node.js (for the Native CLI)

Windows uses the Win32 host with the **software** GPU surface backend.

On high-DPI displays the app opts into **Per-Monitor V2** DPI awareness at startup so the canvas rasterizes at the real device scale (e.g. 1.25× / 1.5× / 2×) instead of letting Windows stretch a 1× bitmap. That is what keeps text and edges sharp.

## Setup

```powershell
# From a Windows shell, in this project directory:
winget install -e --id zig.zig
# Or download Zig 0.16.0 x86_64 Windows zip and add it to PATH.

npm install -g @native-sdk/cli
# Bun: https://bun.sh — then confirm:
zig version
bun --version
native --version
```

## Commands

```powershell
# Validate markup
native check
native markup check src/app.native

# Unit tests (headless)
native test

# Run (native window + hot reload of app.native)
native dev

# Release binary
native build
```

## Bun encoder (CLI)

```powershell
bun run scripts/compress.ts --input photo.png --output photo.webp --quality 80
bun test scripts/compress.test.ts
```

## Project layout

```
app.zon              # app identity, window, shortcuts
src/app.native       # declarative native UI
src/main.zig         # Model / Msg / update_fx / effects
src/tests.zig        # dispatch + markup tests
scripts/compress.ts  # Bun WebP encode
assets/icon.png
```

Zero-config: no `frontend/`, no `build.zig` — the `native` CLI owns the build graph.
