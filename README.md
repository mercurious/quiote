# Quiote

Quiote is Donkey's branch: where Donkey sets up a web browser for browsing on
a ROCKNIX handheld, Quiote sets up the Chrome web browser to run WebGPU apps,
with WebGPU on the device's own Vulkan driver.
On the Retroid Pocket Flip 2, that driver is Turnip on the Adreno 650.

Quiote is a launcher and a set of configuration files. Its installer
downloads Google's official Chrome build for Linux arm64 straight from Google
and runs it unmodified. Everything goes under `/storage`, so the read-only
ROCKNIX system is left alone.

## Status

| Device | ROCKNIX | GPU driver | WebGPU adapter |
|---|---|---|---|
| Retroid Pocket Flip 2 (SM8250) | nightly 20261101, Sway 1.11 | Turnip, Mesa 26.2.3 | `qualcomm adreno-6xx`, with `float32-filterable`, `shader-f16` and `timestamp-query` |

## Install

From portmart: **Net → Quiote**.

By hand, with `quiote-aarch64.tar.gz` from a release, on the device:

```sh
tar -xzf quiote-aarch64.tar.gz -C /storage/apps
/storage/apps/quiote/install.sh
```

Then in EmulationStation: **Start → Game Settings → Update Gamelists**, and
**Ports → Quiote**.

`install.sh --update-chrome` swaps in Google's latest build. The browser
does not update itself.

Ports → Quiote opens the WebGPU check page. It names the adapter, lists the
features WebGPU apps ask for, and keeps a compute pass and a render pass
running so you can see frames reach the screen. The window title carries the
verdict too: `Quiote: WebGPU qualcomm adreno-6xx`.

## Controls

The default layout (`controller/browse.yaml`) is for pages that don't read
the gamepad. Apps that do read it bring `gamepad.yaml` (below).

| Control | Action |
|---|---|
| Right stick | pointer |
| A, R2 | click |
| L2 | context menu |
| B / Y | back / forward |
| X | reload |
| Start | Enter |
| Select | full screen on/off |
| L1 / R1 | previous / next tab |
| D-pad | arrow keys |
| Left stick | page up / down |
| L3 / R3 | zoom out / in |
| Home | exit Quiote |

Touch works throughout. ROCKNIX's exit chord (L1 + Select + Start) also
closes Quiote. There is no on-screen keyboard: browse in Donkey.

## Running apps in Quiote

An app runs Quiote's `launch.sh` with Chrome arguments, usually
`--app=<url>` (a window with no browser toolbar). Quiote runs one window at a
time, full screen on its own Sway workspace. While it runs, Chrome's pid is
in `/run/quiote/chrome.pid`.

`install.sh` writes Quiote's home to `/storage/.config/quiote/home`.
Portmart puts apps where there is room, so apps find Quiote through that file.

| | Effect |
|---|---|
| `--serve <dir>` | The first argument(s). Serves `<dir>` at `http://127.0.0.1:<port>` for the session. Inside later arguments, `@serve@` becomes that address. With no other arguments it opens `--app=@serve@/`. Use it for apps that need http, e.g. ones with module workers, which `file://` can't load. |
| `QUIOTE_PROFILE=<name>` | Gives the app its own Chrome profile, `/storage/.config/quiote/<name>` (default `quiote`). |
| `QUIOTE_CONTROLLER=<yaml>` | Sets the InputPlumber profile for the session. Takes a path, or a file in Quiote's `controller/`. `gamepad.yaml` passes the pad through as an Xbox 360 pad, which Chrome reports with the `standard` mapping. Home stays mapped to exit. |
| `QUIOTE_SCALE=<n>` | Sets the device scale factor (default 1). |
| `QUIOTE_PORT=<n>` | Sets the port for `--serve` (default 8737). |
| `QUIOTE_ANGLE=vulkan\|gl` | Sets ANGLE's backend, which runs WebGL and shares canvases with the compositor (default `vulkan`). WebGPU apps need `vulkan` (below). WebGL apps need `gl`: with ANGLE on Vulkan, Turnip never shows a WebGL canvas created with `antialias: true` (the page draws, the screen stays empty). |
| `QUIOTE_FLAGS="<flags>"` | Adds extra Chrome flags, split on spaces, e.g. `--remote-debugging-port=9222`. |

An app's own `launch.sh`, for a release that unpacks its web build into `web/`:

```sh
#!/bin/sh
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
QUIOTE=$(cat /storage/.config/quiote/home) || { echo "Install Quiote first." >&2; exit 1; }
QUIOTE_PROFILE=myapp QUIOTE_CONTROLLER=gamepad.yaml \
  exec "$QUIOTE/launch.sh" --serve "$HERE/web" '--app=@serve@/?quality=low'
```

In its portmart manifest: `"depends": ["quiote"]`, and a launcher with
`"exec": "launch.sh"`.

## How WebGPU gets to the GPU

`launch.sh` starts Chrome with these flags:

- `--ozone-platform=wayland`
- `--enable-features=Vulkan`: Dawn, Chrome's WebGPU, uses the Vulkan driver.
  Without it, the only adapter is SwiftShader on the CPU.
- `--use-angle=vulkan` (`QUIOTE_ANGLE`): the canvas is shared with the
  compositor through Vulkan. With ANGLE on GL that import fails and the GPU
  device is lost (Dawn: "Requested allocation size ... is smaller than the
  image requires"). WebGL apps set `QUIOTE_ANGLE=gl`.
- `--enable-unsafe-webgpu --ignore-gpu-blocklist`: gets past the adapter
  blocklist.
- `--no-sandbox --test-type`: root is the only user on ROCKNIX, and Chrome's
  sandbox refuses to run as root. `--test-type` drops the warning bar that
  `--no-sandbox` brings. **Pages run unsandboxed**, so point Quiote at apps
  you trust.

Chrome warns that `--ozone-platform=wayland` "is not compatible with
Vulkan". The warning is about compositing; WebGPU runs on Vulkan regardless.

## Building

```sh
tools/package.sh   # dist/quiote-aarch64.tar.gz (+ .sha256): Quiote's home
tools/smoke.sh     # on-device end-to-end test (QUIOTE_HOST)
```

Deploy an unreleased build through portmart's dev channel, from a portmart
checkout:

```sh
tools/pm push flip2-12g quiote ~/quiote/dist/quiote-aarch64.tar.gz --manifest catalog/apps/quiote.json
```

## License

Quiote's own files are under the Mozilla Public License 2.0 (`LICENSE`).

Chrome is a trademark of Google LLC. Quiote is not affiliated with or
endorsed by Google. Quiote downloads the Chrome web browser from Google and
does not redistribute it; Google's terms of service for Chrome apply to it.
