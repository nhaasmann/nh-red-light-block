# NH Red Light Block

A tiny macOS menu-bar app from the NH Private Health Office. It removes blue and green light from your display at night, so your screen glows red only, and gives you your full screen back in the morning.

**[Download for Mac](https://github.com/nhaasmann/nh-red-light-block/releases/latest/download/NH-Red-Light-Block.dmg)** · [Website](https://nhaasmann.github.io/nh-red-light-block/)

## What it does

- **Red only at night.** Warm filters such as Night Shift leave green in. This sets the green and blue channels to zero, leaving the red primary, which the body clock's photoreceptor (melanopsin, peak near 480 nm) barely responds to.
- **Follows your sun.** Amber from 30 minutes before sunset, red from two hours before bedtime until you wake, unfiltered in the morning. Sunset comes from your location, worked out on your Mac.
- **One slider.** Manual mode sets any strength between unfiltered and red only. Control + Option + Command + R switches the filter off and on.
- **Live spectrum chart.** Settings shows an estimate of the light your screen is emitting. It is computed from the live channel output, the display's colour profile and approximate panel emission peaks. It is a model, not a sensor measurement.

## Install

1. Open the downloaded DMG and drag the app to Applications.
2. Open it. The app is not notarised, so the first time go to System Settings > Privacy & Security and click Open Anyway.
3. Click the sun or moon in the menu bar. In Settings, click Use My Location and set your wake time and bedtime.

Needs macOS 14 or newer. Nothing leaves your Mac. Quitting the app restores normal colour.

## Honest limits

- A display cannot add blue light, so the morning mode is an unfiltered, slightly cooler screen. Real morning light comes from outdoors.
- The filter uses the display gamma table. On some macOS 26 setups (reported on M5 Pro/Max, and with HDR plus auto-brightness) the system ignores it. The app checks and warns if the filter did not take.
- This is a wellness tool, not medical advice.

## Build from source

Requires Xcode command line tools (Swift 6).

```bash
swift test
```

```bash
./build.sh
```

The build writes `dist/NH Red Light Block.app` and `dist/NH Red Light Block.dmg`.

- `Sources/RedLightCore`: sunrise/sunset maths and the schedule, unit tested
- `Sources/RedLightBlock`: the menu-bar app (SwiftUI)
- `docs/`: the website
- `PLAN.md`: original design notes

## Credits

Made by Nick Haasmann, NH Private Health Office. Schedule timing follows the light-timing guidance on calibrate.day and Brown et al. 2022 (PLOS Biology).

© 2026 NH Private Health Office. All rights reserved. Fonts on the website (Inter, Newsreader) are used under the SIL Open Font License; see `docs/fonts`.
