# YellowDot (menubar overlay fork)

###### Recolor any macOS menubar item with a color of your choosing

This is a personal fork of [YellowDot by FuzzyIdeas](https://lowtechguys.com/yellowdot).
Upstream hides the macOS recording/location indicator dot. This fork was repurposed to do
one thing instead: **paint a solid color over menubar items you pick.**

Automatic detection of the recording indicator has been removed — nothing is overlaid until
you add a target yourself.

## How it works

- The picker lists on-screen menubar items; hovering one outlines it on screen so you can
  tell which is which.
- Adding a target records its owner, window name, and size. The matching window is made
  transparent (`CGSSetWindowAlpha`) and a borderless colored pill is drawn in its place.
- Targets are remembered across launches, can be toggled on and off individually, and share
  a single overlay color.

## Settings

Menubar icon → **Settings...**:

- **Show menubar icon** — hide the icon; the Settings window opens on relaunch instead.
- **Launch at login**
- **Indicator overlay color** — applies to every active overlay.
- **Active Overlays** — the target list, with an **Add Overlay Target** picker.

## Requirements

macOS 13+ and **Screen Recording** permission (needed to enumerate window names and sizes).
The app prompts on first launch; grant it in System Settings → Privacy & Security → Screen
Recording.

## Build

```sh
./build.sh
```

Archives the Xcode project with ad-hoc signing and drops `YellowDot.app` in `build/export`.
Drag it to `/Applications`.

## Uninstall

```sh
./uninstall.sh
```

Quits the app, removes it from `/Applications`, resets its TCC permissions (asks for `sudo`),
and clears its launch agent, preferences, caches, and saved state.

## License

Upstream license retained — see [LICENSE](LICENSE).
