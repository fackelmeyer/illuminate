# Illuminate

[![CI](https://github.com/fackelmeyer/illuminate/actions/workflows/ci.yml/badge.svg)](https://github.com/fackelmeyer/illuminate/actions/workflows/ci.yml)
![Swift 6.4](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue)](LICENSE)

A menu-bar app that unlocks the extra brightness of XDR displays for everyday (SDR) content, using only public macOS APIs.

On a MacBook Pro with a Liquid Retina XDR panel, macOS caps desktop content at 500–600 nit, although the panel sustains 1000 nit full-screen. Illuminate asks WindowServer for EDR headroom and lifts SDR content into it, by up to 2× of the current SDR white.

## Requirements

- macOS 14 or later to run; Xcode 27 or later (Swift 6.4) to build
- A display that reports `maximumPotentialExtendedDynamicRangeColorComponentValue ≥ 2`: MacBook Pro 14"/16" (M1 Pro or later), Pro Display XDR, Studio Display XDR. Other HDR monitors may work but have not been tested.

## Install

```sh
scripts/dmg.sh             # builds build/Illuminate-<version>.dmg
```

Open the disk image, drag **Illuminate** onto **Applications**, eject the image, and start Illuminate from the Applications folder. To start it automatically, choose **Launch at Login** in its menu. Illuminate then appears under System Settings › General › Login Items, where you can also switch it off.

The menu item is greyed out while Illuminate runs from the disk image, because macOS would record a path that disappears when you eject the image.

## Build and run (development)

```sh
swift test                 # unit tests for the core logic
scripts/bundle.sh          # builds and ad-hoc signs build/Illuminate.app
open build/Illuminate.app
swift scripts/make-icon.swift   # regenerates Support/AppIcon.icns
```

Ad-hoc signing is enough on the Mac that built the app. Other Macs block it through Gatekeeper. To distribute it, sign with a Developer ID (`SIGN_IDENTITY="Developer ID Application: …" scripts/dmg.sh`) and notarize the disk image with `xcrun notarytool`.

## Usage

| | |
|---|---|
| ⌃⌥⌘I | Toggle the boost |
| ⌃⌥⌘↑ / ↓ | Raise or lower the boost by 10 % |
| Menu bar ☀︎ | Slider, method, pause rules, Launch at Login |

The boost follows the system brightness slider: full boost means 2× the current SDR white. The app also caps it at 60 % of the live EDR headroom, which keeps a 1600-nit panel near its 1000-nit full-screen limit.

## How it works

Illuminate has two techniques, and you can switch between them under **Method**.

**Overlay (default).** Illuminate puts a borderless, click-through window over each display, at shielding level. The window contains a `CAMetalLayer` set up like this:
- `wantsExtendedDynamicRangeContent = true`
- `.rgba16Float` pixel format in extended linear sRGB
- `compositingFilter = "multiply"`

The layer is cleared to a 1×1 drawable of value *k* > 1, so WindowServer multiplies everything beneath it by *k*.
- HDR video is multiplied rather than clipped.
- If the app dies, the window disappears with it, so no system state is left behind.

**Gamma table.** A 1×1 EDR trigger window keeps headroom granted. Meanwhile Illuminate scales the display's *captured* transfer table with `CGSetDisplayTransferByTable`, so calibration is preserved.
- Colours stay faithful.
- HDR video clips, and it conflicts with f.lux.
- It is disabled on M5 Pro and M5 Max, where macOS ignores gamma tables (FB22273730, [Apple Developer Forums](https://developer.apple.com/forums/thread/819331); still open on macOS 27).

### Robustness

- **Per-display engagement:** A state machine (`idle → engaging → ready`, with `cooldown` and `isolated`) waits for headroom before applying any gain. A display that refuses EDR never affects another display.
- **Pausing:** The boost pauses for the screen saver, lock screen, fast user switching, sleep and display sleep. Pause reasons form a *set*, so the boost resumes only when every reason has cleared.
- **Power:** By default the boost pauses on battery below 20 % and in Low Power Mode. Both rules can be changed in the menu.
- **Video:** When a video player holds a display-sleep power assertion, the gain drops to 1. The overlay stays up so headroom isn't lost.
- **Gamma safety:**
  - A drift watchdog runs every 5 s and accounts for readback clamping at 1.0.
  - It detects an all-black ("zero gamma") table.
  - The table is restored at exit, on SIGTERM/SIGINT/SIGHUP/SIGQUIT, and at the next launch if the previous session crashed.
- **Overlay hygiene:**
  - The overlay presents at 5 fps; otherwise WindowServer promotes the idle window to direct scan-out and drops the filter.
  - The window fades in only after the first frame is on screen.
  - At most 2 frames are in flight.
  - The window is re-anchored on every tick.
  - It is hidden from VoiceOver.

## Engineering notes

- **Logic without AppKit.** Every decision the app makes (gain, engagement, pausing, power rules, preference decoding, install location) lives in `IlluminateCore`, which does not import AppKit. Time and system state are passed in, so the Swift Testing suite runs the state machines deterministically and in parallel.
- **Thin app shell.** `BoostController` is the single source of truth. Monitors feed it events, and the menu only renders its state.
- **Concurrency.** The app target is main-actor by default with Approachable Concurrency. The C callbacks (Carbon hotkeys, IOKit power, display reconfiguration) are `nonisolated` and enter the main actor with `MainActor.assumeIsolated`, which traps instead of racing if the assumption ever breaks.
- **Strict compiler settings.** Swift 6 language mode, `ExistentialAny`, `MemberImportVisibility` and `InternalImportsByDefault` in every target, and warnings as errors. `IlluminateCore` also builds with strict memory safety.
- **CI.** Every push and pull request builds, tests and bundles the app on GitHub's Xcode 27 runner.

## Project layout

```
Sources/IlluminateCore/   Pure logic, no AppKit, fully unit-tested
  BoostCurve              level → gain, headroom and nits caps, nits estimate
  EngagementMachine       per-display EDR engagement state machine
  SuspensionState         set of pause reasons
  GammaTable              scale / clamp / compare / degenerate detection
  DisplayProfile          eligibility and known panel peaks
  Preferences             lenient Codable settings, PowerStatus rules
  PlatformQuirks          M5 Pro/Max gamma bug, playback heuristic
Sources/Illuminate/       The app (main actor by default)
  BoostController         single source of truth; owns one DisplayBooster per display
  Display/                EDRWindow (Metal surface), techniques, gamma controller
  System/                 system events, power, playback, Carbon hotkeys
  UI/                     status menu, login item
Tests/IlluminateCoreTests Swift Testing
```

## Known limitations

- **Screenshots and screen recordings include the boost.** The multiplied pixels clip to SDR white. Excluding the overlay with `sharingType = .none` would turn captures black, because the multiply then applies against an empty window.
- **Full-screen video and some games:** Other XDR tools report that the boost fades after about 10 s in full-screen video on the macOS 27 beta ([BrightIntosh #301](https://github.com/niklasr22/BrightIntosh/issues/301)), and that some games withdraw the headroom while they are in front ([BrightIntosh #309](https://github.com/niklasr22/BrightIntosh/issues/309)). The engagement machine re-requests EDR, but this has not been verified here.
- **Light and wear:** Higher brightness costs battery and adds some LED wear. macOS's own thermal limiter stays in charge. Dark Mode keeps the panel cooler.
- **Undocumented filter name:** `"multiply"` is an undocumented compositing filter name on a public property.

## Manual test checklist (per release)

Run each of these with the boost on for at least 10 minutes:
- Space switch
- Mission Control
- Full-screen video, both SDR and HDR
- Sleep and wake
- Lock and unlock
- Screen saver
- Lid close and open
- Plugging in an external display
- Switching Method back and forth quickly (each switch re-creates the Metal windows)

Repeat the run on M1/M2 (500 nit), M3 (600 nit), M4/M5 (1000 nit outdoor) and M5 Pro/Max (gamma disabled).

## Prior art

Other apps that brighten XDR displays beyond the SDR limit:

- [BrightIntosh](https://github.com/niklasr22/BrightIntosh) (open source, GPL-3.0). Its issue tracker documents many of the macOS edge cases listed above.
- [Vivid](https://www.getvivid.app/) (commercial)
- [Lunar](https://lunar.fyi/) (commercial, "XDR Brightness" feature)

## License

[MIT](LICENSE) © 2026 Jonas Fackelmeyer
