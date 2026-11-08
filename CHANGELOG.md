# Changelog

## 1.1.3 — 2026-11-08
- Works with monitors turned to portrait. The sharper modes now match the panel's own orientation, so an upright 1920 × 1080 screen gets 1053 × 1872 and the other sizes.
- Ignores the few small HiDPI modes macOS adds by itself, some in a different aspect ratio (600 × 800 on an upright 1080p screen). They are no longer offered as sizes, and Turn On no longer picks one by mistake.

## 1.1.2 — 2026-11-08
- App icon.

## 1.1.1 — 2026-10-31
- Shows the copyright in the window and in the About panel.
- Shows "External Display" instead of a blank name for virtual displays, such as the one macOS creates for remote sessions.

## 1.1 — 2026-10-31
### Fixed
- **VRR (Adaptive Sync) stays on after switching.** macOS lists every refresh rate twice, as a fixed and a variable variant that look identical through the public API. SharpDisplay now asks the window server which one is variable and always uses it. In 1.0 it could land on the fixed variant, so you had to pick *Variable* again in System Settings.

### New
- **Pick your size in the app.** A menu under the status line lets you choose from *More Space* (2496 × 1404 on a 1440p monitor) to *Larger Text* (1600 × 900). Switching sizes is instant and needs no password.
- **Ultrawide monitors.** Monitors are now judged by height instead of width, so 3440 × 1440, 3840 × 1600 and 5120 × 1440 panels are supported. Very wide panels need a large framebuffer, so some Macs may not offer the biggest sizes.
- **Universal app.** Runs natively on Apple Silicon and Intel Macs (tested on Apple Silicon).

## 1.0 — 2026-10-30

First release: one-button HiDPI for sub-4K external monitors.
