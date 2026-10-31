# SharpDisplay

**Sharp, Retina-style text on 1440p, 1080p and ultrawide monitors connected to a Mac. One button.**

macOS only renders text at 2x (HiDPI) on displays it considers Retina — 4K and up. On a 27" 1440p monitor
text is drawn at 1x and looks soft, because macOS no longer uses subpixel antialiasing.
SharpDisplay adds real HiDPI modes for your monitor, so macOS renders everything at twice the resolution
and scales it down to the panel.

| Before | After |
|---|---|
| 2560 × 1440, rendered at 1x | Looks like 2496 × 1404, rendered at 4992 × 2808 |

- **One button.** Turn On adds the modes and switches to the sharpest one. Turn Off puts everything back.
- **Pick your size.** Choose between more space and larger text right in the app; switching sizes needs no password.
- **No virtual display, no mirroring.** Full refresh rate and VRR (Adaptive Sync) keep working, no added latency.
  SharpDisplay always picks the variable refresh variant of a mode when your monitor has one.
- **Nothing runs in the background.** The app changes a system setting and can be quit; the mode stays.
- **Almost no lost space.** The largest mode is 97.5% of the native width. Smaller ones are there for a larger UI.

## Requirements

- Mac with Apple Silicon or Intel (tested on Apple Silicon)
- macOS 14 Sonoma or later
- An external monitor less than 2160 pixels tall: 2560 × 1440, 1920 × 1080, 3440 × 1440, 5120 × 1440 and similar

## Install

1. Download `SharpDisplay.zip` from [Releases](../../releases) and move `SharpDisplay.app` to Applications.
2. The app isn't notarized yet, so the first time **right-click it → Open → Open**.
3. Press **Turn On** and enter your administrator password.

The screen goes dark for 2–4 seconds while macOS reloads the display, then comes back sharper.
Pick another size from the menu under the status line, or in **System Settings → Displays**.

> Very wide monitors such as 5120 × 1440 need a very large HiDPI framebuffer (about 10000 × 2800).
> Some Macs, especially those with base M1 chips, may not offer the largest sizes.

## How it works

SharpDisplay does what you could do by hand with a few commands:

1. Writes a display override file for your monitor model to
   `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-<vendor>/DisplayProductID-<product>`
   with HiDPI `scale-resolutions` at 97.5%, 90%, 80%, 75% and 62.5% of the native width.
   (macOS ignores a HiDPI mode equal to the native resolution, which is why the largest one is 97.5%.)
2. Sets `DisplayResolutionEnabled` in `/Library/Preferences/com.apple.windowserver`.
3. Briefly reconnects the display in software so macOS reads the new modes, then switches to the size you picked.
   macOS lists every refresh rate twice, as a fixed and a variable variant; SharpDisplay asks the window server
   which one is variable and uses it, so Adaptive Sync stays on.

An override file that already existed (for example from BetterDisplay) is backed up to
`/Library/Application Support/SharpDisplay/Backups` and restored by Turn Off.

To check what would be installed without changing anything:

```sh
/Applications/SharpDisplay.app/Contents/MacOS/SharpDisplay --print-plist
```

### Uninstall by hand

```sh
sudo rm /Library/Displays/Contents/Resources/Overrides/DisplayVendorID-<vendor>/DisplayProductID-<product>
```

then unplug and replug the monitor (or restart).

## Build

```sh
./build.sh
```

Produces a universal (Apple Silicon and Intel) `build/SharpDisplay.app` and `build/SharpDisplay.zip`.
Needs Xcode command line tools. No dependencies.

## Credits

The override approach comes from the macOS display community, in particular
[BetterDisplay](https://github.com/waydabber/BetterDisplay) and
[kirakirag/hidpi](https://github.com/kirakirag/hidpi).

## License

MIT
