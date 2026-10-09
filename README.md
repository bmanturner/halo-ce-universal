# Halo: Combat Evolved for iPhone and iPad

A port of the Halo: Combat Evolved decompilation (Xbox build 2342,
`cachebeta.exe`, SHA-256
`4cc87b45f721270392a96f1674ed2b5cd4a7bb4355faeab4531d1cf1884d9520`). It starts
from [OpenCommunityEdition/OpenCE](https://github.com/OpenCommunityEdition/OpenCE),
by way of [AttilaTheFun/halo-ce-universal](https://github.com/AttilaTheFun/halo-ce-universal)'s
Apple port.

## This fork

I fixed some stuff on iOS. Now that it works, I'm just adding stuff I like,
such as a Bumper Jumper ("B.Jumper") controller layout.

## Build and install

On an Apple Silicon Mac with Xcode:

```sh
python3 tools/ios_build.py --team YOUR_TEAM_ID --bundle-id com.yourname.haloce
xcrun devicectl device install app --device DEVICE_ID build/ios/app-device/Release-iphoneos/HaloCE.app
```

[port/ios/README.md](port/ios/README.md) has the toolchain, the simulator,
signing and troubleshooting.

## Game data

The app does not include the game data. Use your own Xbox disc image (`.iso`
or `.xiso`) of Halo: Combat Evolved: at the first start, tap **Choose Halo
ISO** and select it in Files. Refer to "Install and add game data" in
[port/ios/README.md](port/ios/README.md).

## Multiplayer

**Multiplayer → Join Game → Server Browser** lists public internet games of
the same network version; joins go peer to peer, with no server of this
project. Refer to [port/linux/NETCODE.md](port/linux/NETCODE.md) for the
netcode.

## Other platforms

The code still builds for Linux, Windows, Android and the web; their
instructions are in [port/linux](port/linux/README.md),
[port/windows](port/windows/README.md), [port/android](port/android/README.md)
and [port/web](port/web/README.md).
