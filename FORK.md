# The Apple fork

This repository, [bmanturner/halo-ce-universal](https://github.com/bmanturner/halo-ce-universal),
is a fork of [OpenCommunityEdition/OpenCE](https://github.com/OpenCommunityEdition/OpenCE),
by way of [AttilaTheFun/halo-ce-universal](https://github.com/AttilaTheFun/halo-ce-universal)'s
Apple port. Outside the Apple directories, it is OpenCE with the hooks that
the Apple apps need.

Up to date with OpenCE's `main` at
[`e0b581b1`](https://github.com/OpenCommunityEdition/OpenCE/commit/e0b581b157999e90382668dbc5578528e85701cc)
(2026-10-11), OpenCE's build 188.

## Releases

[Releases](https://github.com/bmanturner/halo-ce-universal/releases) has an
unsigned IPA for iPhone and iPad (iOS 16 or later). Sign it with your own
Apple account before installing: AltStore, SideStore or Sideloadly, or
[port/ios/RESIGNING.md](port/ios/RESIGNING.md) with Xcode's tools.

There is no Apple TV download: the Apple TV app contains your own game data,
so you build it yourself (`tools/tvos_build.py`, refer to
[port/tvos/README.md](port/tvos/README.md)).

## What the fork adds

Not in OpenCE:

- **iPhone, iPad, Mac and Apple TV apps** ([port/ios](port/ios/README.md),
  [port/macos](port/macos/README.md), [port/tvos](port/tvos/README.md)).
  The Apple TV app is a personal build with your own maps built into it. It
  draws with ANGLE's Metal backend, plays with game controllers, keeps saves
  in iCloud, and switches the TV to SDR while it is in front so the TV can
  use its game mode.
- **Server browser** in the Apple apps' own presentation of OpenCE's
  peer-to-peer browser.
- **Mouse sensitivity** from 1 to 100, finer at the low end.
- **B.Jumper** button layout (Halo 3's Bumper Jumper) in Gamepad Setup.
- **Touchpad scoreboard:** hold a DualSense or DualShock 4 touchpad to show
  the scoreboard.
- **Frame rate** setting in Video Settings: 30 Classic, 60 or Display, in
  place of Smooth Motion.
- **Render height** setting in Video Settings: draw at fewer pixels and
  upscale. **MetalFX upscaling** without per-frame CPU stalls.
- **Field of view** in Video Settings.
- **Game Mode** on iPhone and iPad: iOS gives the game priority and polls
  Bluetooth controllers twice as often.
- **Custom Edition maps on iPhone and iPad:** put them, with Halo PC's
  `bitmaps.map`, `sounds.map` and `loc.map`, in Files > Halo >
  CustomEdition > maps. The tag cache range is fixed for Custom Edition maps.
- **Map folder setting** (`paths.maps`).
- **Faster iOS rendering:** the vertex and index cache that OpenCE enables
  only on OpenGL ES 3.2 also runs on the iPad's ES 3.0.
- **Profile-guided optimisation** for the iOS build.
- Sockets are made again after iOS has had the app in the background.

None of these change what goes over the network, so public servers still work.
