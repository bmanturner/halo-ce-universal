# Halo: Combat Evolved for iPhone, iPad and Apple TV

A port of the Halo: Combat Evolved decompilation (Xbox build 2342,
`cachebeta.exe`, SHA-256
`4cc87b45f721270392a96f1674ed2b5cd4a7bb4355faeab4531d1cf1884d9520`). It starts
from [OpenCommunityEdition/OpenCE](https://github.com/OpenCommunityEdition/OpenCE),
by way of [AttilaTheFun/halo-ce-universal](https://github.com/AttilaTheFun/halo-ce-universal)'s
Apple port.

Up to date with OpenCE's `main` at
[`9da2a45f`](https://github.com/OpenCommunityEdition/OpenCE/commit/9da2a45ffa364b720ae9faab6a1dee876926fe42)
(2026-10-10), OpenCE's build 177.

## This fork

I fixed some stuff on iOS. Now that it works, I'm just adding stuff I like.
Not in upstream OpenCE:

- **B.Jumper** button layout (Halo 3's Bumper Jumper) in Gamepad Setup.
- **Touchpad scoreboard:** hold a DualSense or DualShock 4 touchpad to show
  the scoreboard.
- **Render height** setting in Video Settings (iOS): draw at fewer pixels
  and upscale, after a relaunch.
- **Frame rate** setting in Video Settings (iOS): 30 Classic, 60 or Display,
  in place of Smooth Motion. At 60 each frame is shown as soon as it is drawn,
  and the wait for the next comes before it reads the controls.
- **Game Mode** on iPhone and iPad: iOS gives the game priority and polls
  Bluetooth controllers twice as often.
- **Custom Edition maps on iPhone and iPad:** put them, with Halo PC's
  `bitmaps.map`, `sounds.map` and `loc.map`, in Files > Halo >
  CustomEdition > maps.
- **MetalFX upscaling** without per-frame CPU stalls, upscaling from the
  render height.
- **Faster iOS rendering:** the vertex and index cache that upstream enables
  only on OpenGL ES 3.2 now runs on the iPad's ES 3.0.
- **Profile-guided optimisation** for the iOS build.
- **Apple TV app** ([port/tvos](port/tvos/README.md)): a personal build with
  your own maps built into the app. It draws with ANGLE's Metal backend
  (built from source for tvOS), plays with game controllers, keeps saves in
  iCloud, and switches the TV to SDR while it is in front so the TV can use
  its game mode.

None of these change what goes over the network, so public servers still work.

## Download

[Releases](https://github.com/bmanturner/halo-ce-universal/releases) has an
unsigned IPA for iPhone and iPad (iOS 16 or later). Sign it with your own
Apple account before installing: AltStore, SideStore or Sideloadly, or
[port/ios/RESIGNING.md](port/ios/RESIGNING.md) with Xcode's tools.

There is no Apple TV download: the Apple TV app contains your own game data,
so you build it yourself.

## Build and install

Both need an Apple Silicon Mac with Xcode.

### iPhone and iPad

```sh
python3 tools/ios_build.py --team YOUR_TEAM_ID --bundle-id com.yourname.haloce
xcrun devicectl device install app --device DEVICE_ID build/ios/app-device/Release-iphoneos/HaloCE.app
```

[port/ios/README.md](port/ios/README.md) has the toolchain, the simulator,
signing and troubleshooting.

### Apple TV

Pair the Apple TV with Xcode first: on the Apple TV, open Settings > Remotes
and Devices > Remote App and Devices; on the Mac, Xcode > Window > Devices
and Simulators. Then:

```sh
python3 tools/tvos_build.py --team YOUR_TEAM_ID --bundle-id com.yourname.haloce.tv \
    --game-data ~/HaloData/maps --install APPLE_TV_ID
```

`--game-data` is a folder with your Xbox maps (see "Game data") and
`APPLE_TV_ID` comes from `xcrun devicectl list devices`. Add
`--custom-edition DIR` for Custom Edition maps and
`--icloud-container iCloud.com.yourname.haloce` for iCloud saves. It needs
a paid Apple developer team. The first build also builds ANGLE for tvOS from
source: about 7 GB and 10 minutes. [port/tvos/README.md](port/tvos/README.md)
has the details, the controls and what differs from iOS.

## Game data

The apps do not include the game data. Use your own Xbox disc image (`.iso`
or `.xiso`) of Halo: Combat Evolved.

- **iPhone and iPad:** at the first start, tap **Choose Halo ISO** and select
  it in Files. Refer to "Install and add game data" in
  [port/ios/README.md](port/ios/README.md).
- **Apple TV:** tvOS has no Files app, so the maps are built into the app.
  Extract them on the Mac with
  `python3 tools/ios_extract_assets.py YOUR.iso --output ~/HaloData`, which
  writes `~/HaloData/maps`, or copy them from the iPhone or iPad app (refer to
  "Game data" in [port/tvos/README.md](port/tvos/README.md)). A build made
  this way contains your game data: keep it to yourself.

## Multiplayer

**Multiplayer → Join Game → Server Browser** lists public internet games of
the same network version; joins go peer to peer, with no server of this
project. Refer to [port/linux/NETCODE.md](port/linux/NETCODE.md) for the
netcode.

## Other platforms

This fork supports iPhone, iPad and Apple TV only. The code also contains
ports to Linux, Windows, Android, the web and the Mac, with their
instructions in
[port/linux](port/linux/README.md), [port/windows](port/windows/README.md),
[port/android](port/android/README.md), [port/web](port/web/README.md) and
[port/macos](port/macos/README.md), but this fork does not build, test or
release them, and they may not work. For Linux, Windows and Android, use
[OpenCE](https://github.com/OpenCommunityEdition/OpenCE).
