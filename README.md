# SharpDisplay

**Sharp, Retina-style text on 1440p and 1080p monitors connected to Apple Silicon Macs. One button.**

macOS only renders text at 2x (HiDPI) on displays it considers Retina — 4K and up. On a 27" 1440p monitor
text is drawn at 1x and looks soft, because macOS no longer uses subpixel antialiasing.
SharpDisplay adds real HiDPI modes for your monitor, so macOS renders everything at twice the resolution
and scales it down to the panel.

| Before | After |
|---|---|
| 2560 × 1440, rendered at 1x | Looks like 2496 × 1404, rendered at 4992 × 2808 |

- **One button.** Turn On adds the modes and switches to the sharpest one. Turn Off puts everything back.
- **No virtual display, no mirroring.** Full refresh rate and VRR (Adaptive Sync) keep working, no added latency.
- **Nothing runs in the background.** The app changes a system setting and can be quit; the mode stays.
- **Almost no lost space.** The largest mode is 97.5% of the native width. Smaller ones are there for a larger UI.

## Requirements

- Mac with Apple Silicon
- macOS 14 Sonoma or later
- An external monitor below 4K (for example 2560 × 1440 or 1920 × 1080)

## Install

1. Download `SharpDisplay.zip` from [Releases](../../releases) and move `SharpDisplay.app` to Applications.
2. The app isn't notarized yet, so the first time **right-click it → Open → Open**.
3. Press **Turn On** and enter your administrator password.

The screen goes dark for 2–4 seconds while macOS reloads the display, then comes back sharper.
Pick another size any time in **System Settings → Displays** (turn on *Show all resolutions*).

> After switching modes macOS may set the refresh rate to a fixed value. If your monitor supports it,
> choose **Variable** again in System Settings → Displays.

## How it works

SharpDisplay does what you could do by hand with a few commands:

1. Writes a display override file for your monitor model to
   `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-<vendor>/DisplayProductID-<product>`
   with HiDPI `scale-resolutions` at 97.5%, 90%, 80%, 75% and 62.5% of the native width.
   (macOS ignores a HiDPI mode equal to the native resolution, which is why the largest one is 97.5%.)
2. Sets `DisplayResolutionEnabled` in `/Library/Preferences/com.apple.windowserver`.
3. Briefly reconnects the display in software so macOS reads the new modes, then switches to the largest one.

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

Produces `build/SharpDisplay.app` and `build/SharpDisplay.zip`. Needs Xcode command line tools. No dependencies.

## Credits

The override approach comes from the macOS display community, in particular
[BetterDisplay](https://github.com/waydabber/BetterDisplay) and
[kirakirag/hidpi](https://github.com/kirakirag/hidpi).

## License

MIT
