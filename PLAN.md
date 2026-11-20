# RedLightBlock — implementation plan

A tiny macOS menu-bar app that removes all green and blue light from the display at
night (pure red screen), eases in through amber at sunset, and gives a cool,
unfiltered screen in the morning. Schedule is driven by geolocation (sunrise/sunset)
plus the user's wake time and bedtime.

Target: Apple Silicon Macs running macOS 14 or newer.

## Research findings that shape the design

- **calibrate.day** is not a screen app. It is a daily light-timing plan: bright light
  soon after waking, dim and warm light as bedtime nears ("dim it, warm it"), dimming
  starts about 2 h before sleep. Sample day: wake 06:30, dim 20:30, sleep 22:30.
  It cites Brown et al. 2022 (PLOS Biology): daytime >= 250 melanopic lux, evening
  (last 3 h before bed) <= 10, sleep <= 1. We take its timing model: the schedule is
  anchored to wake time and bedtime, with the sun deciding when evening starts.
- **Why red-only**: melanopsin (the circadian photoreceptor) peaks near 480 nm and is
  still sensitive through green (~550 nm). f.lux and Night Shift only warm the white
  point, so green stays. Setting the green and blue channels to zero leaves only the
  red primary (~630 nm), where melanopic sensitivity is close to nil.
- **Existing tools**: f.lux (closed source, has a "darkroom" red mode but inverts
  colours), Night Shift (warm only), Iris (paid), Luma (github.com/chountalas/luma,
  MIT, Swift, gamma table + overlay fallback, warm/dim only). None is a simple,
  open, red-only scheduler. Luma's source confirms the technique and its pitfalls.
- **Technique**: `CGSetDisplayTransferByFormula` (per-channel gamma). The system
  restores the tables automatically when the process exits, so a crash can never
  leave the screen stuck red. macOS resets tables on wake, display reconfiguration
  and login, so we must re-apply (timer + notifications).
- **Known macOS 26 risk**: on M5 Pro/Max the gamma API returns success but does
  nothing; on built-in XDR panels with auto-brightness + HDR content it can behave
  oddly. The app reads the table back with
  `CGGetDisplayTransferByTable` and shows a warning if the filter did not take.
- **Honest limit of the "morning boost"**: a display cannot emit more blue than its
  native white. Gamma can only cut red, which makes white look cooler but adds no
  melanopic light. So morning mode = guaranteed unfiltered screen + optional mild
  cool tint, and the UI says that real morning light comes from outdoors.

## Behaviour

Inputs: latitude/longitude (CoreLocation, or typed in), wake time (default 06:30),
bedtime (default 22:30).

| Phase | When | Channel gains (R, G, B) |
|---|---|---|
| Morning boost | wake -> wake + 2 h | 0.88, 0.96, 1.00 (if boost on, else neutral) |
| Day | until 30 min before sunset | 1, 1, 1 |
| Evening amber | sunset - 30 min -> wind-down | 1.00, 0.55, 0.15 |
| Night red | wind-down (bedtime - 2 h) -> wake | redLevel, 0, 0 |

- Transitions are linear ramps: 30 min into amber, 30 min into red, 20 min into
  morning (so waking is a red -> cool sunrise on screen).
- If sunset is later than wind-down (summer), red starts at wind-down anyway.
- If there is no location yet, sunset falls back to 19:00 and sunrise to 07:00.
- `redLevel` (0.3 ... 1.0, default 1.0) dims the red screen.
- Modes: Auto, Red now, Amber now, Off. "Pause 1 hour" returns to Auto afterwards.
- Global hotkey Ctrl+Option+Cmd+R toggles Off <-> Auto (escape hatch, since a red
  screen makes colour work impossible).

## Structure (Swift Package, no Xcode project)

```
Package.swift                      macOS 14+, targets below
Sources/RedLightCore/              pure logic, no AppKit, fully unit-tested
  SunCalculator.swift              NOAA sunrise/sunset for date + lat/lon
  ColorGains.swift                 struct r,g,b + lerp
  Schedule.swift                   Settings + time -> (phase, gains, nextChange)
Sources/RedLightBlock/             the app
  main / App.swift                 SwiftUI MenuBarExtra(.window), LSUIElement
  AppState.swift                   ObservableObject, UserDefaults, 10 s tick
  GammaController.swift            apply to all active displays, readback check,
                                   re-apply on wake / screen change, restore on quit
  LocationProvider.swift           CLLocationManager one-shot, cached in defaults
  HotKey.swift                     Carbon RegisterEventHotKey
  MenuView.swift                   the popover UI
Tests/RedLightCoreTests/           sun times vs known values, phase boundaries, ramps
Resources/Info.plist               LSUIElement, NSLocationUsageDescription, bundle id
build.sh                           swift build -c release -> RedLightBlock.app, ad-hoc codesign
README.md                          what it does, science, limits, build/run
```

CLI flags on the same binary, for verification without the UI:
- `--status` prints location, today's sunrise/sunset, current phase and gains.
- `--probe` applies pure red for 2 s, reads the table back, prints PASS/FAIL, restores.

## UI (one small popover)

Phase name + "next change at HH:MM"; mode picker; wake and bedtime pickers; red
brightness slider; morning boost toggle; location line with "Use my location" and
manual lat/lon fields; launch at login (SMAppService); warning line if the gamma
readback fails; Pause 1 h; Quit. Menu-bar icon reflects the phase.

## Done means

1. `swift test` passes (sun times within 2 min of reference, phase logic, ramps).
2. `./build.sh` produces `RedLightBlock.app`.
3. `--probe` reports PASS on this Mac (green and blue tables read back as zero).
4. The app launches, shows in the menu bar, and the screen follows the schedule.
5. Quitting restores normal colour.

## Not in scope

Per-app exclusions, per-display settings, overlay fallback, brightness hardware
control, notarisation, auto-update.
