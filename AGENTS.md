# Quiote

Quiote ("Don Quiote", Donkey's branch) sets up Google's unmodified Chrome
build on ROCKNIX as the runtime for WebGPU apps, with WebGPU on the device's
Vulkan driver. It is a launcher, controller profiles and a WebGPU check
page; `install.sh` downloads the browser on the device.

# Git
This repo lives at `mercurious/quiote`, with the noreply email
(`96538+mercurious@users.noreply.github.com`) as its git identity, and
starts on `main`. Commit locally after every turn; push after testing or
when the operator says to. The active `gh` account may switch to another
account: switch back to `mercurious` without commentary.

# Legal lines that shape the code
- **Never ship Chrome.** `install.sh` downloads Google's arm64 .deb at
  install time. Never put a Chrome binary or a modified Chrome in a release
  or in git.
- **Never put Chrome in the name.** Not in the project name or the port
  name, and no Chrome logo. "Quiote" is the user-facing name. Prose may say
  "the Chrome web browser", with the trademark and not-affiliated lines from
  the README.
- Quiote's own files are MPL-2.0.

# ROCKNIX
ROCKNIX is not garden-variety Linux: BusyBox, a read-only system, and root
as the only user. Check your assumptions on the device.
`mercurious/etk` has detailed ROCKNIX docs and tools.
- **Dev device:** Retroid Pocket Flip 2, ssh alias `flip2-12g` (Tailscale)
  or `flip2-12g-usb` (USB networking, `169.254.170.6`), key `~/.ssh/etk_rig`.
  The screen is 1920x1080 landscape at scale 1. Quiote is installed there
  through portmart, in `/storage/games-external/quiote`.
- **GPU:** Turnip Adreno 650, Mesa 26.2.3 (ETK-GTK build), Vulkan 1.3.
  Chrome's WebGPU needs `--enable-features=Vulkan` and `--use-angle=vulkan`
  (see README "How WebGPU gets to the GPU"); without either it falls back
  to SwiftShader or loses the device.
- **Unpacking:** BusyBox `xz` can't open Google's `data.tar.xz`, which has a
  256 MiB dictionary. `install.sh` uses Python's `lzma`.
- **Session:** Sway 1.11. `XDG_RUNTIME_DIR=/run/0-runtime-dir`,
  `WAYLAND_DISPLAY=wayland-1`, socket `sway-ipc.0.sock`. SSH sessions don't
  source `/etc/profile`; set these yourself.
- **Controller:** InputPlumber at `CompositeDevice0`. Profiles load with
  `LoadProfilePath`; restarting `inputplumber.service` restores the stock
  gamepad. `SendButtonChord`/`SendEvent` inject presses.

# Validation with the owner
Never ask the owner-operator to do drudge work (scripted button presses,
click-through checklists) to tick off an edge case. Validate with
`tools/smoke.sh`, `grim` screenshots and our own instrumentation; the owner
reports bugs from normal use.
- `QUIOTE_FLAGS=--remote-debugging-port=9222` plus `ssh -L 9222:...` gives
  CDP on the device's Chrome (Playwright `connectOverCDP`).
